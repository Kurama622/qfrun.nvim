local M = {}
function M.match(line)
  return line:match("^([^:]+):(%d+):(%d+):%s*(%w+):%s*(.*)$")
end
return M
