vim.opt.runtimepath = { vim.fn.getcwd(), vim.env.VIMRUNTIME }
vim.opt.packpath = {}
vim.o.swapfile = false
vim.o.hidden = true
local checks = 0
local function eq(actual, expected, message)
  checks = checks + 1
  assert(vim.deep_equal(actual, expected), message .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual))
end
local function drain() vim.wait(20, function() return false end, 1) end
local function buffer(lines, ft)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[buf].mail_initial_cursor = true
  vim.bo[buf].filetype = ft or "mail"
  drain()
  return buf
end
local mail, view = require("mail"), require("mail.view")
local ns = vim.api.nvim_create_namespace("mail_view")
local function marks(buf) return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) end

vim.wo.conceallevel, vim.wo.concealcursor = 1, "nc"
mail.setup({ treesitter = false, cmp_contacts = false })
local draft = buffer({ "To: me@example.org", "", "> quoted" })
eq(vim.wo.conceallevel, 2, "mail view enabled by default")
eq(vim.wo.concealcursor, "", "cursor line reveals source")
eq(vim.fn.maparg("\\mv", "n", false, true).buffer, 1, "toggle shortcut is buffer-local")
vim.cmd.MailViewToggle()
eq(vim.wo.conceallevel, 0, "toggle reveals source")
eq(#marks(draft), 0, "toggle clears decorations")
local plain = buffer({ "> unrelated Markdown", "[x](https://example.org)" }, "markdown")
eq(vim.wo.conceallevel, 1, "leaving mail restores conceallevel")
eq(vim.wo.concealcursor, "nc", "leaving mail restores concealcursor")
eq(vim.fn.exists(":MailViewToggle"), 0, "command stays in mail")
eq(vim.fn.maparg("\\mv", "n"), "", "mapping stays in mail")
vim.api.nvim_set_current_buf(draft)
drain()
eq(vim.wo.conceallevel, 0, "toggle survives returning to draft")
vim.cmd.MailViewToggle()
vim.cmd.split()
drain()
eq(vim.wo.conceallevel, 2, "new split uses mail view")
vim.api.nvim_set_current_buf(plain)
drain()
eq(vim.wo.conceallevel, 1, "split restores options inherited before mail view")
vim.cmd.close()
mail.setup({ treesitter = false, cmp_contacts = false, view = false })
drain()
eq(vim.wo.conceallevel, 0, "config can disable view on an existing draft")
vim.cmd.MailViewToggle()
eq(vim.wo.conceallevel, 2, "runtime toggle overrides configured default")
mail.setup({ treesitter = false, cmp_contacts = false, view = { quote_char = "│", keymap = false } })
eq(mail.config.view.enabled, true, "partial view config retains defaults")
eq(vim.fn.maparg("\\mv", "n"), "", "keymap opt-out removes owned mapping")
vim.keymap.set("n", "\\mv", "<cmd>echo 'mine'<cr>", { buffer = draft })
mail.setup({ treesitter = false, cmp_contacts = false })
eq(vim.fn.maparg("\\mv", "n"), "<Cmd>echo 'mine'<CR>", "user mapping preserved")
for _, invalid in ipairs({ "", "xx", "\n", "界" }) do
  eq(pcall(mail.setup, { view = { quote_char = invalid } }), false, "reject invalid quote character")
end
vim.bo[draft].filetype = "text"
drain()
eq(vim.wo.conceallevel, 1, "filetype change restores window options")
eq(vim.fn.exists(":MailViewToggle"), 0, "filetype change removes view command")
eq(vim.fn.maparg("\\mv", "n"), "<Cmd>echo 'mine'<CR>", "filetype cleanup preserves user mapping")

local parser_path, markdown = vim.env.MAIL_NVIM_PARSER, vim.env.MAIL_NVIM_MARKDOWN_PARSERS
if parser_path and parser_path ~= "" and markdown and markdown ~= "" then
  vim.treesitter.language.add("mail", { path = parser_path })
  for _, lang in ipairs({ "markdown", "markdown_inline" }) do
    vim.treesitter.language.add(lang, { path = markdown .. "/" .. lang .. ".so" })
  end
  mail.setup({ cmp_contacts = false })
  local lines = {
    "To: me@example.org", "Subject: https://header.example.org", "",
    "> quote", "> > nested", "",
    "A [label](https://example.org) and https://plain.example.org/test_(one).",
    "`https://code.example.org`", "",
    "| Name | Right | Center |", "| :--- | ---: | :---: |",
    "| **界** | [Web](https://example.org) | a |", "| `a\\|b` | x \\| y | &amp; |", "",
    "```text", "> literal", "https://fenced.example.org", "```",
  }
  draft = buffer(lines)
  local text, quotes, urls, tables = {}, 0, {}, {}
  for _, m in ipairs(marks(draft)) do
    local opts = m[4]
    if opts.conceal == "┃" then quotes = quotes + 1 end
    if opts.url then urls[#urls + 1] = opts.url end
    if opts.virt_text then
      text = {}
      for _, chunk in ipairs(opts.virt_text) do text[#text + 1] = chunk[1] end
      tables[#tables + 1] = table.concat(text)
    end
    eq(m[2] == 15 or m[2] == 16, false, "no decorations inside fenced code")
  end
  eq(quotes, 3, "nested quote bars")
  eq(urls, { "https://plain.example.org/test_(one)" }, "bare links exclude headers, code and trailing punctuation")
  eq(tables, {
    "│ Name │ Right │ Center │",
    "├──────┼───────┼────────┤",
    "│ 界   │   Web │   a    │",
    "│ a|b  │ x | y │   &    │",
  }, "tables align Unicode, link labels, escaped pipes and entities")
  eq(vim.api.nvim_buf_get_lines(draft, 0, -1, false), lines, "rendering never rewrites draft")
  vim.api.nvim_win_set_cursor(0, { 12, 4 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = draft })
  drain()
  local function table_count()
    local count = 0
    for _, m in ipairs(marks(draft)) do if m[4].virt_text then count = count + 1 end end
    return count
  end
  eq(table_count(), 0, "moving into table reveals its source")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = draft })
  drain()
  eq(table_count(), 4, "moving out restores table")
  local original_win = vim.api.nvim_get_current_win()
  vim.cmd.split()
  vim.api.nvim_win_set_cursor(0, { 12, 4 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = draft })
  drain()
  eq(table_count(), 0, "a second window editing a table reveals its source")
  vim.cmd.close()
  drain()
  eq(vim.api.nvim_get_current_win(), original_win, "original window remains")
  eq(table_count(), 4, "closing editing window restores rendered table")
  vim.api.nvim_buf_set_lines(draft, 11, 12, false, { "| Longer name | changed | b |" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = draft })
  drain()
  local changed
  for _, m in ipairs(marks(draft)) do
    if m[2] == 11 and m[4].virt_text then
      local chunks = {}
      for _, chunk in ipairs(m[4].virt_text) do chunks[#chunks + 1] = chunk[1] end
      changed = table.concat(chunks)
    end
  end
  eq(changed, "│ Longer name │ changed │   b    │", "table recalculated after editing")
  vim.cmd.MailViewToggle()
  eq(#marks(draft), 0, "toggle removes quotes, links and tables")
  eq(vim.wo.conceallevel, 0, "toggle also disables native Markdown conceal")
  mail.setup({ cmp_contacts = false, view = { quote_char = "│" } })
  local thin = 0
  for _, m in ipairs(marks(draft)) do if m[4].conceal == "│" then thin = thin + 1 end end
  eq(thin, 3, "custom quote character takes effect after setup")
  vim.api.nvim_buf_set_lines(draft, 0, -1, false, { "To: x@example.org", "", "Small draft" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = draft })
  drain()
  eq(#marks(draft), 0, "deleting old content removes stale decorations")
  vim.api.nvim_buf_set_lines(draft, 2, -1, false, { "| URL | Other |", "| --- | --- |", "|https://example.org|plain|" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = draft })
  drain()
  local table_urls = {}
  for _, m in ipairs(marks(draft)) do if m[4].url then table_urls[#table_urls + 1] = m[4].url end end
  eq(table_urls, { "https://example.org" }, "bare URLs stop at table separators")

  -- An attached UI verifies actual conceal output, not only extmark metadata.
  local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, { rpc = true })
  local function lua(code, args) return vim.rpcrequest(child, "nvim_exec_lua", code, args or {}) end
  local ok, err = pcall(function()
    vim.rpcrequest(child, "nvim_ui_attach", 100, 30, { rgb = true })
    lua([[
      local root, parser_path, markdown, lines = ...
      vim.opt.rtp = { root, vim.env.VIMRUNTIME }
      vim.opt.packpath = {}
      vim.o.swapfile = false
      vim.treesitter.language.add("mail", { path = parser_path })
      for _, lang in ipairs({ "markdown", "markdown_inline" }) do
        vim.treesitter.language.add(lang, { path = markdown .. "/" .. lang .. ".so" })
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.bo.filetype = "mail"
      vim.b.mail_initial_cursor = true
      require("mail").setup({ cmp_contacts = false, fold_quotes = false })
    ]], { vim.fn.getcwd(), parser_path, markdown, lines })
    local function screen()
      vim.rpcrequest(child, "nvim_command", "redraw!")
      return lua([[
        local lines = {}
        for row = 1, 25 do
          local cells = {}
          for col = 1, 95 do cells[#cells + 1] = vim.fn.screenstring(row, col) end
          lines[#lines + 1] = table.concat(cells):gsub("%s+$", "")
        end
        return table.concat(lines, "\n")
      ]])
    end
    local rendered = screen()
    eq(rendered:find("┃ ┃ nested", 1, true) ~= nil, true, "UI displays nested quote bars")
    eq(rendered:find("A label and https://plain.example.org", 1, true) ~= nil, true, "UI conceals Markdown link syntax")
    eq(rendered:find("│ a|b  │ x | y │   &    │", 1, true) ~= nil, true, "UI displays clean aligned table")
    eq(rendered:find("> literal", 1, true) ~= nil, true, "UI preserves code containing quote characters")
    lua([[vim.api.nvim_win_set_cursor(0, { 4, 0 })]])
    eq(screen():find("> quote", 1, true) ~= nil, true, "cursor line shows literal quote source")
    lua([[vim.api.nvim_win_set_cursor(0, { 12, 4 }); require("mail.view").refresh(vim.api.nvim_get_current_buf())]])
    rendered = screen()
    eq(rendered:find("| **界** | [Web](https://example.org) | a |", 1, true) ~= nil, true, "cursor inside table reveals source in UI")
    eq(rendered:find("├", 1, true), nil, "no rendered table borders remain while editing")
    lua([[vim.api.nvim_win_set_cursor(0, { 1, 0 }); vim.cmd.normal("v")]])
    vim.wait(20, function() return false end, 1)
    eq(screen():find("├", 1, true), nil, "Visual selection shows source tables")
    lua([[vim.cmd.normal({ args = { "\27" }, bang = true })]])
    vim.wait(20, function() return false end, 1)
    eq(screen():find("├", 1, true) ~= nil, true, "leaving Visual mode restores table")
    lua([[vim.cmd.MailViewToggle()]])
    rendered = screen()
    eq(rendered:find("A [label](https://example.org)", 1, true) ~= nil, true, "disabled view shows raw link")
    eq(rendered:find("```text", 1, true) ~= nil, true, "disabled view shows raw code fences")
  end)
  vim.fn.jobstop(child)
  assert(ok, err)
  vim.api.nvim_buf_delete(draft, { force = true })
  drain()
  eq(vim.api.nvim_buf_is_valid(draft), false, "buffer wipe cleans up view without errors")
else
  print("View rendering checks skipped; set MAIL_NVIM_PARSER and MAIL_NVIM_MARKDOWN_PARSERS.")
end
print(("%d view checks passed"):format(checks))
