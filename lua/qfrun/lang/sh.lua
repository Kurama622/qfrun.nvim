local M = {}
-- test.sh: line 1: unexpected EOF while looking for matching `"'
function M.match(line)
  local filename, lnum, msg = line:match("^(.*):%s*line%s*(%d+):%s*(.*)$")
  local col, type_str = 1, "E"
  return filename, lnum, col, type_str, msg
end
return M
