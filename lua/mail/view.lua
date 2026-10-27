local M = {}
local ns = vim.api.nvim_create_namespace("mail_view")
local states, windows, pending = {}, {}, false

local function highlights()
  local link = vim.api.nvim_get_hl(0, { name = "Special", link = false })
  vim.api.nvim_set_hl(0, "MailLink", { default = true, fg = link.fg, ctermfg = link.ctermfg, underline = true })
  vim.api.nvim_set_hl(0, "MailTableBorder", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "MailTableHeader", { default = true, link = "Title" })
  for level = 1, 6 do
    vim.api.nvim_set_hl(0, "MailQuote" .. level, { default = true, link = "@markup.heading." .. level })
  end
end

local function restore(win)
  local saved = windows[win]
  if saved and vim.api.nvim_win_is_valid(win) then
    for name, value in pairs(saved.original) do
      if vim.wo[win][name] == saved.applied[name] then vim.wo[win][name] = value end
    end
  end
  windows[win] = nil
end

local function sync_windows()
  for win in pairs(windows) do
    if not vim.api.nvim_win_is_valid(win) or not states[vim.api.nvim_win_get_buf(win)] then restore(win) end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local state = states[vim.api.nvim_win_get_buf(win)]
    if state then
      local saved = windows[win]
      if not saved then
        saved = { original = { conceallevel = vim.wo[win].conceallevel, concealcursor = vim.wo[win].concealcursor }, applied = {} }
        -- A new split inherits the mail window's already modified options.
        for other, previous in pairs(windows) do
          if vim.api.nvim_win_is_valid(other) and vim.api.nvim_win_get_buf(other) == vim.api.nvim_win_get_buf(win)
            and vim.deep_equal(saved.original, previous.applied) then
            saved.original = vim.deepcopy(previous.original)
            break
          end
        end
        windows[win] = saved
      end
      local values = { conceallevel = state.enabled and 2 or 0, concealcursor = "" }
      for name, value in pairs(values) do
        -- Remember deliberate option changes, so leaving mail restores those too.
        if saved.applied[name] ~= nil and vim.wo[win][name] ~= saved.applied[name] then
          saved.original[name] = vim.wo[win][name]
        end
        vim.wo[win][name], saved.applied[name] = value, value
      end
    end
  end
end

local function walk(node, visit)
  if visit(node) == false then return end
  for child in node:iter_children() do
    if child:named() then walk(child, visit) end
  end
end

local function range(node)
  return { node:range() }
end

local function contains(ranges, row, col)
  for _, r in ipairs(ranges) do
    if (row > r[1] or row == r[1] and col >= r[2])
      and (row < r[3] or row == r[3] and col < r[4]) then return true end
  end
  return false
end

