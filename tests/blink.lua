-- Run in its own process so real nvim-cmp and blink.compat do not share modules.
vim.opt.runtimepath = {
  vim.fn.getcwd(), assert(vim.env.MAIL_NVIM_BLINK_COMPAT),
  assert(vim.env.MAIL_NVIM_BLINK), vim.env.VIMRUNTIME,
}
vim.opt.packpath = {}
vim.o.swapfile = false
vim.o.hidden = true
vim.o.virtualedit = "onemore"
local checks = 0
local function eq(actual, expected, message)
  checks = checks + 1
  assert(vim.deep_equal(actual, expected), message .. "\n" .. vim.inspect(actual))
end
local function provider(mode)
  return { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l",
    "tests/contacts.lua", mode or "valid", "{input}" }
end
local mail = require("mail")
mail.setup({ treesitter = false, contacts_eval = provider() })

local calls = {}
package.preload["mail_test.provider"] = function()
  return { new = function(opts)
    return { get_completions = function(_, _, callback)
      calls[opts.id] = (calls[opts.id] or 0) + 1
      callback({ items = { { label = "Other suggestion" } } })
    end }
  end }
end
local defaults = { "lsp", "path", "buffer", "snippets", "dictionary", "spell", "emoji", "latex", "copilot", "cmp-contacts" }
local providers = {}
for _, id in ipairs(defaults) do
  providers[id] = { module = "mail_test.provider", opts = { id = id } }
end
providers["cmp-contacts"] = {
  name = "cmp-contacts", module = "blink.compat.source", fallbacks = { "buffer" },
}
local blink = require("blink.cmp")
blink.setup({ fuzzy = { implementation = "lua" }, sources = { default = defaults, providers = providers } })
vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "blink.cmp" })
vim.wait(20, function() return false end)
local config = require("blink.cmp.config")
local sources = require("blink.cmp.sources.lib")
eq(type(config.sources.per_filetype.mail), "function", "late setup did not install mail selector")

local function buffer(lines, ft)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = ft or "mail"
  vim.wait(10, function() return false end)
end
local function select(row, col)
  vim.api.nvim_win_set_cursor(0, { row, col })
  return sources.get_enabled_provider_ids("default")
end
local context_id = 0
local function complete()
  context_id = context_id + 1
  local ctx = require("blink.cmp.completion.trigger.context").new({
    id = context_id, providers = sources.get_enabled_provider_ids("default"),
    initial_trigger_kind = "manual", trigger_kind = "manual",
  })
  local response
  require("blink.cmp.sources.lib.tree").new(ctx):get_completions(ctx, function(items) response = items end)
  eq(vim.wait(2000, function() return response ~= nil end, 5), true, "Blink completion timed out")
  return response
end
for _, name in ipairs({ "To", "From", "CC", "BCC", "Reply-To", "Resent-To" }) do
  buffer({ name .. ": Ali", "  Bob", "Subject: Hello", "", "To: body" })
  eq(select(1, #name + 5), { "cmp-contacts" }, name .. " includes other providers")
  eq(select(2, 5), { "cmp-contacts" }, "folded address includes other providers")
  eq(select(3, 14), defaults, "subject lost default sources")
  eq(select(5, 8), defaults, "body lost default sources")
  eq(select(1, 0), defaults, "header label changed sources")
end
buffer({ "To: ", "Subject: Hello", "", "Body" })
eq(select(1, 4), { "cmp-contacts" }, "empty address includes other sources")
local response = complete()
eq(#response["cmp-contacts"], 3, "Blink lost contacts")
eq(calls, {}, "unrelated providers were queried in address field")
select(4, 4)
response = complete()
eq(response["cmp-contacts"], nil, "contacts shown in body")
eq(calls.dictionary, 1, "dictionary did not resume in body")
calls = {}
for _, mode in ipairs({ "empty", "slow" }) do
  mail.setup({ treesitter = false, contacts_eval = provider(mode), contacts_timeout = 20 })
  select(1, 4)
  eq(complete(), {}, "empty/slow contacts should produce an empty menu")
  eq(calls, {}, "empty/slow contacts triggered fallback providers")
end
mail.setup({ treesitter = false, contacts_eval = provider(), contacts_only = false })
eq(select(1, 4), defaults, "opt-out did not restore sources")
local original = function() return { "dictionary", inherit_defaults = true } end
config.sources.per_filetype.mail = original
mail.setup({ treesitter = false, contacts_eval = provider() })
eq(select(1, 4), { "cmp-contacts" }, "mail override bypasses address selection")
eq(config.sources.per_filetype.mail(), { "cmp-contacts" }, "selector failed")
select(4, 4)
eq(config.sources.per_filetype.mail(), original(), "existing callback changed in body")
buffer({ "To: Ali" }, "text")
eq(select(1, 7), defaults, "non-mail buffer changed sources")
mail.setup({ treesitter = false, cmp_contacts = false })
eq(config.sources.per_filetype.mail, original, "disable did not restore callback")
config.sources.per_filetype.mail = { "spell" }
config.sources.providers.contacts = { name = "Address book", module = "blink.compat.source", opts = { cmp_name = "cmp-contacts" } }
config.sources.providers["cmp-contacts"] = nil
mail.setup({ treesitter = false, contacts_eval = provider() })
buffer({ "To: Ali", "Subject: Hello", "", "Body" })
eq(select(1, 7), { "contacts" }, "aliased provider not selected")
eq(#complete().contacts, 3, "aliased provider did not return contacts")
eq(select(4, 4), { "spell" }, "static mail sources changed in body")
mail.setup({ treesitter = false, cmp_contacts = false })
print(("%d Blink integration checks passed"):format(checks))
