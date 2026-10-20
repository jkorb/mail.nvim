-- Run with -c 'luafile tests/blink-input.lua' so Neovim processes real input.
vim.opt.runtimepath = {
  vim.fn.getcwd(), assert(vim.env.MAIL_NVIM_BLINK_COMPAT),
  assert(vim.env.MAIL_NVIM_BLINK), vim.env.VIMRUNTIME,
}
vim.opt.packpath = {}
vim.o.swapfile = false
vim.o.showmode = false
local other_calls = 0
package.preload["mail_test.other"] = function()
  return { new = function()
    return { get_completions = function(_, _, callback)
      other_calls = other_calls + 1
      callback({ items = { { label = "Other suggestion" } } })
    end }
  end }
end
local blink = require("blink.cmp")
blink.setup({
  fuzzy = { implementation = "lua" },
  sources = {
    default = { "other", "contacts" },
    providers = {
      other = { module = "mail_test.other" },
      contacts = { name = "cmp-contacts", module = "blink.compat.source", fallbacks = { "other" } },
    },
  },
})
require("mail").setup({
  treesitter = false,
  contacts_eval = { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l",
    "tests/contacts.lua", "valid", "{input}" },
})
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "To: ", "Subject: Hello", "", "" })
vim.bo.filetype = "mail"

local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function wait_for(predicate, message)
  local deadline = vim.uv.now() + 2000
  while not predicate() do
    assert(vim.uv.now() < deadline, message .. "\n" .. vim.inspect({
      line = vim.api.nvim_get_current_line(),
      context = blink.get_context(),
      trigger = require("blink.cmp.completion.trigger").context,
      items = blink.get_items(),
      other_calls = other_calls,
    }))
    coroutine.yield(10)
  end
end
local function only_contacts()
  if not blink.is_visible() then return false end
  if not vim.deep_equal(blink.get_context().providers, { "contacts" }) then return false end
  local items = blink.get_items()
  if #items == 0 then return false end
  for _, item in ipairs(items) do
    if item.source_id ~= "contacts" then return false end
  end
  return true
end
local function normal_completion()
  return blink.is_visible() and blink.get_items()[1].source_id == "other"
end
local thread = coroutine.create(function()
  -- Let the initial mail cursor placement run before moving into the body.
  coroutine.yield(20)
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  vim.api.nvim_input("iOther")
  wait_for(normal_completion, "ordinary body completion did not open")
  local before = other_calls
  vim.api.nvim_input(" @")
  wait_for(only_contacts, "@ did not switch an open menu to only contacts")
  check(other_calls == before, "@ queried an unrelated source")
  vim.api.nvim_input("Ali")
  wait_for(function() return only_contacts() and #blink.get_items() == 1 end, "typing filtered out Alice")
  coroutine.yield(150)
  check(only_contacts(), "body suggestion disappeared while waiting")
  check(blink.get_items()[1].label == '"Alice" <alice@example.org>', "wrong body contact")
  check(blink.accept({ index = 1 }), "Blink did not accept body contact")
  wait_for(function() return vim.api.nvim_get_current_line() == 'Other @"Alice" <alice@example.org>' end,
    "accepting did not keep @ and the full contact")
  vim.api.nvim_input(" Other")
  wait_for(normal_completion, "normal completion did not resume after accepting")
  check(other_calls > before, "other source did not resume after accepting")

  vim.api.nvim_input(" @Ali")
  wait_for(only_contacts, "second body lookup did not open")
  vim.api.nvim_input(" ")
  wait_for(function() return not blink.is_visible() end, "space did not end body lookup")
  vim.api.nvim_input("Other")
  wait_for(normal_completion, "normal completion did not resume after a space")
  vim.api.nvim_input(" @Ali")
  wait_for(only_contacts, "third body lookup did not open")
  vim.api.nvim_input("<C-w><BS>Other")
  wait_for(normal_completion, "normal completion did not resume after deleting @")
  check(not vim.api.nvim_get_current_line():find("@Other", 1, true), "test failed to delete the trigger")
  blink.show({ providers = { "other" } })
  wait_for(function() return vim.deep_equal(blink.get_context().providers, { "other" }) end,
    "manual source selection did not open")
  vim.api.nvim_input("s")
  wait_for(function() return vim.api.nvim_get_current_line():match("Others$") end, "input not processed")
  coroutine.yield(20)
  check(vim.deep_equal(require("blink.cmp.completion.trigger").context.providers, { "other" }),
    "ordinary body typing overrode a manual source selection")
  local before_phrase = other_calls
  vim.api.nvim_input(" !be")
  wait_for(function() return only_contacts() and blink.get_items()[1].label == "!best" end,
    "phrase trigger did not switch the menu to phrases")
  check(other_calls == before_phrase, "phrase lookup queried an unrelated source")
  coroutine.yield(150)
  check(blink.get_items()[1].label == "!best", "phrase suggestion disappeared while waiting")
  check(blink.accept({ index = 1 }), "Blink did not accept phrase")
  wait_for(function() return vim.api.nvim_get_current_line() == "Johannes" end, "multiline signoff was not inserted")
  local row = vim.api.nvim_win_get_cursor(0)[1]
  check(vim.api.nvim_buf_get_lines(0, row - 2, row - 1, false)[1]:match(" Best,$"), "phrase trigger was not replaced")
  vim.api.nvim_input(" Other")
  wait_for(normal_completion, "ordinary completion did not resume after phrase")
  vim.api.nvim_input(" !gro")
  wait_for(function() return only_contacts() and blink.get_items()[1].label == "!groetjes" end,
    "second phrase lookup did not open")
  vim.api.nvim_input("<C-w><BS>Other")
  wait_for(normal_completion, "deleting phrase trigger did not restore ordinary completion")
end)

local function step()
  local ok, delay = coroutine.resume(thread)
  if not ok then
    io.stderr:write(debug.traceback(thread, tostring(delay)) .. "\n")
    vim.cmd("cquit 1")
  elseif coroutine.status(thread) == "dead" then
    print(("%d Blink input checks passed"):format(checks))
    vim.cmd("qa!")
  else
    vim.defer_fn(step, delay)
  end
end
vim.schedule(step)
