local M = {}
local headers = require("mail.headers")

function M.initial_position(lines)
  local fields, separator = headers.parse(lines)
  local to
  for _, field in ipairs(fields) do
    if field.name == "in-reply-to" and field.value:match("%S") and separator then
      return { math.min(separator + 1, #lines), 0 }
    end
    if field.name == "to" and not to then
      to = { field.row, field.col }
    end
  end
  return to
end

function M.jump(destination)
  if vim.bo.filetype ~= "mail" then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local fields, separator = headers.parse(lines)
  local target
  if destination == "body" and separator then
    target = { math.min(separator + 1, #lines), 0 }
  else
    for _, field in ipairs(fields) do
      if field.name == destination:lower() then
        target = { field.row, field.col }
        break
      end
    end
  end
  if not target then
    return false
  end
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0, target)
  return true
end

function M.attach(buf)
  for _, name in ipairs({ "To", "Cc", "Bcc", "Subject", "Body" }) do
    vim.api.nvim_buf_create_user_command(buf, "Mail" .. name, function()
      if not M.jump(name:lower()) then
        vim.notify("mail.nvim: no " .. name .. " field or section", vim.log.levels.INFO)
      end
    end, { desc = "Jump to the mail " .. name:lower() })
  end
end

return M
