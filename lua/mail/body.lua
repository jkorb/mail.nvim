local M = {}
local cache = {}

-- A small fallback scanner also works when the optional parsers are absent.
-- Quote depth is the nesting written in the message, not a guessed timestamp.
function M.scan(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if cache[buf] and cache[buf].tick == tick then return cache[buf] end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fields, separator = require("mail.headers").parse(lines)
  local result = { tick = tick, lines = lines, fields = fields, separator = separator, rows = {} }
  local fence, signature
  for row, line in ipairs(lines) do
    local depth, text = 0, line
    if separator and row > separator then
      -- Inside a fence only its outer quote prefix belongs to the message;
      -- any further > characters are code, including on a would-be closer.
      while (not fence or depth < fence.depth) and text:match("^ ? ? ?>") do
        depth = depth + 1
        text = text:gsub("^ ? ? ?>[ \t]?", "", 1)
      end
      local code = text:match("^    ") ~= nil or text:match("^\t") ~= nil
      if fence and fence.depth > depth then fence = nil end
      if fence then
        code = true
        local closing = text:match("^ ? ? ?([`~]+)%s*$")
        if closing and closing:sub(1, 1) == fence.char and #closing >= fence.length
          and not closing:find("[^" .. fence.char .. "]") then fence = nil end
      else
        local opening, info = text:match("^ ? ? ?([`~]+)(.*)$")
        if opening and #opening >= 3 and not opening:find("[^" .. opening:sub(1, 1) .. "]")
          and (opening:sub(1, 1) ~= "`" or not info:find("`", 1, true)) then
          fence, code = { char = opening:sub(1, 1), length = #opening, depth = depth }, true
        end
      end
      if depth == 0 and line == "-- " and not code then signature = true end
      result.rows[row] = { depth = depth, code = code, signature = signature or false, text = text }
    else
      result.rows[row] = { depth = 0, code = false, header = true, text = line }
    end
  end
  cache[buf] = result
  return result
end

function M.forget(buf) cache[buf] = nil end

return M
