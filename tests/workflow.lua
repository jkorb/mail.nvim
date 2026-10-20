vim.opt.runtimepath = { vim.fn.getcwd(), vim.env.VIMRUNTIME }
vim.opt.packpath = {}
vim.o.swapfile, vim.o.hidden, vim.o.virtualedit = false, true, "onemore"
local checks = 0
local function eq(actual, expected, message)
  checks = checks + 1
  assert(vim.deep_equal(actual, expected), message .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual))
end
local function drain() vim.wait(15, function() return false end, 1) end
local mail, check = require("mail"), require("mail.check")
local function buffer(lines, ft)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[buf].mail_initial_cursor = true
  vim.bo[buf].filetype = ft or "mail"
  drain()
  return buf
end
mail.setup({ treesitter = false, cmp_contacts = false })
local src = require("mail.cmp-contacts").new(mail.config)
local function complete(line, col)
  local buf = buffer({ "To: me@example.org", "Subject: Hello", "", line })
  col = col or #line
  vim.api.nvim_win_set_cursor(0, { 4, col })
  local response
  src:complete({ context = { bufnr = buf, cursor = { row = 4, col = col + 1 },
    cursor_line = line, cursor_before_line = line:sub(1, col), cursor_after_line = line:sub(col + 1) } },
    function(value) response = value end)
  drain()
  return response, buf
