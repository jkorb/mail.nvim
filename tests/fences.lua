vim.opt.runtimepath = { vim.fn.getcwd(), vim.env.VIMRUNTIME }
vim.opt.packpath = {}
local parser_path, markdown = vim.env.MAIL_NVIM_PARSER, vim.env.MAIL_NVIM_MARKDOWN_PARSERS
if not parser_path or not markdown then
  print("Fence rendering checks skipped; set MAIL_NVIM_PARSER and MAIL_NVIM_MARKDOWN_PARSERS.")
  return
end
local checks = 0
local function eq(actual, expected, message)
  checks = checks + 1
  assert(vim.deep_equal(actual, expected), message .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual))
end
local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, { rpc = true })
-- A redraw regression must fail the test instead of leaving an RPC hung.
local watchdog = vim.defer_fn(function() pcall(vim.fn.jobstop, child) end, 15000)
local function lua(code, args) return vim.rpcrequest(child, "nvim_exec_lua", code, args or {}) end
local function input(keys)
  vim.rpcrequest(child, "nvim_input", keys)
  vim.wait(20, function() return false end, 1)
end
local function screen()
  vim.rpcrequest(child, "nvim_command", "redraw!")
  return lua([[
    local lines = {}
    for row = 1, 27 do
      local cells = {}
      for col = 1, 95 do cells[#cells + 1] = vim.fn.screenstring(row, col) end
      lines[#lines + 1] = table.concat(cells):gsub("%s+$", "")
    end
    return table.concat(lines, "\n")
  ]])
end
local function shows(text, message) eq(screen():find(text, 1, true) ~= nil, true, message) end
local function draft(body)
  lua([[
    local body = ...
    local lines = { "To: me@example.org", "Subject: Fences", "" }
    vim.list_extend(lines, body)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    vim.cmd("normal! zx")
    require("mail.view").refresh(vim.api.nvim_get_current_buf())
  ]], { body })
end
local ok, err = pcall(function()
  vim.rpcrequest(child, "nvim_ui_attach", 100, 32, { rgb = true })
  lua([[
    local root, parser_path, markdown = ...
    vim.opt.rtp = { root, vim.env.VIMRUNTIME }
    vim.opt.packpath = {}
    vim.o.swapfile, vim.o.ruler, vim.o.showmode = false, false, false
    vim.o.laststatus = 0
    vim.treesitter.language.add("mail", { path = parser_path })
    for _, lang in ipairs({ "markdown", "markdown_inline" }) do
      vim.treesitter.language.add(lang, { path = markdown .. "/" .. lang .. ".so" })
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "To: me@example.org", "Subject: Fences", "", "Hello" })
    vim.bo.filetype = "mail"
    vim.b.mail_initial_cursor = true
    -- Match LazyVim's ordering: highlighting is already active before setup.
    vim.treesitter.start(0, "mail")
    _G.original_highlighter = vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()]
    _G.original_markdown_query = vim.treesitter.query.get("markdown", "highlights")
    require("mail").setup({ cmp_contacts = false })
  ]], { vim.fn.getcwd(), parser_path, markdown })
  eq(lua([[return vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= original_highlighter]]), true,
    "mail replaces a highlighter started by another plugin")
  eq(lua([[return vim.treesitter.query.get("markdown", "highlights") == original_markdown_query]]), true,
    "global Markdown query is unchanged")
  lua([[_G.mail_highlighter = vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()]; require("mail.treesitter").start(vim.api.nvim_get_current_buf())]])
  eq(lua([[return vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] == mail_highlighter]]), true,
    "repeated attachment reuses the mail highlighter")

  for _, fence in ipairs({ "```", "````", "~~~" }) do
    draft({ fence .. "text", "> literal code", fence, "", "> quote after code", "End of message" })
    shows(fence .. "text", "opening fence and language stay visible")
    shows("\n" .. fence .. "\n", "closing fence stays visible")
    shows("> literal code", "unquoted code keeps literal greater-than signs")
    shows("┃ quote after code", "quote conceal resumes after a fence")
    draft({ "> " .. fence .. "text", "> > literal code", "> " .. fence, "> following quote", ">> older history" })
    shows("┃ " .. fence .. "text", "quoted fence keeps its outer quote bar")
    shows("┃ > literal code", "quoted code conceals only its outer quote prefix")
    shows("┃ following quote", "code continuation does not suppress the following quote bar")
    eq(lua([[return vim.fn.foldclosed(5)]]), -1, "literal > in quoted code is not folded")
  end
  draft({ "> ```", "> > ```", "> > still literal", "> ```", ">> older history" })
  shows("┃ > still literal", "a deeper literal fence does not close the outer quoted fence")
  eq(lua([[return vim.fn.foldclosed(6)]]), -1, "literal nested fence does not fold the rest of the code")
  draft({ "````", "still code", "```", ">> literal after short closer", "End of message" })
  shows("````", "unfinished four-backtick fence remains editable")
  shows(">> literal after short closer", "short closer does not hide or fold code")
  shows("End of message", "unfinished fence leaves the end of the message visible")
  draft({ "```not`a`fence", "> quote after inline backticks" })
  shows("┃ quote after inline backticks", "invalid backtick info string does not swallow quoted mail")
  draft({ "    >> indented code", "", ">     >> quoted indented code", "", "> latest" })
  shows("    >> indented code", "indented code keeps literal quote characters")
  shows("┃     >> quoted indented code", "quoted indented code keeps only its outer quote bar")
  eq(lua([[return vim.fn.foldclosed(4)]]), -1, "indented code is not folded as history")
  draft({ "```", ">> literal", "```", "> latest", ">> history" })
  lua([[vim.api.nvim_win_set_cursor(0, { 1, 0 }); vim.cmd.MailViewToggle()]])
  shows("```", "view toggle leaves fences visible")
  shows("> latest", "view toggle reveals quote source")
  lua([[vim.cmd.MailViewToggle()]])
  shows("┃ latest", "view toggle restores quote bars")
  draft({ "```markdown", "| Name | Value |", "| --- | --- |", "| a | b |", "```", "> latest" })
  shows("| Name | Value |", "Markdown nested inside a code fence keeps its source table")
  eq(lua([[
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("mail_view"), 0, -1, { details = true })) do
      if mark[4].virt_text then return true end
    end
    return false
  ]]), false, "view does not render tables from injected code languages")

  if vim.env.MAIL_NVIM_MINI_PAIRS then
    -- Load after mail setup, as mini.pairs does on VeryLazy in LazyVim.
    lua([[
      vim.opt.rtp:append(...)
      require("mini.pairs").setup()
      if vim.env.MAIL_NVIM_LAZYVIM then
        -- Exercise LazyVim's actual wrapper and options without booting its UI.
        local root = vim.env.MAIL_NVIM_LAZYVIM
        Snacks = { toggle = function() return { map = function() end } end }
        local specs = dofile(root .. "/lua/lazyvim/plugins/coding.lua")
        dofile(root .. "/lua/lazyvim/util/mini.lua").pairs(specs[1].opts)
      end
    ]], { vim.env.MAIL_NVIM_MINI_PAIRS })
    draft({ "", "", "> ```text", "> quoted code", "> ```", "> latest", "Tail of draft" })
    lua([[vim.api.nvim_win_set_cursor(0, { 4, 0 })]])
    input("i")
    for _ = 1, 3 do input("`") end
    eq(lua([[return vim.api.nvim_get_current_line()]]), "```", "three typed backticks produce exactly three")
    shows("```", "new fence stays visible while typing")
    shows("Tail of draft", "incomplete fence leaves existing draft visible")
    input("<CR>")
    input("code > value")
    input("<CR>")
    for _ = 1, 3 do input("`") end
    eq(lua([[return vim.api.nvim_get_current_line()]]), "```", "closing fence has exactly three backticks")
    input("<Esc>")
    shows("┃ latest", "quote bars recover after completing a new code block")
    shows("┃ quoted code", "quoted code keeps its quote bar after edits above it")
    -- Deleting and restoring a fence repeatedly must not leave hidden lines.
    for _ = 1, 3 do
      lua([[vim.api.nvim_win_set_cursor(0, { 4, 0 })]])
      input("dd")
      shows("code > value", "deleting opening fence does not hide code")
      shows("Tail of draft", "deleting fence does not hide the draft tail")
      input("u")
      shows("```", "undo restores a visible fence")
      shows("┃ latest", "undo restores quote bars")
    end
    lua([[vim.api.nvim_win_set_cursor(0, { 4, 0 })]])
    input("A<BS><BS><BS><Esc>")
    eq(lua([[return vim.api.nvim_buf_get_lines(0, 3, 4, false)[1] ]]), "", "fence can be removed with backspace")
    draft({ "Use " })
    lua([[vim.api.nvim_win_set_cursor(0, { 4, 3 })]])
    input("A`")
    eq(lua([[return vim.api.nvim_get_current_line()]]), "Use ``", "inline code still pairs backticks")
    input("value`<Esc>")
    eq(lua([[return vim.api.nvim_get_current_line()]]), "Use `value`", "inline closer still skips the paired backtick")
    lua([[vim.bo.filetype = "text"]])
    eq(lua([[return vim.fn.maparg("`", "i", false, true).buffer]]), 0, "leaving mail restores global pairing")
    lua([[vim.keymap.set("i", "`", "custom", { buffer = true }); vim.bo.filetype = "mail"]])
    eq(lua([[return vim.fn.maparg("`", "i", false, true).rhs]]), "custom", "user backtick mapping is preserved")
  else
    print("Pairing checks skipped; set MAIL_NVIM_MINI_PAIRS to a mini.pairs checkout.")
  end
end)
watchdog:stop()
watchdog:close()
vim.fn.jobstop(child)
assert(ok, err)
print(("%d fence checks passed"):format(checks))
