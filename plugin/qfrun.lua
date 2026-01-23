local qfr = require("qfrun")
vim.api.nvim_create_user_command("QfCompile", function()
	qfr:close_running()
	qfr:compile()
end, {})

vim.api.nvim_create_user_command("QfClose", function()
	qfr:close_running()
end, {})

vim.api.nvim_create_user_command("QfRecompile", function()
	qfr:close_running()
	if qfr.last_cmd then
		qfr:compile(qfr.last_cmd)
	end
end, {})
