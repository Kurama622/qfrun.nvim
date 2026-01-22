local qfr = require("qfrun")
vim.api.nvim_create_user_command("QfCompile", function()
	if not qfr.ansi_ns then
		qfr.ansi_ns = vim.api.nvim_create_namespace("ansi_colors")
	end
	qfr:close_running()
	qfr:compile()
end, {})

vim.api.nvim_create_user_command("QfRecompile", function()
	qfr:close_running()
	if qfr.last_cmd then
		qfr:compile(qfr.last_cmd)
	end
end, {})
