local M = {}
local config = {}

function M.register()
  if not config.treesitter or not config.parser then
    return false
  end
  local ok, parsers = pcall(require, "nvim-treesitter.parsers")
  if not ok then
    return false
  end
  local install = vim.deepcopy(config.parser)
  if install.path then
    install.path = vim.fn.expand(install.path)
  end
  if type(parsers.get_parser_configs) == "function" then
    -- nvim-treesitter's legacy master branch.
    install.url = install.path or install.url
    install.path = nil
    install.files = { "src/parser.c", "src/scanner.c" }
    parsers.get_parser_configs().mail = { install_info = install, filetype = "mail" }
  else
    parsers.mail = { install_info = install }
  end
  return true
end

function M.setup(options)
  config = options
  local group = vim.api.nvim_create_augroup("mail_treesitter", { clear = true })
  vim.treesitter.language.register("mail", "mail")
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "TSUpdate",
    callback = function() M.register() end,
  })
  M.register()
end

function M.start(buf)
  if not config.treesitter then
    if vim.b[buf].mail_treesitter then
      vim.treesitter.stop(buf)
      vim.b[buf].mail_treesitter = nil
    end
    return false
  end
  if vim.treesitter.highlighter.active[buf] then
    return true
  end
  local ok, err = pcall(vim.treesitter.start, buf, "mail")
  if ok then
    vim.b[buf].mail_treesitter = true
  else
    vim.notify_once("mail.nvim: " .. tostring(err)
      .. "\nRun :checkhealth mail. Use :TSInstall mail for a missing parser,"
      .. " or :TSInstall! mail to rebuild an outdated one, then restart Neovim.", vim.log.levels.WARN)
  end
  return ok
end

return M
