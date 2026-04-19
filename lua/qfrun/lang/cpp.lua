local M = {}
function M.match(line)
  local filename, lnum, col, type_str, msg =
    line:match("^([^:]+):(%d+):(%d+): (%w+):%s*(.*)$")
  if filename == nil then
    filename, lnum, msg = line:match("[^:]+: (.*):(%d+): (.*)")
    col, type_str = 1, "E"
  end

  if filename == nil then
    filename, lnum, col, msg = line:match("([^:]+):(%d+):(%d+):%s+(.*)")
    col, type_str = 1, "E"
  end

  return filename, lnum, col, type_str, msg
end
return M
