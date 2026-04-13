local Qfrun = {
  ["cpp"] = { "g++ -Wall ${SRC} -o ${TARGET} && ./${TARGET}" },
  ["python"] = { "python ${SRC}" },
  ["lua"] = { "nvim -l ${SRC}" },
  ["sh"] = { "bash ${SRC}" },

  parse_stdout_as_stderr = false,
  project_config_name = ".env",
  enable_diagnostic = false,
  last_cmd = nil,
  qf_id = nil,
  qf_buf = -1,
  job = nil, ---@type vim.SystemObj?
  job_status = false,
  src_dir = nil,
  exec_id = 0,
  diagnostics = {},
}

local severity = {
  E = vim.diagnostic.severity.ERROR,
  W = vim.diagnostic.severity.WARN,
  N = vim.diagnostic.severity.INFO,
}

local qf_ns = vim.api.nvim_create_namespace("Qfrun")
local function get_relative_path(base, target)
  -- 1. 规范化路径：转为绝对路径并统一分隔符
  local function normalize(p)
    return vim.fn.fnamemodify(p, ":p"):gsub("\\", "/"):gsub("/$", "")
  end

  local b_split = vim.split(normalize(base), "/", { trimempty = true })
  local t_split = vim.split(normalize(target), "/", { trimempty = true })

  -- 2. 找出公共前缀
  local i = 1
  while i <= #b_split and i <= #t_split and b_split[i] == t_split[i] do
    i = i + 1
  end

  -- 3. 计算需要向上跳多少层 (..)
  local ups = {}
  for _ = i, #b_split do
    table.insert(ups, "..")
  end

  -- 4. 拼接目标剩余路径
  local remains = {}
  for j = i, #t_split do
    table.insert(remains, t_split[j])
  end

  local res = table.concat(vim.list_extend(ups, remains), "/")
  return res == "" and "." or res
end

function Qfrun.setup(opts)
  for key, val in pairs(opts) do
    Qfrun[key] = val
  end
end

local function parse_err(stderr, save_item, ft)
  local list = {}
  local lines = vim.split(stderr, "\n", { trimempty = true })

  local i = 1
  local prev_item = {}
  while i <= #lines do
    local line = lines[i]
    local filename, lnum, col, type_str, msg = nil, nil, nil, "", ""

    if type(Qfrun.project_compile_langs) == "table" then
      for _, lang in ipairs(Qfrun.project_compile_langs) do
        local status, lang_parser = pcall(require, "qfrun.lang." .. lang)
        if not status then
          vim.notify_once(
            lang .. " language is not supported",
            vim.log.levels.WARN
          )
        else
          filename, lnum, col, type_str, msg = lang_parser.match(line)
          if filename ~= nil and lnum ~= nil and col ~= nil then
            break
          end
        end
      end
    else
      local status, lang_parser = pcall(require, "qfrun.lang." .. ft)
      if not status then
        vim.notify_once(
          ft .. " language is not supported",
          vim.log.levels.WARN
        )
      else
        filename, lnum, col, type_str, msg = lang_parser.match(line)
      end
    end

    filename = (
      filename
      and (not vim.startswith(filename, "/"))
      and Qfrun.src_dir
    )
        and vim.fs.joinpath(Qfrun.src_dir, filename)
      or filename
    local bufnr = vim.fn.bufadd(filename)

    if filename and lnum and col then
      prev_item = {
        filename = filename,
        lnum = tonumber(lnum),
        col = tonumber(col),
        type = type_str:sub(1, 1):upper(),
        text = msg,
        bufnr = bufnr,
      }
      table.insert(list, prev_item)
      if Qfrun.enable_diagnostic then
        table.insert(Qfrun.diagnostics, {
          lnum = 0,
          col = 0,
          message = "",
          severity = severity[prev_item.type],
        })
      end

      local j = i + 1

      while j <= #lines do
        local next_line = lines[j]

        if
          next_line:match("^%s*%d+%s*|")
          or next_line:match("^%s*|")
          or next_line:match("^%s*%^")
          or next_line:match("generated")
        then
          table.insert(list, {
            filename = prev_item.filename,
            bufnr = prev_item.bufnr,
            text = next_line,
          })
          j = j + 1
        else
          break
        end
      end

      i = j
    else
      if save_item then
        table.insert(list, {
          text = line,
          user_data = "compile_info",
        })
      end
      i = i + 1
    end
  end

  return list
