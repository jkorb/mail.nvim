local M = {}

local defaults = {
  cmp_contacts = true,
  contacts_eval = nil,
  contacts_timeout = 3000,
  contacts_only = true,
  treesitter = true,
  parser = nil,
}
M.config = vim.deepcopy(defaults)
local registration, completion

function M.register_completion()
  if not M.config.cmp_contacts then
    return
  end
  if not registration then
    local ok, cmp = pcall(require, "cmp")
    if ok then
      completion = require("mail.cmp-contacts").new(M.config)
      registration = { cmp = cmp, id = cmp.register_source("cmp-contacts", completion) }
    end
  end
  if completion and M.config.contacts_only and M.config.contacts_eval then
    require("mail.blink").configure(completion)
  end
end

function M.setup(options)
  local config = vim.tbl_extend("force", vim.deepcopy(defaults), options or {})
  assert(type(config.contacts_timeout) == "number" and config.contacts_timeout > 0,
    "mail.nvim: contacts_timeout must be a positive number of milliseconds")
  assert(type(config.cmp_contacts) == "boolean", "mail.nvim: cmp_contacts must be a boolean")
  assert(type(config.contacts_only) == "boolean", "mail.nvim: contacts_only must be a boolean")
  assert(type(config.treesitter) == "boolean", "mail.nvim: treesitter must be a boolean")
  if config.parser then
    assert(type(config.parser) == "table" and (config.parser.path or config.parser.url),
      "mail.nvim: parser needs a path or URL")
  end
  M.config = config
  require("mail.blink").reset()
  if completion then
    completion:cancel()
    completion = nil
  end
  if registration then
    registration.cmp.unregister_source(registration.id)
    registration = nil
  end
  require("mail.treesitter").setup(M.config)
  M.register_completion()
  require("mail.autocmds").setup()
end

return M
