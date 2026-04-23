local qfr = require("qfrun")
vim.api.nvim_create_user_command("QfCompile", function()
  qfr:close_running()
  qfr:compile()
end, {})

vim.api.nvim_create_user_command("QfClose", function()
  qfr:close_running()
  qfr.last_cmd = nil
  qfr.src_dir = nil
  qfr.last_on_done = nil
  qfr.qf_buf = -1
  qfr.project_compile_langs = nil
  vim.cmd.cclose()
end, {})

vim.api.nvim_create_user_command("QfRecompile", function()
  qfr:close_running()
  if qfr.last_cmd then
    qfr:compile(qfr.last_cmd, qfr.last_on_done)
  end
end, {})

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("QfInput", { clear = true }),
  pattern = "qf",
  callback = function()
    if vim.api.nvim_buf_is_valid(qfr.qf_buf) then
      vim.api.nvim_buf_set_keymap(qfr.qf_buf, "n", "i", "", {
        callback = function()
          qfr:qf_interactive()
        end,
      })
    end
  end,
})