end

local function apply_qf_syntax()
  vim.cmd([[
    syntax clear
    syntax match QfIndicator /\v\|*\s*\zs\~*\^\~*/
    syntax match QfDate / \d\+:\d\+:\d\+/
    syntax match QfError /^▸ \zsE:[^ ]*/ 
    syntax match QfWarn /^▸ \zsW:[^ ]*/
    syntax match QfNote /^▸ \zsN:[^ ]*/
    syntax match QfLineCol / \d\+:\d\+ /
    syntax match QfErrorMsg /use.*$/
    syntax match QfContext /^  .*/ contains=ALL
    syntax match QfFinish /\<finished\>/
    syntax match QfExit /\<exited abnormally\>/
    syntax match QfCode /\vcode\s+\zs\d+/
    syntax match QfCode /\vsignal\s+\zs\d+/

    highlight QfIndicator guifg=#887ec8
    highlight QfDate guifg=#84a800
    highlight QfLineCol guifg=#c7c938
    highlight QfErrorMsg guifg=#abb2bf
    highlight QfError guifg=#d75f5f gui=bold,underline
    highlight QfWarn guifg=#e0af68 gui=bold,underline
    highlight QfNote guifg=#268bd2
    highlight QfContext guifg=#abb2bf
    highlight QfFinish guifg=#62c92a
    highlight QfExit guifg=#992c3d gui=bold
    highlight QfCode guifg=#992c3d gui=bold
  ]])
end

local info_list = {
  start = {
    user_data = "compile_info",
  },
  fill = {
    user_data = "compile_info",
    text = " ",
  },
  cmd = {
    user_data = "compile_info",
  },
}

function Qfrun:update_qf(qf_list, over)
  vim.fn.setqflist({}, "a", {
    items = qf_list,
    title = over and "Compilation" or "Compiling",
    quickfixtextfunc = function(info)
      local lines = {}
      self.qf_id = info.id

      local res = vim.fn.getqflist({ id = info.id, items = 1, winid = 0 })
      local items = res.items

      for i = info.start_idx, info.end_idx do
        local item = items[i]

        if item.user_data == "compile_info" then
          table.insert(lines, item.text)
        elseif item.type ~= "" then
          table.insert(
            lines,
            string.format(
              "▸ %s:%s %d:%d %s",
              item.type,
              vim.fn.bufname(item.bufnr),
              item.lnum,
              item.col,
              item.text
            )
          )
        else
          table.insert(lines, "  " .. item.text)
        end
      end

      return lines
    end,
  })

  local qf_win = vim.fn.getqflist({ winid = 0 }).winid
  local curwin
  if qf_win == 0 then
    curwin = vim.api.nvim_get_current_win()
    vim.cmd.copen()
    qf_win = vim.api.nvim_get_current_win()
    self.qf_buf = vim.api.nvim_get_current_buf()

    vim.opt_local.number = false
    vim.opt_local.signcolumn = "no"
    vim.opt_local.list = false
    vim.opt_local.winfixbuf = true
    vim.opt_local.relativenumber = false
    vim.opt_local.cursorline = true
    vim.bo.textwidth = 0
  end

  if curwin and vim.api.nvim_win_is_valid(curwin) then
    vim.api.nvim_set_current_win(curwin)
  end
  if self.qf_buf and vim.api.nvim_buf_is_valid(self.qf_buf) then
    pcall(vim.api.nvim_buf_set_name, Qfrun.qf_buf, "Qfrun")
    if not vim.tbl_isempty(self.diagnostics) then
      vim.diagnostic.set(qf_ns, self.qf_buf, self.diagnostics)
    end
  end

  vim.schedule(function()
    pcall(vim.api.nvim_win_call, qf_win, function()
      local count = vim.api.nvim_buf_line_count(0)
      local height = vim.api.nvim_win_get_height(qf_win)
      if count > height then
        vim.api.nvim_win_set_cursor(qf_win, { count, 0 })
      end
      apply_qf_syntax()
    end)
  end)
