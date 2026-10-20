local M = {}
local expression = "v:lua.require'mail.folds'.level(v:lnum)"
local options = {
  foldmethod = "expr", foldexpr = expression,
  foldtext = "v:lua.require'mail.folds'.text()",
  foldlevel = 1, foldenable = true, foldminlines = 0,
}
local windows, history = {}, {}

function M.level(row)
  local info = require("mail.body").scan(vim.api.nvim_get_current_buf()).rows[row]
  return info and math.min(info.depth, 20) or 0
end

function M.text()
  local count = vim.v.foldend - vim.v.foldstart + 1
  local line = vim.fn.getline(vim.v.foldstart):gsub("^[%s>]+", "")
  return ("┃ %d quoted %s · %s"):format(count, count == 1 and "line" or "lines", line)
end

local function restore(win)
  local state = windows[win]
  if state and vim.api.nvim_win_is_valid(win) and vim.wo[win].foldexpr == expression then
    for name, value in pairs(state.original) do vim.wo[win][name] = value end
  end
  windows[win] = nil
end

function M.sync()
  local enabled = require("mail").config.fold_quotes
  for win, state in pairs(windows) do
    if not vim.api.nvim_win_is_valid(win) or not enabled
      or vim.api.nvim_win_get_buf(win) ~= state.buf or vim.bo[state.buf].filetype ~= "mail" then
      restore(win)
    end
  end
  if not enabled then return end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "mail" and not windows[win] then
      local original = history[buf] and history[buf][win]
      local inherited = vim.wo[win].foldexpr == expression
      if not original and inherited then
        -- A split inherits the source window's fold settings and open folds.
        for _, other in pairs(windows) do
          if other.buf == buf then original = other.original; break end
        end
      end
      if not original then
        original = {}
        for name in pairs(options) do original[name] = vim.wo[win][name] end
      end
      original = vim.deepcopy(original)
      windows[win] = { buf = buf, original = original }
      history[buf] = history[buf] or {}
      history[buf][win] = original
      for name, value in pairs(options) do
        if not inherited or name ~= "foldlevel" and name ~= "foldenable" then vim.wo[win][name] = value end
      end
    end
  end
end

function M.setup()
  for win in pairs(windows) do restore(win) end
  history = {}
  local group = vim.api.nvim_create_augroup("mail_folds", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "FileType", "WinClosed" }, {
    group = group, callback = function() M.sync() end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(event)
      history[event.buf] = nil
      require("mail.body").forget(event.buf)
      for win, state in pairs(windows) do if state.buf == event.buf then restore(win) end end
    end,
  })
end

return M
