local M = {}
-- /home/arch/Github/qfrun.nvim/test.py:6: UserWarning: 这是一个警告示例！
-- File "/home/arch/Github/qfrun.nvim/test.py", line 11, in test
function M.match(line)
  local filename, lnum, type_str, msg =
    line:match("^(.*):(%d+):.*(Warning):%s*(.*)$")
  if filename == nil or lnum == nil then
    filename, lnum = line:match([[%s*File%s*"(.*)",%s*line%s*(%d+)]])
    type_str = "E"
  end
  local col = 1
  return filename, lnum, col, type_str, msg
end
return M