local function mark(plan, node, opts)
  local r = range(node)
  opts.end_row, opts.end_col = r[3], r[4]
  plan.marks[#plan.marks + 1] = { r[1], r[2], opts }
end

-- Render table cells using the same conceal and highlight captures as the
-- injected Markdown highlighter, including link labels and Unicode entities.
local function cell_chunks(text, row, first, last, spans, header)
  while first < last and text:sub(first + 1, first + 1):match("%s") do first = first + 1 end
  while last > first and text:sub(last, last):match("%s") do last = last - 1 end
  local boundaries, seen = { first, last }, { [first] = true, [last] = true }
  for _, span in ipairs(spans[row] or {}) do
    for _, col in ipairs({ span.first, span.last }) do
      if col > first and col < last and not seen[col] then
        boundaries[#boundaries + 1], seen[col] = col, true
      end
    end
  end
  table.sort(boundaries)
  local chunks, width = {}, 0
  for i = 1, #boundaries - 1 do
    local from, to = boundaries[i], boundaries[i + 1]
    local value, groups, hidden = text:sub(from + 1, to), { header and "MailTableHeader" or "Normal" }, nil
    for _, span in ipairs(spans[row] or {}) do
      if from >= span.first and from < span.last then
        if span.conceal ~= nil then hidden = span end
        if span.hl then groups[#groups + 1] = span.hl end
      end
    end
    if hidden then value = from == hidden.first and hidden.conceal or "" end
    -- Tabs in virtual text need expanding before measuring column widths.
    value = value:gsub("\\|", "|"):gsub("\t", "    ")
    if value ~= "" then
      chunks[#chunks + 1] = { value, groups }
      width = width + vim.fn.strdisplaywidth(value)
    end
  end
  return chunks, width
end

local function table_plan(node, lines, spans)
  local result = { range = range(node), rows = {} }
  local widths, align = {}, {}
  for child in node:iter_children() do
    local kind, r = child:type(), range(child)
    if kind == "pipe_table_header" or kind == "pipe_table_row" or kind == "pipe_table_delimiter_row" then
      local entry = { row = r[1], col = r[2], cells = {}, delimiter = kind == "pipe_table_delimiter_row" }
      for cell in child:iter_children() do
        if cell:type() == "pipe_table_cell" or cell:type() == "pipe_table_delimiter_cell" then
          local cr, index = range(cell), #entry.cells + 1
          if entry.delimiter then
            local value = lines[cr[1] + 1]:sub(cr[2] + 1, cr[4])
            align[index] = value:match("^:.*:$") and "center" or value:match(":$") and "right" or "left"
            entry.cells[index] = {}
          else
            local chunks, width = cell_chunks(lines[cr[1] + 1], cr[1], cr[2], cr[4], spans, kind == "pipe_table_header")
            entry.cells[index] = { chunks = chunks, width = width }
            widths[index] = math.max(widths[index] or 3, width)
          end
        end
      end
      result.rows[#result.rows + 1] = entry
    end
  end
  for _, entry in ipairs(result.rows) do
    local chunks = { { entry.delimiter and "├" or "│", "MailTableBorder" } }
    for i, width in ipairs(widths) do
      if entry.delimiter then
        chunks[#chunks + 1] = { string.rep("─", width + 2) .. (i == #widths and "┤" or "┼"), "MailTableBorder" }
      else
        local cell = entry.cells[i] or { chunks = {}, width = 0 }
        local padding = width - cell.width
        local left = align[i] == "right" and padding or align[i] == "center" and math.floor(padding / 2) or 0
        chunks[#chunks + 1] = { string.rep(" ", left + 1), "Normal" }
        vim.list_extend(chunks, cell.chunks)
        chunks[#chunks + 1] = { string.rep(" ", padding - left + 1), "Normal" }
        chunks[#chunks + 1] = { "│", "MailTableBorder" }
      end
    end
    entry.chunks = chunks
  end
  return result
end

local function build(buf)
  local plan = { marks = {}, tables = {} }
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "mail")
  if not ok or not parser then return plan end
  local parsed = pcall(parser.parse, parser, true)
  if not parsed then return plan end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local code, links, quotes, tables, spans = {}, {}, {}, {}, {}
  local body
  parser:for_each_tree(function(tree, language)
    local lang = language:lang()
    if language == parser then
      walk(tree:root(), function(node)
        if node:type() == "body" then body = range(node) end
        if node:type() == "quote_symbol" then quotes[#quotes + 1] = node end
      end)
    elseif lang == "markdown" and language:parent() == parser then
      walk(tree:root(), function(node)
        local kind = node:type()
        if kind == "fenced_code_block" or kind == "indented_code_block" or kind == "html_block" then
          code[#code + 1] = range(node)
          return false
        elseif kind == "pipe_table" then tables[#tables + 1] = node end
      end)
    elseif lang == "markdown_inline" and language:parent() and language:parent():parent() == parser then
      local query_ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
      if query_ok and query then
        for id, node, metadata in query:iter_captures(tree:root(), buf) do
          local r, name = range(node), query.captures[id]
          if r[1] == r[3] and name:sub(1, 1) ~= "_" and name ~= "nospell" and name ~= "spell" then
            spans[r[1]] = spans[r[1]] or {}
            spans[r[1]][#spans[r[1]] + 1] = {
              first = r[2], last = r[4], conceal = (metadata[id] or metadata).conceal,
              hl = name ~= "conceal" and "@" .. name .. "." .. lang or nil,
            }
          end
        end
      end
      walk(tree:root(), function(node)
        local kind, r = node:type(), range(node)
        if kind == "code_span" then code[#code + 1] = r; return false end
        if kind == "inline_link" or kind == "image" or kind == "full_reference_link"
          or kind == "collapsed_reference_link" or kind == "shortcut_link" then
          links[#links + 1] = r
        end
        if kind == "link_text" or kind == "image_description" or kind == "uri_autolink" or kind == "email_autolink" then
          mark(plan, node, { hl_group = "MailLink", priority = 125 })
          spans[r[1]] = spans[r[1]] or {}
          spans[r[1]][#spans[r[1]] + 1] = { first = r[2], last = r[4], hl = "MailLink" }
        elseif kind == "backslash_escape" then
          spans[r[1]] = spans[r[1]] or {}
          spans[r[1]][#spans[r[1]] + 1] = { first = r[2], last = r[2] + 1, conceal = "" }
        end
      end)
    end
  end)
  local body_rows = require("mail.body").scan(buf).rows
  local quote_counts = {}
  for _, node in ipairs(quotes) do
    local row = node:range()
    quote_counts[row] = (quote_counts[row] or 0) + 1
    -- Markdown code ranges include block-quote continuations, sometimes even
    -- the next line's prefix. Keep the outer mail quote bars, while leaving
    -- literal > characters inside the code untouched.
    if body_rows[row + 1] and quote_counts[row] <= body_rows[row + 1].depth then
      local level = math.min(body_rows[row + 1].depth, 6)
      mark(plan, node, { conceal = require("mail").config.view.quote_char, hl_group = "MailQuote" .. level, priority = 150 })
    end
  end
  if body then
    for row = body[1], math.min(body[3], #lines - 1) do
      local line, offset = lines[row + 1], 1
      while true do
        local first, last = line:find("https?://[^%s%c<>\"`|]+", offset)
        if not first then break end
        local url = line:sub(first, last):gsub("[.,;:!?]+$", "")
        -- Retain balanced URL parentheses, but omit surrounding prose brackets.
        for close, open in pairs({ [")"] = "(", ["]"] = "[" }) do
          while url:sub(-1) == close do
            local _, opens = url:gsub("%" .. open, "")
            local _, closes = url:gsub("%" .. close, "")
            if closes <= opens then break end
            url = url:sub(1, -2)
          end
        end
        if not contains(code, row, first - 1) and not contains(links, row, first - 1) then
          plan.marks[#plan.marks + 1] = {
            row, first - 1, { end_col = first - 1 + #url, hl_group = "MailLink", url = url, priority = 125 },
          }
          spans[row] = spans[row] or {}
          spans[row][#spans[row] + 1] = { first = first - 1, last = first - 1 + #url, hl = "MailLink" }
        end
        offset = last + 1
      end
    end
  end
  for _, node in ipairs(tables) do plan.tables[#plan.tables + 1] = table_plan(node, lines, spans) end
  return plan
end

function M.refresh(buf)
  local state = states[buf]
  if not state or not vim.api.nvim_buf_is_loaded(buf) then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local cursors = {}
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do cursors[#cursors + 1] = vim.api.nvim_win_get_cursor(win)[1] - 1 end
  local visual = vim.api.nvim_get_current_buf() == buf and vim.fn.mode():match("[vV\22]") ~= nil
  local drawing = { tick, state.enabled, cursors, visual }
  if vim.deep_equal(state.drawing, drawing) then return end
  state.drawing = drawing
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not state.enabled or not require("mail").config.treesitter then return end
  if tick ~= state.tick then state.plan, state.tick = build(buf), tick end
  for _, item in ipairs(state.plan.marks) do vim.api.nvim_buf_set_extmark(buf, ns, item[1], item[2], item[3]) end
  for _, tbl in ipairs(state.plan.tables) do
    local editing = visual
    for _, row in ipairs(cursors) do
      if row >= tbl.range[1] and row <= tbl.rows[#tbl.rows].row then editing = true end
    end
    if not editing then
      for _, entry in ipairs(tbl.rows) do
        local line = vim.api.nvim_buf_get_lines(buf, entry.row, entry.row + 1, false)[1]
        vim.api.nvim_buf_set_extmark(buf, ns, entry.row, entry.col, {
          end_col = #line, conceal = "", virt_text = entry.chunks, virt_text_pos = "inline", priority = 200,
        })
      end
    end
  end
end

local function refresh_all()
  sync_windows()
  for buf in pairs(states) do M.refresh(buf) end
end

local function queue()
  if pending then return end
  pending = true
  vim.schedule(function() pending = false; refresh_all() end)
end

function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  if not states[buf] then return end
  states[buf].enabled = not states[buf].enabled
  sync_windows()
  M.refresh(buf)
end

function M.attach(buf)
  if not states[buf] then states[buf] = { enabled = require("mail").config.view.enabled } end
  vim.api.nvim_buf_create_user_command(buf, "MailViewToggle", M.toggle, { desc = "Toggle mail formatting" })
  vim.api.nvim_buf_call(buf, function()
    local previous = vim.b[buf].mail_view_key
    if previous and vim.fn.maparg(previous, "n", false, true).callback == M.toggle then
      vim.keymap.del("n", previous, { buffer = buf })
    end
    vim.b[buf].mail_view_key = nil
    local key = require("mail").config.view.keymap
    if key and vim.fn.maparg(key, "n") == "" then
      vim.keymap.set("n", key, M.toggle, { buffer = buf, desc = "Toggle mail formatting" })
      vim.b[buf].mail_view_key = vim.fn.maparg(key, "n", false, true).lhs
    end
  end)
  sync_windows()
  M.refresh(buf)
end

function M.setup()
  for buf in pairs(states) do
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
  end
  for win in pairs(windows) do restore(win) end
  states = {}
  highlights()
  local group = vim.api.nvim_create_augroup("mail_view", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "CursorMoved", "CursorMovedI",
    "BufWinEnter", "WinEnter", "WinClosed", "ModeChanged" }, { group = group, callback = queue })
  -- Restore before Neovim saves the old buffer's window-local options.
  vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave" }, {
    group = group,
    callback = function()
      restore(vim.api.nvim_get_current_win())
      queue()
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
  vim.api.nvim_create_autocmd({ "FileType", "BufWipeout" }, {
    group = group,
    callback = function(event)
      if states[event.buf] and (event.event == "BufWipeout" or vim.bo[event.buf].filetype ~= "mail") then
        vim.api.nvim_buf_clear_namespace(event.buf, ns, 0, -1)
        if event.event == "FileType" then
          vim.api.nvim_buf_call(event.buf, function()
            local key = vim.b[event.buf].mail_view_key
            if key and vim.fn.maparg(key, "n", false, true).callback == M.toggle then
              vim.keymap.del("n", key, { buffer = event.buf })
            end
            vim.b[event.buf].mail_view_key = nil
          end)
          pcall(vim.api.nvim_buf_del_user_command, event.buf, "MailViewToggle")
        end
        states[event.buf] = nil
        queue()
      end
    end,
  })
end

return M
