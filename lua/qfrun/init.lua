local Qfrun = {
	["cpp"] = { compile = { "g++ -Wall ${source} -o ${output} && ./${output}" }, run = "." },
	["python"] = { compile = "python ${source}", run = "python" },

	last_cmd = nil,
	qf_id = nil,
	ansi_ns = nil,
	job = nil, ---@type vim.SystemObj?
}
function Qfrun.setup(opts)
	Qfrun = vim.api.tbl_extend("force", Qfrun, opts or {})
end

local function parse_err(stderr, save_item)
	local list = {}
	local lines = vim.split(stderr, "\n", { trimempty = true })

	local i = 1
	local prev_item = {}
	while i <= #lines do
		local line = lines[i]

		local filename, lnum, col, type_str, msg = line:match("^([^:]+):(%d+):(%d+):%s*(%w+):%s*(.*)$")
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
			save_item.lnum = prev_item.lnum
			save_item.col = prev_item.col
			save_item.bufnr = prev_item.bufnr

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
					filename = save_item.filename,
					bufnr = save_item.bufnr,
					lnum = save_item.lnum,
					col = save_item.col,
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
    syntax match QfIndicator /\v\|\s*\zs\^\~*/
    syntax match QfDate / \d\+:\d\+:\d\+/
    syntax match QfError /^▸ \zsE:[^ ]*/ 
    syntax match QfLineCol / \d\+:\d\+ /
    syntax match QfErrorMsg /use.*$/
    syntax match QfWarn /^▸ \zsW:[^ ]*/
    syntax match QfContext /^  .*/ contains=ALL
    syntax match QfFinish /\<finished\>/
    syntax match QfExit /\<exited abnormally\>/
    syntax match QfCode /\vcode\s+\zs\d+/

    highlight QfIndicator guifg=#887ec8 ctermfg=Magenta
    highlight QfDate guifg=NvimLightGreen ctermfg=Green
    highlight QfLineCol guifg=#c7c938 ctermfg=Yellow
    highlight QfErrorMsg guifg=#abb2bf ctermfg=White
    highlight QfError guifg=#d75f5f ctermfg=Red gui=bold,underline
    highlight QfWarn guifg=#e0af68 ctermfg=Yellow gui=bold,underline
    highlight QfContext guifg=#abb2bf ctermfg=White
    highlight QfFinish guifg=#62c92a ctermfg=Green
    highlight QfExit guifg=#992c3d ctermfg=Red gui=bold
    highlight QfCode guifg=#992c3d ctermfg=Red gui=bold
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
	local line_colors = {}
	local ansi_colors = {
		["30"] = "Black",
		["31"] = "Red",
		["32"] = "Green",
		["33"] = "Yellow",
		["34"] = "Blue",
		["35"] = "Magenta",
		["36"] = "Cyan",
		["37"] = "White",
	}

	vim.fn.setqflist({}, "a", {
		items = qf_list,
		title = over and "Compilation" or "Compiling",
		quickfixtextfunc = function(info)
			local lines = {}
			self.qf_id = info.id

			local res = vim.fn.getqflist({ id = info.id, items = 1, winid = 0 })
			local items = res.items

			local lpeg = vim.lpeg
			local P, R, C, Ct = lpeg.P, lpeg.R, lpeg.C, lpeg.Ct

			-- ESC [digits m
			local esc = P("\27")
			local digits = R("09") ^ 0
			local code = esc * "[" * C(digits) * "m" / function(d)
				return { type = "code", value = d }
			end

			local text = C((1 - esc) ^ 1) / function(t)
				return { type = "text", value = t }
			end

			local grammar = Ct((code + text) ^ 0)

			for i = info.start_idx, info.end_idx do
				local item = items[i]

				if item.user_data == "compile_info" then
					local segs = grammar:match(item.text)
					local plain = {}
					local active = nil

					for _, seg in ipairs(segs) do
						if seg.type == "code" then
							local c = seg.value
							if c ~= "" and c ~= "0" and ansi_colors[c] then
								if active then
									active._end = #table.concat(plain)
								end
								active = {
									lnum = i,
									start = #table.concat(plain),
									color = ansi_colors[c],
									code = tonumber(c),
								}
								table.insert(line_colors, active)
							else
								if active then
									active._end = #table.concat(plain)
									active = nil
								end
							end
						else
							table.insert(plain, seg.value)
						end
					end

					if active then
						active._end = #table.concat(plain)
					end
					table.insert(lines, table.concat(plain))
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

			local buf = vim.api.nvim_win_get_buf(res.winid)

			if #line_colors > 0 then
				vim.schedule(function()
					for _, c in ipairs(line_colors) do
						vim.api.nvim_set_hl(self.ansi_ns, "ANSI" .. c.color, { ctermfg = c.code, fg = c.color })
						vim.api.nvim_buf_set_extmark(buf, self.ansi_ns, c.lnum - 1, c.start, {
							end_col = c._end,
							hl_group = "ANSI" .. c.color,
						})
					end
				end)
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

		vim.api.nvim_win_set_hl_ns(qf_win, self.ansi_ns)
		vim.opt_local.number = false
		vim.opt_local.signcolumn = "no"
		vim.opt_local.list = false
		vim.opt_local.winfixbuf = true
		vim.opt_local.relativenumber = false
		vim.bo.textwidth = 0
	end

	if curwin and vim.api.nvim_win_is_valid(curwin) then
		vim.api.nvim_set_current_win(curwin)
	end

	vim.schedule(function()
		vim.api.nvim_win_call(qf_win, function()
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
	if not compile_cmd then
		local buf = vim.api.nvim_get_current_buf()
		local ft = vim.bo[buf].ft
		local compile_cfg = self[ft].compile
		local compile_cfg_type = type(compile_cfg)
		if compile_cfg_type == "table" and #self[ft].compile > 1 then
			vim.ui.select(compile_cfg, { promt = "compile" }, function(choice)
				if choice then
					compile_cmd = choice
				end
			end)
		elseif compile_cfg_type == "string" then
			compile_cmd = compile_cfg
		elseif compile_cfg_type == "table" and #self[ft].compile == 1 then
			compile_cmd = compile_cfg[1]
		elseif compile_cfg_type == nil then
			return
		end
	end
	compile_cmd = ((compile_cmd:gsub("${source}", vim.fn.expand("%"))):gsub("${output}", vim.fn.expand("%<")))
	self.last_cmd = compile_cmd

	local start_time = vim.uv.hrtime()
	local stdout_buffer = ""
	local stderr_buffer = ""
	local save_item = {}

	info_list.cmd.text = self.last_cmd
	info_list.start.text = ("Compilation started at %s"):format(os.date("%a %b %H:%M:%S"))
	vim.schedule(function()
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

	self.job = vim.system({ "sh", "-c", compile_cmd }, {
		text = true,
		stdout = function(err, data)
			if err or not data then
				return
			end

			vim.schedule(function()
				stdout_buffer = stdout_buffer .. data
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
						table.insert(list, {
							text = line,
							user_data = "compile_info",
						})
					end
				end

				self:update_qf(list)
			end)
		end,

		stderr = function(err, data)
			if err or not data then
				return
			end

			vim.schedule(function()
				stderr_buffer = stderr_buffer .. data
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
					local err_list = parse_err(err_text, save_item)
					vim.list_extend(list, err_list)

					self:update_qf(list)
				end
			end)
		end,
	}, function(out)
		local duration = (vim.uv.hrtime() - start_time) / 1e9
		vim.schedule(function()
			local list = {}
			if stdout_buffer ~= "" then
				table.insert(list, {
					text = stdout_buffer,
					user_data = "compile_info",
				})
			end

			if stderr_buffer ~= "" then
				local err_list = parse_err(stderr_buffer)
				vim.list_extend(list, err_list)
			end

			table.insert(list, {
				user_data = "compile_info",
				text = " ",
			})
			table.insert(list, {
				user_data = "compile_info",
				text = ("Compilation %s at %s, duration %fs"):format(
					out.code ~= 0 and "exited abnormally with code " .. out.code or "finished",
					os.date("%a %b %H:%M:%S"),
					duration
				),
			})

			self:update_qf(list, true)
		end)
	end)
end

function Qfrun:close_running()
	if self.job and not self.job:is_closing() then
		self.job:kill("sigterm")
		vim.notify("close running job " .. self.job.pid, vim.log.levels.WARN)
		self.job = nil
	end
end

vim.api.nvim_create_autocmd("FileType", {
	pattern = "qf",
	callback = function()
		apply_qf_syntax()
	end,
})

return Qfrun
