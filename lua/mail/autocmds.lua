local M = {}
local navigation = require("mail.navigation")

M.initial_position = navigation.initial_position

function M.setup()
  local group = vim.api.nvim_create_augroup("mail_nvim", { clear = true })
  local pending = {}

  local function attach(buf)
    if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "mail" then
      return
    end
    navigation.attach(buf)
    require("mail").register_completion()
    require("mail.treesitter").start(buf)
    if pending[buf] or vim.b[buf].mail_initial_cursor then
      return
    end
    local win = vim.fn.bufwinid(buf)
    if win == -1 then
      return
    end
    local cursor = vim.api.nvim_win_get_cursor(win)
    pending[buf] = true
    vim.schedule(function()
      pending[buf] = nil
      if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "mail"
        or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf
        or vim.b[buf].mail_initial_cursor then
        return
      end
      -- Do not undo a movement made while the callback was waiting.
      if vim.deep_equal(cursor, vim.api.nvim_win_get_cursor(win)) then
        local target = M.initial_position(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        if target then
          vim.api.nvim_win_set_cursor(win, target)
        end
      end
      vim.b[buf].mail_initial_cursor = true
    end)
  end

  vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = group,
    callback = function(event) attach(event.buf) end,
  })
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function(event)
      if vim.bo[event.buf].filetype == "mail" then
        require("mail").register_completion()
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LazyLoad",
    callback = function(event)
      if event.data == "blink.cmp" or event.data == "blink.compat" or event.data == "nvim-cmp" then
        vim.schedule(function() require("mail").register_completion() end)
      end
    end,
  })
  -- Lazy loading can happen after FileType, including during startup.
  if vim.v.vim_did_enter == 0 then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      once = true,
      callback = function() attach(vim.api.nvim_get_current_buf()) end,
    })
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      attach(buf)
    end
  end
end

return M
