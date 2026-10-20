local M = {}

function M.context(config, buf, row, col)
  if not config.phrases or not next(config.phrases) or not vim.api.nvim_buf_is_valid(buf)
    or vim.bo[buf].filetype ~= "mail" then return end
  local body = require("mail.body").scan(buf)
  local info, line = body.rows[row], body.lines[row] or ""
  if not info or info.header or info.depth > 0 or info.code then return end
  local first, input = line:sub(1, col):match("()!([%w_%-]*)$")
  if not first or first > 1 and not line:sub(first - 1, first - 1):match("%s") then return end
  -- Do not complete an existing Markdown image or inside an inline code span.
  if line:sub(col + 1, col + 1) == "[" then return end
  local before, delimiter, pos = line:sub(1, first - 1), nil, 1
  while true do
    local a, b = before:find("`+", pos)
    if not a then break end
    local size = b - a + 1
    if delimiter == size then delimiter = nil elseif not delimiter then delimiter = size end
    pos = b + 1
  end
  if delimiter then return end
  local suffix = line:sub(col + 1):match("^[%w_%-]*")
  return input, {
    start = { line = row - 1, character = first - 1 },
    ["end"] = { line = row - 1, character = col + #suffix },
  }
end

function M.items(config, range)
  local items = {}
  for name, phrase in pairs(config.phrases) do
    items[#items + 1] = {
      label = "!" .. name, filterText = "!" .. name, sortText = name,
      detail = phrase:gsub("\n", " / "),
      documentation = { kind = "plaintext", value = phrase },
      insertTextFormat = 1,
      textEdit = { range = vim.deepcopy(range), newText = phrase },
      kind = vim.lsp.protocol.CompletionItemKind.Text,
    }
  end
  table.sort(items, function(a, b) return a.label < b.label end)
  return items
end

return M
