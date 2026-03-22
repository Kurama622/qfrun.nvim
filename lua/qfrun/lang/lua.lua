local M = {}
-- E5112: Error while creating lua chunk: test.lua:4: ')' expected near 'msg'
function M.match(line)
  local type_str, filename, lnum, msg =
    line:match("^(.*):.*:%s*(.*):(%d+):%s*(.*)$")
  local col = 1
  return filename, lnum, col, type_str, msg
end
return M
