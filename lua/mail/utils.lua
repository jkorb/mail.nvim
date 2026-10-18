local M = {}

function M.goto_treesitter_node(query_str)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "mail" then
    return false
  end
  local ok, target = pcall(function()
    local parser = vim.treesitter.get_parser(buf, "mail")
    if not parser then
      return nil
    end
    local tree = parser:parse()[1]
    local query = vim.treesitter.query.parse("mail", query_str)
    for _, node in query:iter_captures(tree:root(), buf) do
      local row, col = node:start()
      return { row + 1, col }
    end
  end)
  if ok and target then
    vim.api.nvim_win_set_cursor(0, target)
    return true
  end
  return false
end

function M.in_treesitter_capture(capture)
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local col = cursor[2]
  if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
    col = math.max(0, col - 1)
  end
  local ok, captures = pcall(vim.treesitter.get_captures_at_pos, buf, cursor[1] - 1, col)
  if not ok then
    return false
  end
  local names = type(capture) == "table" and capture or { capture }
  for _, item in ipairs(captures) do
    if vim.tbl_contains(names, item.capture) then
      return true
    end
  end
  return false
end

return M
