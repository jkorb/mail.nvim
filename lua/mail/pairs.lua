local M = {}
local mappings = {}

local function backtick()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local info = require("mail.body").scan(buf).rows[cursor[1]]
  local before = vim.api.nvim_get_current_line():sub(1, cursor[2])
  -- mini.pairs normally turns the third backtick into a new pair, producing
  -- four. Keep inline pairing, but type fence runs and fenced code literally.
  if info and not info.header and (info.code or before:match("^[ \t>]*``+$")) then return "`" end
  return vim.fn.eval(mappings[buf].rhs)
end

local function detach(buf)
  local saved = mappings[buf]
  if saved and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_call(buf, function()
      if vim.fn.maparg("`", "i", false, true).callback == backtick then
        vim.keymap.del("i", "`", { buffer = buf })
        if saved.buffer == 1 then vim.fn.mapset("i", false, saved) end
      end
    end)
  end
  mappings[buf] = nil
end

function M.attach(buf)
  vim.api.nvim_buf_call(buf, function()
    local mapping = vim.fn.maparg("`", "i", false, true)
    if mapping.callback == backtick then return end
    -- Only adapt mini.pairs' backtick mapping. Leave user mappings and other
    -- pairing plugins alone, and do not load mini.pairs on the user's behalf.
    if not mapping.expr or mapping.expr == 0 or not mapping.rhs
      or not mapping.rhs:find("v:lua.MiniPairs.closeopen", 1, true)
      or not mapping.rhs:find("``", 1, true) then return end
    mappings[buf] = mapping
    vim.keymap.set("i", "`", backtick, { buffer = buf, expr = true, replace_keycodes = false, desc = "Mail backticks" })
  end)
end

function M.setup()
  for buf in pairs(mappings) do detach(buf) end
  local group = vim.api.nvim_create_augroup("mail_pairs", { clear = true })
  vim.api.nvim_create_autocmd({ "FileType", "BufWipeout" }, {
    group = group,
    callback = function(event)
      if event.event == "BufWipeout" or vim.bo[event.buf].filetype ~= "mail" then detach(event.buf) end
    end,
  })
end

return M
