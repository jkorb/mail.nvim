-- Optional integration tests against installed dependencies; see :h mail-tests.
vim.opt.runtimepath = { vim.fn.getcwd(), vim.env.VIMRUNTIME }
vim.opt.packpath = {}
vim.o.swapfile = false
vim.o.virtualedit = "onemore"
vim.o.hidden = true
local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function setup_buffer(line)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line, "Subject: Hello", "", "Body **bold**", "> quote" })
  vim.bo[buf].filetype = "mail"
  vim.wait(10, function() return false end)
  vim.api.nvim_win_set_cursor(0, { 1, #line })
  return buf
end
local function provider()
  return { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", "tests/contacts.lua", "valid", "{input}" }
end
local treesitter_path = vim.env.MAIL_NVIM_TREESITTER
if vim.env.MAIL_NVIM_MARKDOWN_PARSERS then
  for _, lang in ipairs({ "markdown", "markdown_inline" }) do
    check(vim.treesitter.language.add(lang, {
      path = vim.env.MAIL_NVIM_MARKDOWN_PARSERS .. "/" .. lang .. ".so",
    }), lang .. " parser missing")
  end
end
if treesitter_path then
  vim.opt.runtimepath:append(treesitter_path)
  local install_dir = vim.fn.getcwd() .. "/tmp/installed"
  require("nvim-treesitter").setup({ install_dir = install_dir })
  require("mail").setup({ cmp_contacts = false, parser = { path = assert(vim.env.MAIL_NVIM_GRAMMAR) } })
  require("nvim-treesitter").install({ "mail" }):wait(60000)
  check(vim.fn.filereadable(install_dir .. "/parser/mail.so") == 1, "nvim-treesitter did not install the grammar")
  -- Refresh runtime discovery when the install directory was just created.
  vim.opt.runtimepath:prepend(install_dir)
  local buf = setup_buffer("To: alice@example.org")
  check(vim.treesitter.highlighter.active[buf], "installed parser did not start")
  check(not vim.treesitter.get_parser(buf, "mail"):parse()[1]:root():has_error(), "installed parser cannot parse mail")
  local captures = vim.treesitter.get_captures_at_pos(buf, 0, 5)
  check(vim.tbl_contains(vim.tbl_map(function(c) return c.capture end, captures), "address_field"), "plugin address query not used")
  if vim.env.MAIL_NVIM_MARKDOWN_PARSERS then
    local parser = vim.treesitter.get_parser(buf, "mail")
    parser:parse(true)
    local markdown = parser:children().markdown
    check(markdown, "body did not inject Markdown")
    check(markdown:children().markdown_inline, "Markdown inline parser missing")
    local bold = vim.treesitter.get_captures_at_pos(buf, 3, 7)
    check(vim.tbl_contains(vim.tbl_map(function(c) return c.capture end, bold), "markup.strong"), "bold body text not highlighted")
  end
end
local cmp_path = vim.env.MAIL_NVIM_CMP
if cmp_path then
  vim.opt.runtimepath:append(cmp_path)
  local cmp = require("cmp")
  cmp.setup({ sources = { { name = "cmp-contacts" } } })
  require("mail").setup({ treesitter = false, contacts_eval = provider() })
  local instance
  for _, item in pairs(cmp.core.sources) do
    if item.name == "cmp-contacts" then instance = item end
  end
  check(instance, "source not registered with nvim-cmp")
  for _, line in ipairs({
    "To: Ali", "To: a@example.org,Ali", "To: é@example.org, Ali", 'To: "Ali',
    'To: Old Name <ali', 'To: alice@', "@", "Ask @Ali", "Écrire à @alice",
  }) do
    local body = not line:match("^To:")
    local buf = setup_buffer(body and "To: " or line)
    if body then
      vim.api.nvim_buf_set_lines(buf, 3, 4, false, { line })
      vim.api.nvim_win_set_cursor(0, { 4, #line })
    end
    local ctx = require("cmp.context").new({}, { reason = require("cmp.types").cmp.ContextReason.Manual })
    local done = false
    instance:complete(ctx, function() done = true end)
    check(vim.wait(2000, function() return done end, 5), "nvim-cmp completion timed out")
    local entries = require("cmp.utils.async").wrap(function() return instance:get_entries(ctx) end)():sync()
    check(#entries > 0, "nvim-cmp filtered all entries for " .. line)
    local alice
    for _, entry in ipairs(entries) do
      if entry.completion_item.label == '"Alice" <alice@example.org>' then alice = entry end
    end
    check(alice, "Alice missing for " .. line)
    check(not alice:is_invalid(), "nvim-cmp rejects edit range")
    local edit = alice.completion_item.textEdit
    vim.api.nvim_buf_set_text(0, edit.range.start.line, edit.range.start.character,
      edit.range["end"].line, edit.range["end"].character, { edit.newText })
    if body then
      check(vim.api.nvim_get_current_line() == line:gsub("@.*$", '@"Alice" <alice@example.org>'), "body completion edit not applied")
    else
      check(vim.api.nvim_get_current_line():match('"Alice" <alice@example.org>$'), "completion edit not applied")
    end
  end
  for key, phrase in pairs({ best = "Best,\nJohannes", groetjes = "Groetjes,\nJohannes", sounds = "Sounds good to me." }) do
    local buf = setup_buffer("To: ")
    local line = "Écrire !" .. key:sub(1, 2)
    vim.api.nvim_buf_set_lines(buf, 3, 4, false, { line })
    vim.api.nvim_win_set_cursor(0, { 4, #line })
    local ctx = require("cmp.context").new({}, { reason = require("cmp.types").cmp.ContextReason.Manual })
    local done = false
    instance:complete(ctx, function() done = true end)
    check(vim.wait(2000, function() return done end, 5), "nvim-cmp phrase completion timed out")
    local entries = require("cmp.utils.async").wrap(function() return instance:get_entries(ctx) end)():sync()
    local found
    for _, entry in ipairs(entries) do if entry.completion_item.label == "!" .. key then found = entry end end
    check(found and not found:is_invalid(), "nvim-cmp filtered or rejected phrase " .. key)
    local edit = found.completion_item.textEdit
    vim.api.nvim_buf_set_text(buf, edit.range.start.line, edit.range.start.character,
      edit.range["end"].line, edit.range["end"].character, vim.split(edit.newText, "\n", { plain = true }))
    check(table.concat(vim.api.nvim_buf_get_lines(buf, 3, 3 + #vim.split(phrase, "\n"), false), "\n") == "Écrire " .. phrase,
      "nvim-cmp phrase damaged multiline text")
  end
end
local compat_path = vim.env.MAIL_NVIM_BLINK_COMPAT
if compat_path then
  vim.opt.runtimepath:append(compat_path)
  local mail = require("mail")
  mail.setup({ treesitter = false, cmp_contacts = false })
  -- Registration exercises the real Blink adapter independently of nvim-cmp.
  local src = require("mail.cmp-contacts").new({ contacts_eval = provider() })
  require("blink.compat.registry").register_source("cmp-contacts", src)
  local adapter = require("blink.compat.source").new({}, { name = "cmp-contacts" })
  local line = "To: é@example.org, Ali"
  local buf = setup_buffer(line)
  check(adapter:enabled(), "Blink adapter disabled in address header")
  local result
  adapter:get_completions({ id = 1, bufnr = buf, cursor = { 1, #line }, line = line,
    trigger = { kind = "manual" } }, function(value) result = value end)
  check(vim.wait(2000, function() return result ~= nil end, 5), "Blink completion timed out")
  check(#result.items == 3, "Blink adapter lost contacts")
  local edit = result.items[2].textEdit
  check(edit.range.start.character == #"To: é@example.org, ", "Blink changed byte offsets")
  vim.api.nvim_buf_set_text(buf, edit.range.start.line, edit.range.start.character,
    edit.range["end"].line, edit.range["end"].character, { edit.newText })
  check(vim.api.nvim_get_current_line() == 'To: é@example.org, "Alice" <alice@example.org>', "Blink edit damaged another recipient")
end
if vim.env.MAIL_NVIM_BLINK then
  local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", "tests/blink.lua" },
    { text = true }):wait(15000)
  check(result.code == 0, "Blink integration failed: " .. (result.stderr or "") .. (result.stdout or ""))
  io.write(result.stdout or "")
  io.write(result.stderr or "")
  result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-c", "luafile tests/blink-input.lua" },
    { text = true }):wait(15000)
  check(result.code == 0, "Blink input integration failed: " .. (result.stderr or "") .. (result.stdout or ""))
  io.write(result.stdout or "")
  io.write(result.stderr or "")
end
print(("%d dependency integration checks passed"):format(checks))
