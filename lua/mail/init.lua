local M = {}

local defaults = {
  cmp_contacts = true,
  contacts_eval = nil,
  contacts_timeout = 3000,
  contacts_only = true,
  phrases = {
    best = "Best,\nJohannes",
    groetjes = "Groetjes,\nJohannes",
    sounds = "Sounds good to me.",
    thanks = "Thanks for your help.",
    followup = "Just following up on my previous email.",
    attached = "Please find the document attached.",
  },
  fold_quotes = true,
  draft_check = true,
  image_picker = "nnn",
  image_keymap = "<localleader>mi",
  view = { enabled = true, quote_char = "┃", keymap = "<localleader>mv" },
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
  if completion and (next(M.config.phrases) or M.config.contacts_only and M.config.contacts_eval) then
    require("mail.blink").configure(completion)
  end
end

function M.setup(options)
  local config = vim.tbl_extend("force", vim.deepcopy(defaults), options or {})
  assert(type(config.phrases) == "table", "mail.nvim: phrases must map shortcut names to text")
  for name, phrase in pairs(config.phrases) do
    assert(type(name) == "string" and name:match("^[%w_%-]+$") and type(phrase) == "string" and phrase ~= ""
      and not phrase:find("[%z\1-\8\11-\31\127]"), "mail.nvim: each phrase needs a shortcut name and plain text")
  end
  assert(type(config.fold_quotes) == "boolean", "mail.nvim: fold_quotes must be a boolean")
  assert(type(config.draft_check) == "boolean", "mail.nvim: draft_check must be a boolean")
  if type(config.view) == "boolean" then config.view = { enabled = config.view } end
  assert(type(config.view) == "table", "mail.nvim: view must be a boolean or table")
  config.view = vim.tbl_extend("force", defaults.view, config.view)
  assert(type(config.view.enabled) == "boolean", "mail.nvim: view.enabled must be a boolean")
  assert(type(config.view.quote_char) == "string" and vim.fn.strchars(config.view.quote_char) == 1
    and vim.fn.strdisplaywidth(config.view.quote_char) == 1 and not config.view.quote_char:find("%c"),
    "mail.nvim: view.quote_char must be one display cell")
  assert(config.view.keymap == false or type(config.view.keymap) == "string" and config.view.keymap ~= "",
    "mail.nvim: view.keymap must be a key sequence or false")
  assert(type(config.contacts_timeout) == "number" and config.contacts_timeout > 0,
    "mail.nvim: contacts_timeout must be a positive number of milliseconds")
  assert(type(config.cmp_contacts) == "boolean", "mail.nvim: cmp_contacts must be a boolean")
  assert(type(config.contacts_only) == "boolean", "mail.nvim: contacts_only must be a boolean")
  assert(type(config.image_picker) == "string" and config.image_picker ~= "",
    "mail.nvim: image_picker must be an executable name or path")
  assert(config.image_keymap == false or type(config.image_keymap) == "string" and config.image_keymap ~= "",
    "mail.nvim: image_keymap must be a key sequence or false")
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
  require("mail.view").setup()
  require("mail.folds").setup()
  require("mail.check").setup()
  require("mail.pairs").setup()
  M.register_completion()
  require("mail.autocmds").setup()
end

return M
