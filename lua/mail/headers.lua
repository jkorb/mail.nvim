local M = {}

local address_fields = {
  to = true, cc = true, bcc = true, from = true, sender = true,
  ["reply-to"] = true, ["resent-to"] = true, ["resent-cc"] = true,
  ["resent-bcc"] = true, ["resent-from"] = true, ["resent-sender"] = true,
}

-- Rows are one-based; columns are zero-based byte offsets, like window cursors.
function M.parse(lines)
  local fields, current = {}, nil
  for row, line in ipairs(lines) do
    if line == "" or line == "\r" then
      return fields, row
    end
    local name, prefix, value = line:match("^([^%s:]+)(:[ \t]*)(.*)$")
    if name then
      current = { name = name:lower(), row = row, col = #name + #prefix, value = value, last_row = row }
      fields[#fields + 1] = current
    elseif current and line:match("^[ \t]") then
      current.value = current.value .. " " .. line:gsub("^[ \t]+", "")
      current.last_row = row
    else
      break
    end
  end
  return fields
end

function M.address_field(buf, row, col)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "mail" then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, row, false)
  for _, field in ipairs(M.parse(lines)) do
    if address_fields[field.name] and row >= field.row and row <= field.last_row then
      local start = row == field.row and (#field.name + 1) or 0
      if col >= start then
        return field
      end
    end
  end
end

return M