end
for _, key in ipairs({ "best", "groetjes", "sounds" }) do
  local response, buf = complete("Before !" .. key .. " afterwards", #"Before !" + #key)
  local found
  for _, item in ipairs(response.items) do if item.label == "!" .. key then found = item end end
  eq(found ~= nil, true, "phrase is available without contact lookup")
  local edit = found.textEdit
  vim.api.nvim_buf_set_text(buf, edit.range.start.line, edit.range.start.character,
    edit.range["end"].line, edit.range["end"].character, vim.split(edit.newText, "\n", { plain = true }))
  eq(table.concat(vim.api.nvim_buf_get_lines(buf, 3, -1, false), "\n"),
    "Before " .. mail.config.phrases[key] .. " afterwards", "phrase preserves surrounding text and expands newlines")
end
local response = complete("Écrire !best", #"Écrire !be")
local item
for _, candidate in ipairs(response.items) do if candidate.label == "!best" then item = candidate end end
eq(item.textEdit.range.start.character, #"Écrire ", "phrase range uses byte offsets")
eq(item.textEdit.range["end"].character, #"Écrire !best", "middle-of-word completion replaces the whole shortcut")
for _, line in ipairs({ "Wow!best", "![alt](image.png)", "`!best", "> !best", "    !best", "Done! " }) do
  response = complete(line)
  eq(#response.items, 0, "phrase stays out of punctuation, images, code and quotes: " .. line)
end
local buf = buffer({ "To: !best", "Subject: !best", "", "```", "!best", "```", "!best" })
for _, row in ipairs({ 1, 2, 5 }) do
  vim.api.nvim_win_set_cursor(0, { row, #vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] })
  eq(src:is_available(), false, "phrase source stays out of headers and fenced code")
end
vim.api.nvim_win_set_cursor(0, { 7, 5 })
eq(src:is_available(), true, "phrase source resumes after code fence")
mail.setup({ treesitter = false, cmp_contacts = false, phrases = {} })
eq(require("mail.cmp-contacts").new(mail.config):is_available(), false, "empty phrase list disables shortcuts")

-- Folding keeps the direct reply open and closes only the older nested text.
buf = buffer({ "To: me@example.org", "Subject: Hi", "", "Reply", "> Most recent",
  "> Continued", ">> Older", ">> Continued", ">>> Oldest", ">>> Continued",
  "> Latest again", "", "```", ">> literal code", "```" })
vim.cmd("normal! zx")
eq(vim.fn.foldclosed(5), -1, "most recent quoted reply stays open")
eq(vim.fn.foldclosed(7), 7, "older reply is folded")
eq(vim.fn.foldclosedend(7), 10, "fold includes deeper history")
eq(vim.fn.foldclosed(11), -1, "newer reply after history remains open")
eq(vim.fn.foldlevel(14), 0, "code is not mistaken for quoted history")
vim.api.nvim_win_set_cursor(0, { 7, 0 })
vim.cmd("normal! zo")
eq(vim.fn.foldclosed(7), -1, "standard zo opens history")
eq(vim.fn.foldclosed(9), 9, "deeper quotes fold independently")
vim.cmd.split()
drain()
eq(vim.fn.foldclosed(7), -1, "split inherits an opened fold")
vim.cmd.close()
drain()
eq(vim.fn.foldclosed(7), -1, "changing focus does not close an opened fold")
local other = buffer({ "plain" }, "text")
eq(vim.wo.foldexpr:find("mail.folds", 1, true), nil, "fold expression does not leak to other filetypes")
vim.api.nvim_set_current_buf(buf)
drain()
eq(vim.fn.foldclosed(7), -1, "returning to draft preserves manually opened history")
mail.setup({ treesitter = false, cmp_contacts = false, fold_quotes = false })
eq(vim.wo.foldexpr:find("mail.folds", 1, true), nil, "folding can be disabled")
buf = buffer({ "To: x", "", "> ```", "> > literal code", "> ```", ">> Older" })
eq(require("mail.folds").level(4), 1, "quoted code preserves only its outer quote depth")

-- Draft checks use only local data and ignore quoted history and code.
mail.setup({ treesitter = false, cmp_contacts = false })
buf = buffer({ "To: Alice <alice@example.org>", "Cc: bob@example.org", "Bcc: ", "Subject: Hi", "",
  "Hello", "> TODO quoted", "```", "TODO code", "```", "Use `TODO` as a label." })
eq(check.inspect(buf), {}, "clean draft has no false positives")
buf = buffer({ "To: ", "Cc: ", "Bcc: hidden@example.org", "Subject: Hello", "", "Private message" })
eq(check.inspect(buf), {}, "Bcc-only draft is valid")
buf = buffer({ 'To: "Doe, Alice" (team) <alice@example.org>, friends: bob@example.org;', "Cc: Alice <ALICE@example.org>",
  "Subject: ", "", "TODO write this", "[insert date]", "!best", "> !best", "`!best`", "![x](</missing/test%20image.png>)" })
local findings = check.inspect(buf)
eq(#findings, 6, "duplicate, subject, placeholders, phrase and missing image are reported")
eq(findings[1].message, "Duplicate recipient: ALICE@example.org", "recipient parsing handles names, comments and groups")
eq(findings[#findings].message, "Image file not found: /missing/test image.png", "encoded image paths are decoded")
local root = vim.fn.getcwd() .. "/tmp/check-tests"
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "image" }, root .. "/a (b) [c].png")
buf = buffer({ "To: me@example.org", "Subject: Images", "",
  "![a \\[b\\]](<a%20(b)%20%5Bc%5D.png>)",
  "![remote](https://example.org/missing.png)", "![inline](cid:picture)",
  "![ref][pic]", "[pic]: <a%20(b)%20%5Bc%5D.png>",
  "![missing][oops]", "[oops]: <missing.png>", "\\![literal](missing.png)" })
vim.api.nvim_buf_set_name(buf, root .. "/draft.eml")
findings = check.run(buf)
eq(#findings, 1, "images handle escaped descriptions, references, URI schemes and literal Markdown")
eq(findings[1].lnum, 8, "reference image points to use site")
local ns = vim.api.nvim_create_namespace("mail_draft_check")
eq(#vim.diagnostic.get(buf, { namespace = ns }), 1, "manual check publishes diagnostics")
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
eq(#vim.diagnostic.get(buf, { namespace = ns }), 0, "editing clears stale diagnostics")
local confirmations, answer = 0, 1
vim.fn.confirm = function(message, buttons, default)
  confirmations = confirmations + 1
  eq(message:find("Image file not found:", 1, true) ~= nil, true, "confirmation includes findings")
  eq(buttons, "&Keep editing\n&Leave anyway", "confirmation offers a choice")
  eq(default, 1, "confirmation defaults to keeping draft")
  return answer
end
eq(check.command("wq"), false, "keep editing cancels quit command")
answer = 2
eq(check.command("silent write | quit"), true, "leave anyway permits command chain")
local before = confirmations
eq(check.command("write"), true, "ordinary writes are not gated")
eq(confirmations, before, "ordinary writes do not prompt")
mail.setup({ treesitter = false, cmp_contacts = false, draft_check = false })
eq(check.command("quit"), true, "automatic checks can be disabled")
eq(confirmations, before, "disabled checks do not prompt")
eq(#check.inspect(buf), 1, "manual checks still work when automatic checks are off")

-- A real command-line/UI test catches QuitPre's inability to cancel :quit.
local function child_test(command, leave, clean)
  local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, { rpc = true })
  local function lua(code, args) return vim.rpcrequest(child, "nvim_exec_lua", code, args or {}) end
  local ok, err = pcall(function()
    vim.rpcrequest(child, "nvim_ui_attach", 100, 30, { rgb = true })
    lua([[
      local root, filename, clean = ...
      vim.opt.rtp = { root, vim.env.VIMRUNTIME }
      vim.opt.packpath = {}
      vim.o.swapfile = false
      vim.api.nvim_buf_set_name(0, filename)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "To: me@example.org", clean and "Subject: Hello" or "Subject: ", "", "Body" })
      vim.bo.filetype = "mail"
      vim.b.mail_initial_cursor = true
      vim.cmd.write({ bang = true })
      require("mail").setup({ treesitter = false, cmp_contacts = false })
    ]], { vim.fn.getcwd(), root .. "/quit-" .. command:gsub("%W", "") .. ".eml", clean })
    if command == "wq" or command == "q!" then lua([[vim.api.nvim_buf_set_lines(0, 3, 4, false, { "Edited body" })]]) end
    local input = command == "ZZ" and "ZZ" or ":" .. command .. "\r"
    vim.rpcrequest(child, "nvim_input", input)
    if not clean then
      eq(vim.wait(2000, function()
        return vim.rpcrequest(child, "nvim_get_mode").mode == "r?"
      end, 10), true, "real quit displays confirmation: " .. command .. " " .. vim.inspect(vim.rpcrequest(child, "nvim_get_mode")))
      vim.rpcrequest(child, "nvim_input", leave and "l" or "k")
    end
    if leave or clean then
      eq(vim.fn.jobwait({ child }, 2000)[1], 0, "confirmed or clean quit exits: " .. command)
    else
      drain()
      eq(lua("return vim.api.nvim_get_current_line()"), "Subject: ", "keep editing leaves draft open at finding: " .. command)
      if command == "wq" or command == "q!" then
        eq(lua("return vim.bo.modified"), true, "cancelling quit preserves unsaved changes")
        eq(vim.fn.readfile(root .. "/quit-" .. command:gsub("%W", "") .. ".eml")[4], "Body",
          "cancelled quit does not write or discard changes")
      end
      eq(vim.fn.jobwait({ child }, 0)[1], -1, "editor process remains alive: " .. command)
      lua([[require("mail").setup({ treesitter = false, cmp_contacts = false, draft_check = false })]])
    end
  end)
  vim.fn.jobstop(child)
  assert(ok, err)
end
for _, command in ipairs({ "q", "wq", "q!", "x", "qa", "wqa", "ZZ" }) do child_test(command, false, false) end
child_test("wq", true, false)
child_test("q", false, true)
print(("%d workflow checks passed"):format(checks))
