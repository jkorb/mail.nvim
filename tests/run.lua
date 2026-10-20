vim.opt.runtimepath = { vim.fn.getcwd(), vim.env.VIMRUNTIME }
vim.opt.packpath = {}
vim.o.swapfile = false
vim.o.hidden = true
vim.o.virtualedit = "onemore"
local checks = 0
local function eq(actual, expected, message)
  checks = checks + 1
  assert(vim.deep_equal(actual, expected), (message or "mismatch") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual))
end
local function check(value, message) eq(not not value, true, message) end
local function drain() vim.wait(10, function() return false end, 1) end
local function buffer(lines, ft)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = ft or "mail"
  drain()
  return buf
end
local function cursor() return vim.api.nvim_win_get_cursor(0) end
local function params(buf, row, col)
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
  col = col or #line
  return { offset = 1, context = {
    bufnr = buf, cursor = { row = row, col = col + 1, line = row - 1 },
    cursor_line = line, cursor_before_line = line:sub(1, col), cursor_after_line = line:sub(col + 1),
  } }
end
local function provider(mode)
  return { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", "tests/contacts.lua", mode or "valid", "{input}" }
end
local function complete(src, request)
  local response, calls = nil, 0
  src:complete(request, function(result) response, calls = result, calls + 1 end)
  check(vim.wait(2000, function() return response ~= nil end, 5), "completion timed out")
  drain()
  eq(calls, 1, "callback fires once")
  return response
end
local mail = require("mail")
local nav = require("mail.navigation")
local source = require("mail.cmp-contacts")
mail.setup({ treesitter = false, cmp_contacts = false })

-- Initial placement and actual buffer/window events.
eq(nav.initial_position({ "To: ", "Subject: ", "", "Body" }), { 1, 4 }, "new message")
eq(nav.initial_position({ "tO: a", "in-REPLY-to:", " <id@example.org>", "", "Reply" }), { 5, 0 }, "folded reply header")
eq(nav.initial_position({ "To: x", "In-Reply-To: ", "", "Body" }), { 1, 4 }, "empty reply header")
eq(nav.initial_position({ "To: x", "In-Reply-To: <id>", "" }), { 3, 0 }, "empty body")
eq(nav.initial_position({ "Body", "To: not a header" }), nil, "body-only message")
eq(nav.initial_position({ "X_Custom: yes", "To: x", "", "Body" }), { 2, 4 }, "extension headers with punctuation")
eq(nav.initial_position({ "To: x", " \t", "In-Reply-To: <id>", "", "Body" }), { 5, 0 }, "whitespace fold is not a separator")
local first = buffer({ "From: a@example.org", "To: ", "Subject: hi", "", "Hello" })
eq(cursor(), { 2, 4 }, "FileType places cursor")
vim.api.nvim_win_set_cursor(0, { 5, 2 })
local other = buffer({ "Other buffer" }, "text")
vim.api.nvim_set_current_buf(first)
drain()
eq(cursor(), { 5, 2 }, "return preserves position")
mail.setup({ treesitter = false, cmp_contacts = false })
drain()
eq(cursor(), { 5, 2 }, "repeated setup preserves position")
vim.cmd("MailTo")
eq(cursor(), { 2, 4 }, "To command")
vim.cmd("MailSubject")
eq(cursor(), { 3, 9 }, "Subject command")
vim.cmd("MailBody")
eq(cursor(), { 5, 0 }, "Body command")
eq(nav.jump("bcc"), false, "missing field is a no-op")
vim.api.nvim_set_current_buf(other)
eq(nav.jump("body"), false, "navigation outside mail")
local deferred = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(deferred)
vim.api.nvim_buf_set_lines(deferred, 0, -1, false, { "To: ", "", "Body" })
vim.bo[deferred].filetype = "mail"
vim.api.nvim_win_set_cursor(0, { 3, 2 })
drain()
eq(cursor(), { 3, 2 }, "scheduled placement respects manual movement")

-- Address completion works without a parser or highlighter.
local src = source.new({ contacts_eval = provider() })
for _, name in ipairs({ "To", "Cc", "Bcc", "From", "Sender", "Reply-To", "Resent-To", "Resent-Cc", "Resent-Bcc", "Resent-From", "Resent-Sender", "tO" }) do
  local buf = buffer({ name .. ": ", "Subject: x", "", "To: body" })
  vim.api.nvim_win_set_cursor(0, { 1, #name + 2 })
  check(src:is_available(), name .. " empty field")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  eq(src:is_available(), false, "not in a header label")
  vim.api.nvim_win_set_cursor(0, { 2, 10 })
  eq(src:is_available(), false, "not in subject")
  vim.api.nvim_win_set_cursor(0, { 4, 6 })
  eq(src:is_available(), false, "not in body")
end
local folded = buffer({ "To: alice@example.org,", "  Bob", "Subject: x", "", "Body" })
vim.api.nvim_win_set_cursor(0, { 2, 5 })
check(src:is_available(), "folded field")
local response = complete(src, params(folded, 2))
eq(#response.items, 3, "duplicates and invalid contacts removed")
check(response.isIncomplete, "filtered providers requery as input changes")
eq(response.items[1].label, '"A \\"quoted\\" \\\\ name" <quoted@example.org>', "display name escaping")
eq(response.items[2].textEdit.range, { start = { line = 1, character = 2 }, ["end"] = { line = 1, character = 5 } }, "folded recipient edit")
eq(src:get_position_encoding_kind(), "utf-8", "byte offsets declared")
for _, case in ipairs({
  { "To: alice@example.org,Bob", "Bob", 22 },
  { 'To: "Doe, Jane" <jane@example.org>, Bob Smith', "Bob Smith", 36 },
  { "To: Friends: Bob", "Bob", 13 },
  { 'To: "Bo, B', 'Bo, B', 4 },
  { 'To: "Alice Smith" <ali', 'ali', 4 },
  { 'To: "Alice <Smith', 'Alice <Smith', 4 },
  { 'To: "A \\"quoted\\" name', 'A "quoted" name', 4 },
  { "To: alice+tag%test@example.org", "alice+tag%test@example.org", 4 },
  { "To: é@example.org, Éloïse", "Éloïse", 20 },
  { "To: ", "", 4 },
}) do
  local buf = buffer({ case[1], "", "" })
  local result = complete(source.new({ contacts_eval = provider("echo") }), params(buf, 1))
  local item = result.items[1]
  check(item, "provider returned input: " .. case[1])
  local expected = case[2] == "" and "echo@example.org" or '"' .. case[2]:gsub('[\\"]', '\\%0') .. '" <echo@example.org>'
  eq(item.label, expected, "provider receives current recipient")
  eq(item.textEdit.range.start.character, case[3], "replacement preserves preceding recipients")
end
local regexp = vim.regex("\\%(" .. src:get_keyword_pattern() .. "\\)$")
local start = regexp:match_str("To: a@example.org,Bob Smith")
eq(start, 18, "keyword excludes comma and includes full name")
local middle = buffer({ "To: Ali Smith <old@example.org>, bob@example.org", "", "" })
local edit = complete(src, params(middle, 1, 7)).items[2].textEdit
vim.api.nvim_buf_set_text(middle, edit.range.start.line, edit.range.start.character,
  edit.range["end"].line, edit.range["end"].character, { edit.newText })
eq(vim.api.nvim_buf_get_lines(middle, 0, 1, false)[1], 'To: "Alice" <alice@example.org>, bob@example.org', "completion replaces remaining recipient text")
local split_name = buffer({ "To: Alice", " Smith", "", "" })
eq(complete(src, params(split_name, 2)).items, {}, "multiline names cannot produce invalid edits")
local buf = buffer({ "To: Alice", "", "" })
for _, mode in ipairs({ "invalid", "empty", "object", "failure" }) do
  eq(complete(source.new({ contacts_eval = provider(mode) }), params(buf, 1)).items, {}, mode .. " output")
end
eq(complete(source.new({ contacts_eval = { "mail-nvim-missing-command" } }), params(buf, 1)).items, {}, "failed process start")
eq(complete(source.new({}), params(buf, 1)).items, {}, "no provider")
eq(complete(source.new({ contacts_eval = provider("slow"), contacts_timeout = 25 }), params(buf, 1)).items, {}, "timeout")
local slow = source.new({ contacts_eval = provider("slow") })
local stale
slow:complete(params(buf, 1), function(result) stale = result end)
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "To: Changed" })
check(vim.wait(2000, function() return stale ~= nil end, 5), "stale request finished")
eq(stale.items, {}, "changed buffer discards stale contacts")
local callbacks = {}
slow:complete(params(buf, 1), function(result) callbacks[1] = result end)
slow.config.contacts_eval = provider("valid")
slow:complete(params(buf, 1), function(result) callbacks[2] = result end)
check(vim.wait(2000, function() return callbacks[1] and callbacks[2] end, 5), "superseded request settles")
eq(callbacks[1].items, {}, "old request cancelled")
eq(#callbacks[2].items, 3, "new request completed")

-- Body lookups replace only a standalone @name, including text after the cursor.
check(vim.tbl_contains(src:get_trigger_characters(), "@"), "@ triggers contacts")
for _, case in ipairs({
  { "@", "", 0, nil, '@"Alice" <alice@example.org>' },
  { "Ask @Ali", "Ali", 4, nil, 'Ask @"Alice" <alice@example.org>' },
  { "Écrire à @Éloïse", "Éloïse", #"Écrire à ", nil, 'Écrire à @"Alice" <alice@example.org>' },
  { "Contact (@Alice)", "Alice", 9, #"Contact (@Alice", 'Contact (@"Alice" <alice@example.org>)' },
  { "Ask @Alice, please.", "Ali", 4, #"Ask @Ali", 'Ask @"Alice" <alice@example.org>, please.' },
  { "Ask @Alice or @Bob", "Bob", #"Ask @Alice or ", nil, 'Ask @Alice or @"Alice" <alice@example.org>' },
}) do
  local body = buffer({ "To: ", "Subject: Hi", "", case[1] })
  local col = case[4] or #case[1]
  vim.api.nvim_win_set_cursor(0, { 4, col })
  check(src:is_available(), "body trigger: " .. case[1])
  local keyword = vim.regex("\\%(" .. src:get_keyword_pattern() .. "\\)$")
  eq(keyword:match_str(case[1]:sub(1, col)), case[3], "body keyword starts at @")
  local items = complete(source.new({ contacts_eval = provider("echo") }), params(body, 4, col)).items
  local expected = case[2] == "" and "echo@example.org" or '"' .. case[2] .. '" <echo@example.org>'
  eq(items[1].label, expected, "body lookup omits @")
  eq(items[1].insertText, "@" .. expected, "body keeps @ and full contact")
  local body_edit = complete(src, params(body, 4, col)).items[2].textEdit
  vim.api.nvim_buf_set_text(body, body_edit.range.start.line, body_edit.range.start.character,
    body_edit.range["end"].line, body_edit.range["end"].character, { body_edit.newText })
  eq(vim.api.nvim_buf_get_lines(body, 3, 4, false)[1], case[5], "body edit preserves surrounding text")
end

for _, text in ipairs({ "Plain body", "alice@example.org", "https://example.org/@Ali",
  "@@Ali", "\\@Ali", "Ask @Ali ", "Ask @Ali,", "Ask @Ali.", "Ask @Ali/" }) do
  local body = buffer({ "To: ", "", text })
  vim.api.nvim_win_set_cursor(0, { 3, #text })
  eq(src:is_available(), false, "not a body lookup: " .. text)
  eq(complete(src, params(body, 3)).items, {}, "no lookup without a body trigger")
end
for _, case in ipairs({
  { { "To: ", "Subject: @Ali" }, 2, "mail" },
  { { "To: ", " @Ali" }, 2, "text" },
  { { "@Ali" }, 1, "mail" },
  { { "To: ", "", "@Ali" }, 3, "text" },
}) do
  local body = buffer(case[1], case[3])
  vim.api.nvim_win_set_cursor(0, { case[2], #case[1][case[2]] })
  eq(src:is_available(), false, "body completion requires a mail body")
  eq(complete(src, params(body, case[2])).items, {}, "invalid body context has no contacts")
end

-- Shell interpolation must preserve percent signs, quotes and metacharacters.
local shell_input = "50% O'Brien $(mail_nvim_should_not_run)"
buf = buffer({ "To: " .. shell_input, "", "" })
local command = table.concat(vim.tbl_map(vim.fn.shellescape, provider("echo")), " "):gsub("'{input}'", "{input}")
local result = complete(source.new({ contacts_eval = command }), params(buf, 1))
eq(result.items[1].label, '"' .. shell_input .. '" <echo@example.org>', "shell input remains literal")

-- Setup supports completion loading later, and never registers twice.
local count, registered = 0, {}
package.loaded.cmp = nil
package.preload.cmp = nil
mail.setup({ treesitter = false })
package.preload.cmp = function()
  return {
    register_source = function(name, instance)
      eq(name, "cmp-contacts")
      count = count + 1
      registered[count] = instance
      return count
    end,
    unregister_source = function(id) registered[id] = nil end,
  }
end
mail.register_completion()
mail.register_completion()
eq(count, 1, "late completion registered once")
mail.setup({ treesitter = false })
eq(count, 2, "setup replaces source")
eq(registered[1], nil, "old registration removed")
mail.setup({ treesitter = false, cmp_contacts = false })
eq(registered[2], nil, "disabling removes source")
package.loaded.cmp, package.preload.cmp = nil, nil

-- Blink loads independently of the compatibility source; keep its other settings.
do
  package.loaded.cmp = {
    register_source = function() return "cmp-contacts" end,
    unregister_source = function() end,
  }
  mail.setup({ treesitter = false, contacts_eval = provider() })
  local config = { sources = { per_filetype = {}, providers = {
    contacts = { name = "cmp-contacts", module = "blink.compat.source" },
  } } }
  package.loaded["blink.cmp.config"] = config
  vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "blink.cmp" })
  drain()
  check(type(config.sources.per_filetype.mail) == "function", "late Blink setup detected")
  local select = config.sources.per_filetype.mail
  buffer({ "To: Ali", "  Bob", "Subject: Hi", "", "To: body" })
  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  eq(select(), { "contacts" }, "address selects only aliased contact provider")
  vim.api.nvim_win_set_cursor(0, { 2, 5 })
  eq(select(), { "contacts" }, "folded address selects only contacts")
  vim.api.nvim_win_set_cursor(0, { 3, 10 })
  eq(select(), { inherit_defaults = true }, "subject inherits existing sources")
  vim.api.nvim_win_set_cursor(0, { 5, 8 })
  eq(select(), { inherit_defaults = true }, "body resembling header keeps sources")
  mail.register_completion()
  eq(config.sources.per_filetype.mail, select, "registration does not nest selectors")
  mail.setup({ treesitter = false, contacts_eval = provider(), contacts_only = false, phrases = {} })
  eq(config.sources.per_filetype.mail, nil, "opt-out restores absent mail config")
  local original = function() return { "spell", inherit_defaults = true } end
  config.sources.per_filetype.mail = original
  mail.setup({ treesitter = false, contacts_eval = provider() })
  eq(config.sources.per_filetype.mail(), original(), "existing mail callback preserved in body")
  mail.setup({ treesitter = false, cmp_contacts = false })
  eq(config.sources.per_filetype.mail, original, "disable restores original callback")
  mail.setup({ treesitter = false, phrases = {} })
  eq(config.sources.per_filetype.mail, original, "no command leaves sources alone")
  mail.setup({ treesitter = false, contacts_eval = provider() })
  local replacement = { "buffer" }
  config.sources.per_filetype.mail = replacement
  mail.setup({ treesitter = false, cmp_contacts = false })
  eq(config.sources.per_filetype.mail, replacement, "disable preserves later user configuration")
  package.loaded.cmp, package.loaded["blink.cmp.config"] = nil, nil
end

local parser_path = vim.env.MAIL_NVIM_PARSER
if parser_path and parser_path ~= "" then
  check(vim.treesitter.language.add("mail", { path = parser_path }), "custom parser loads")
  mail.setup({ cmp_contacts = false })
  buf = buffer({ "To: alice@example.org", "Cc: bob@example.org", "Subject: Hello", "", "Body with **bold**", "> quote", "> > nested", "-- ", "Signature" })
  local parser = vim.treesitter.get_parser(buf, "mail")
  check(not parser:parse()[1]:root():has_error(), "mail parses")
  check(vim.treesitter.highlighter.active[buf], "highlighter started")
  local highlighter = vim.treesitter.highlighter.active[buf]
  vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf })
  eq(vim.treesitter.highlighter.active[buf], highlighter, "reopening reuses highlighter")
  for _, name in ipairs({ "highlights", "injections", "utils" }) do
    check(vim.treesitter.query.get("mail", name), name .. " query compiles")
  end
  local captures = {}
  local query = vim.treesitter.query.get("mail", "highlights")
  for id, node, metadata in query:iter_captures(parser:parse()[1]:root(), buf) do
    local name = query.captures[id]
    captures[name] = (captures[name] or 0) + 1
    if node:type() == "quote_symbol" then
      eq((metadata[id] or metadata).conceal, nil, "view owns quote conceal independently of the highlighter")
    end
  end
  check(captures.address_field, "address capture")
  check(captures["markup.heading"], "subject capture")
  check(captures["markup.heading.2"], "nested quote capture")
  check(require("mail.utils").goto_treesitter_node("(to) @jump"), "Tree-sitter jump succeeds on first line")
  eq(cursor(), { 1, 0 }, "Tree-sitter uses start and correct row numbering")
  eq(require("mail.utils").goto_treesitter_node("(missing_node) @jump"), false, "invalid query is safe")
  local configs = {}
  package.loaded["nvim-treesitter.parsers"] = configs
  mail.setup({ cmp_contacts = false, parser = { path = "/local/grammar" } })
  eq(configs.mail.install_info.path, "/local/grammar", "current parser registration")
  configs.mail = nil
  vim.api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
  eq(configs.mail.install_info.path, "/local/grammar", "parser re-registered on TSUpdate")
  local legacy = {}
  package.loaded["nvim-treesitter.parsers"] = { get_parser_configs = function() return legacy end }
  mail.setup({ cmp_contacts = false, parser = { path = "/local/grammar" } })
  eq(legacy.mail.install_info.url, "/local/grammar", "legacy parser registration")
  eq(legacy.mail.install_info.files, { "src/parser.c", "src/scanner.c" }, "external scanner included")
  mail.setup({ cmp_contacts = false, treesitter = false })
  eq(vim.treesitter.highlighter.active[buf], nil, "highlighting can be disabled")
else
  print("Parser checks skipped; set MAIL_NVIM_PARSER to a compiled mail parser.")
end
print(("%d checks passed"):format(checks))