end

function Qfrun:compile(compile_cmd)
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].ft
  local bufname = vim.api.nvim_buf_get_name(buf)
  local cwd = vim.uv.cwd()
  bufname = get_relative_path(cwd, bufname)
  self.job_status = true
  for k in pairs(self.diagnostics) do
    self.diagnostics[k] = nil
  end

  local function execute(cmd)
    cmd = (
      (cmd:gsub("${SRC}", bufname)):gsub(
        "${TARGET}",
        vim.fn.fnamemodify(bufname, ":r")
      )
    )
    self.last_cmd = cmd

    local start_time = vim.uv.hrtime()
    local stdout_buffer = ""
    local stderr_buffer = ""
    local save_item = {}

    info_list.cmd.text = self.last_cmd
    info_list.start.text = ("Compilation started at %s"):format(
      os.date("%a %b %H:%M:%S")
    )
    self.exec_id = self.exec_id + 1
    local id = self.exec_id
    vim.schedule(function()
      if (not self.job_status) or id ~= self.exec_id then
        return
      end
      local action = "a"
      local qf_win
      if self.qf_id then
        qf_win = vim.fn.getqflist({ id = self.qf_id, winid = true }).winid
        if vim.api.nvim_win_is_valid(qf_win) then
          action = "r"
        end
      end
      vim.fn.setqflist({}, action, {
        title = "Compiling",
        id = self.qf_id,
        items = { info_list.start, info_list.fill, info_list.cmd },
      })

      if action == "r" then
        vim.schedule(function()
          vim.api.nvim_win_call(qf_win, function()
            apply_qf_syntax()
          end)
        end)
      end
    end)
    self.job = vim.system({ "sh", "-c", cmd }, {
      text = true,
      detach = true,
      stdout = function(err, data)
        if err or not data or not self.job_status or id ~= self.exec_id then
          return
        end

        vim.schedule(function()
          if (not self.job_status) or id ~= self.exec_id then
            return
          end
          stdout_buffer = stdout_buffer .. (data:gsub("\r", ""))
          local lines = vim.split(stdout_buffer, "\n", { plain = true })
          if not data:match("\n$") then
            stdout_buffer = lines[#lines]
            table.remove(lines, #lines)
          else
            stdout_buffer = ""
          end

          local list = {}
          for _, line in ipairs(lines) do
            if line ~= "" then
              if self.parse_stdout_as_stderr then
                local err_list = parse_err(line, save_item, ft)
                vim.list_extend(list, err_list)
              else
                table.insert(list, {
                  text = line,
                  user_data = "compile_info",
                })
              end
            end
          end

          self:update_qf(list)
        end)
      end,

      stderr = function(err, data)
        if err or not data or not self.job_status or id ~= self.exec_id then
          return
        end

        vim.schedule(function()
          if (not self.job_status) or id ~= self.exec_id then
            return
          end
          stderr_buffer = stderr_buffer .. (data:gsub("\r", ""))
          local lines = vim.split(stderr_buffer, "\n", { plain = true })
          if not data:match("\n$") then
            stderr_buffer = lines[#lines]
            table.remove(lines, #lines)
          else
            stderr_buffer = ""
          end

          local list = {}
          local err_text = table.concat(lines, "\n")
          if err_text ~= "" then
            local err_list = parse_err(err_text, save_item, ft)
            vim.list_extend(list, err_list)

            self:update_qf(list)
          end
        end)
      end,
    }, function(out)
      local duration = (vim.uv.hrtime() - start_time) / 1e9
      local finish_reason = (out.code ~= 0)
          and "exited abnormally with code " .. out.code
        or (out.signal ~= 0) and "exited abnormally with signal " .. out.signal
        or "finished"
      vim.schedule(function()
        if (not self.job_status) or id ~= self.exec_id then
          return
        end
        local list = {}
        if stdout_buffer ~= "" then
          table.insert(list, {
            text = stdout_buffer,
            user_data = "compile_info",
          })
        end

        if stderr_buffer ~= "" then
          local err_list = parse_err(stderr_buffer, nil, ft)
          vim.list_extend(list, err_list)
        end

        table.insert(list, {
          user_data = "compile_info",
          text = " ",
        })
        table.insert(list, {
          user_data = "compile_info",
          text = ("Compilation %s at %s, duration %fs"):format(
            finish_reason,
            os.date("%a %b %H:%M:%S"),
            duration
          ),
        })

        self:update_qf(list, true)
      end)
    end)
  end

  local function env_with_compile(callback)
    local env_file = vim.fs.joinpath(cwd, self.project_config_name)
    return coroutine.wrap(function()
      local co = assert(coroutine.running())
      vim.uv.fs_open(env_file, "r", 438, function(err, fd)
        if err and vim.startswith(err, "ENOENT") then
          coroutine.resume(co, fd)
          return
        end
        assert(not err, err)
        coroutine.resume(co, fd)
      end)
      local fd = coroutine.yield()

      if fd == nil then
        vim.schedule(function()
          callback(compile_cmd, ft)
        end)
        return
      end

      vim.uv.fs_fstat(fd, function(err, stat)
        assert(not err)
        coroutine.resume(co, stat.size)
      end)
      local size = coroutine.yield()
      if size == 0 then
        vim.schedule(function()
          callback(compile_cmd, ft)
        end)
        return
      end

      vim.uv.fs_read(fd, size, 0, function(err, data)
        assert(not err)
        vim.uv.fs_close(fd)
        local lines = vim.split(data, "\n")
        local cmd = nil
        local key = ("QF_%s_COMPILE_COMMAND"):format(string.upper(ft))
        for _, line in ipairs(lines) do
          if line:find("^SRC_DIR") then
            self.src_dir = line:sub(#"SRC_DIR" + 2, #line)
          end
          if line:find("^PROJECT_COMPILE_LANGS") then
            self.project_compile_langs = vim.split(line:sub(23, #line), ",")
          end

          if line:find("^" .. key) then
            cmd = line:sub(#key + 2, #line)
            break
          end
        end
        coroutine.resume(co, cmd)
      end)
      local cmd = coroutine.yield()

      vim.schedule(function()
        callback(cmd, ft)
      end)
    end)()
  end

  env_with_compile(function(cmd, lang)
    if not cmd then
      local compile_cfg = self[lang]
      local compile_cfg_type = type(compile_cfg)
      if compile_cfg_type == "table" and #self[lang] > 1 then
        vim.ui.select(compile_cfg, { prompt = "compile:" }, function(choice)
          if choice then
            execute(choice)
          end
        end)
      elseif compile_cfg_type == "string" then
        execute(compile_cfg)
      elseif compile_cfg_type == "table" and #self[lang] == 1 then
        execute(compile_cfg[1])
      elseif compile_cfg_type == nil then
        return
      end
      return
    end
    execute(cmd)
  end)
end

function Qfrun:close_running()
  self.job_status = false
  if self.job and not self.job:is_closing() then
    vim.uv.kill(-self.job.pid, "sigterm")
    vim.notify("close running job " .. self.job.pid, vim.log.levels.WARN)
    self.job = nil
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "Qfrun",
  callback = function()
    apply_qf_syntax()
  end,
})

return Qfrun
