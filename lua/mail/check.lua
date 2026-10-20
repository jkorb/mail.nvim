local M = {}
local ns = vim.api.nvim_create_namespace("mail_draft_check")

local function mailboxes(value)
  local result, token, address = {}, "", nil
  local quoted, escaped, comment, angle = false, false, 0, false
  local function finish()
    local text = vim.trim(address or token)
    if text:find("@", 1, true) then result[#result + 1] = text end
    token, address = "", nil
  end
  for i = 1, #value do
    local ch = value:sub(i, i)
    if escaped then
      if comment == 0 then token = token .. ch; if angle then address = address .. ch end end
      escaped = false
    elseif ch == "\\" and (quoted or comment > 0) then
      escaped = true
      if comment == 0 then token = token .. ch; if angle then address = address .. ch end end
    elseif ch == '"' and comment == 0 then
      quoted = not quoted
      token = token .. ch
      if angle then address = address .. ch end
    elseif not quoted and ch == "(" then comment = comment + 1
    elseif not quoted and ch == ")" and comment > 0 then comment = comment - 1
    elseif comment == 0 then
      if not quoted and ch == "<" then angle, address = true, ""
      elseif not quoted and ch == ">" then angle = false
      elseif not quoted and not angle and (ch == "," or ch == ";" or ch == ":") then finish()
      else
        token = token .. ch
        if angle then address = address .. ch end
      end
    end
  end
  finish()
  return result
end

local function prose(line)
  -- Hide inline code without changing the byte positions of findings.
  local from = 1
  while true do
    local first, last = line:find("`+", from)
    if not first then return line end
    local close, ending = line:find(string.rep("`", last - first + 1), last + 1, true)
    if not close then return line end
    line = line:sub(1, first - 1) .. string.rep(" ", ending - first + 1) .. line:sub(ending + 1)
    from = ending + 1
  end
end

local function destination(text, first)
  while text:sub(first, first):match("%s") do first = first + 1 end
  if text:sub(first, first) == "<" then return text:match("^<([^>]+)>", first) end
  local depth, escaped, last = 0, false, first - 1
  for pos = first, #text do
    local ch = text:sub(pos, pos)
    if escaped then escaped = false
    elseif ch == "\\" then escaped = true
    elseif ch == "(" then depth = depth + 1
    elseif ch == ")" then
      if depth == 0 then break end
      depth = depth - 1
    elseif ch:match("%s") and depth == 0 then break end
    last = pos
  end
  return last >= first and text:sub(first, last) or nil
end

local function image_paths(line, references)
  local images, offset = {}, 1
  while true do
    local first = line:find("![", offset, true)
    if not first then return images end
    local pos, depth = first + 2, 1
    while pos <= #line and depth > 0 do
      local ch = line:sub(pos, pos)
      if ch == "\\" then pos = pos + 1
      elseif ch == "[" then depth = depth + 1
      elseif ch == "]" then depth = depth - 1 end
      pos = pos + 1
    end
    if depth > 0 then return images end
    local label = line:sub(first + 2, pos - 2)
    local path
    if line:sub(pos, pos) == "(" then path = destination(line, pos + 1)
    else
      local ref = line:match("^%[([^%]]*)%]", pos)
      path = references[vim.trim(ref and ref ~= "" and ref or label):lower()]
    end
    if path and line:sub(first - 1, first - 1) ~= "\\" then
      images[#images + 1] = { path = path, col = first - 1 }
    end
    offset = pos
  end
end

local function local_path(buf, path)
  path = path:gsub("\\([%p])", "%1")
  local scheme = path:match("^([%a][%w+.-]*):")
  if scheme and scheme:lower() ~= "file" then return end
  if scheme then
    local ok, file = pcall(vim.uri_to_fname, path)
    return ok and file or nil
  end
  path = path:gsub("[?#].*$", "")
  if path == "" then return end
  path = vim.uri_decode(path)
  if path:sub(1, 1) == "/" or path:sub(1, 1) == "~" then return vim.fs.normalize(path) end
  local filename = vim.api.nvim_buf_get_name(buf)
  local base = filename ~= "" and vim.fn.fnamemodify(filename, ":h") or vim.fn.getcwd()
  return vim.fs.normalize(base .. "/" .. path)
end

function M.inspect(buf)
  if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].filetype ~= "mail" then return {} end
  local body, findings = require("mail.body").scan(buf), {}
  local function add(row, col, message)
    findings[#findings + 1] = {
      bufnr = buf, lnum = row - 1, col = col or 0,
      message = message, source = "mail.nvim", severity = vim.diagnostic.severity.WARN,
    }
  end
  local subject, recipients, seen = nil, false, {}
  for _, field in ipairs(body.fields) do
    if field.name == "subject" then subject = field end
    if field.name == "to" or field.name == "cc" or field.name == "bcc" then
      if vim.trim(field.value) ~= "" then recipients = true end
      for _, address in ipairs(mailboxes(field.value)) do
        local key = address:lower()
        if seen[key] then add(field.row, field.col, "Duplicate recipient: " .. address)
        else seen[key] = true end
      end
    end
  end
  if not recipients then add(1, 0, "No recipients in To, Cc or Bcc.") end
  if not subject or vim.trim(subject.value) == "" then add(subject and subject.row or 1, 0, "Subject is empty.") end
  if not body.separator then add(1, 0, "Missing blank line between headers and body.") end
  local references = {}
  for row, line in ipairs(body.lines) do
    local info = body.rows[row]
    if not info.header and info.depth == 0 and not info.code then
      local name, start = line:match("^%s*%[([^%]]+)%]:%s*()")
      if name then references[vim.trim(name):lower()] = destination(line, start) end
    end
  end
  for row, line in ipairs(body.lines) do
    local info = body.rows[row]
    if not info.header and info.depth == 0 and not info.code then
      local text = prose(line)
      if not info.signature then
        local first = text:find("%f[%w]TODO%f[%W]") or text:find("%f[%w]FIXME%f[%W]")
          or text:lower():find("%[insert[^%]]*%]") or text:find("<++>", 1, true)
        if first then add(row, first - 1, "Unfinished placeholder.") end
        for col, key in text:gmatch("()!([%w_%-]+)") do
          if require("mail").config.phrases[key] and (col == 1 or text:sub(col - 1, col - 1):match("%s")) then
            add(row, col - 1, "Unexpanded phrase: !" .. key)
          end
        end
      end
      for _, image in ipairs(image_paths(text, references)) do
        local path = local_path(buf, image.path)
        if path and vim.fn.filereadable(path) ~= 1 then add(row, image.col, "Image file not found: " .. path) end
      end
    end
  end
  table.sort(findings, function(a, b) return a.lnum == b.lnum and a.col < b.col or a.lnum < b.lnum end)
  return findings
end

function M.run(buf)
  local findings = M.inspect(buf)
  vim.diagnostic.set(ns, buf, findings, { virtual_text = false })
  return findings
end

local function candidates(all)
  if all then return vim.api.nvim_list_bufs() end
  return { vim.api.nvim_get_current_buf() }
end

function M.allow(all)
  if not require("mail").config.draft_check then return true end
  local findings = {}
  for _, buf in ipairs(candidates(all)) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "mail" then
      vim.list_extend(findings, M.run(buf))
    end
  end
  if #findings == 0 then return true end
  local lines = { "Mail draft checks:" }
  for i, finding in ipairs(findings) do
    if i > 12 then lines[#lines + 1] = ("… and %d more. Use :MailCheck to review."):format(#findings - 12); break end
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(finding.bufnr), ":t")
    lines[#lines + 1] = ("%s:%d: %s"):format(name ~= "" and name or "Draft", finding.lnum + 1, finding.message)
  end
  local choice = vim.fn.confirm(table.concat(lines, "\n") .. "\n\nLeave the editor anyway?", "&Keep editing\n&Leave anyway", 1, "Warning")
  if choice == 2 then return true end
  local first = findings[1]
  vim.schedule(function()
    if vim.api.nvim_buf_is_loaded(first.bufnr) then
      vim.api.nvim_set_current_buf(first.bufnr)
      vim.api.nvim_win_set_cursor(0, { first.lnum + 1, first.col })
    end
  end)
  return false
end

local quit_commands = { quit = true, wq = true, xit = true, exit = true, qall = true, wqall = true, xall = true }
local function last_window()
  local count = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= "help" then count = count + 1 end
  end
  return count <= 1
end

-- CmdlineLeave can cancel a command. QuitPre errors do not stop :quit/:quit!.
function M.command(line)
  local quitting, all = false, false
  while line and line ~= "" do
    local ok, parsed = pcall(vim.api.nvim_parse_cmd, line, {})
    if not ok then return true end
    if quit_commands[parsed.cmd] then
      quitting = true
      all = all or parsed.cmd:find("all", 1, true) ~= nil
    end
    line = parsed.nextcmd
  end
  return not quitting or M.allow(all or last_window())
end

function M.quit(command)
  if M.command(command) then vim.cmd(command) end
end

local shortcuts = {
  ZZ = function() M.quit("xit") end,
  ZQ = function() M.quit("quit!") end,
}

local function unmap(buf)
  for key, callback in pairs(shortcuts) do
    if vim.fn.maparg(key, "n", false, true).callback == callback then vim.keymap.del("n", key, { buffer = buf }) end
  end
end

function M.attach(buf)
  vim.api.nvim_buf_create_user_command(buf, "MailCheck", function()
    if #M.run(buf) == 0 then vim.notify("mail.nvim: No draft issues found.")
    else vim.diagnostic.open_float(buf, { namespace = ns, scope = "buffer" }) end
  end, { desc = "Check the mail draft" })
  vim.api.nvim_buf_call(buf, function()
    unmap(buf)
    for key, callback in pairs(shortcuts) do
      if require("mail").config.draft_check and vim.fn.maparg(key, "n") == "" then
        vim.keymap.set("n", key, callback, { buffer = buf, desc = "Check draft and quit" })
      end
    end
  end)
end

function M.setup()
  vim.diagnostic.reset(ns)
  local group = vim.api.nvim_create_augroup("mail_draft_check", { clear = true })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group, pattern = ":",
    callback = function()
      if not vim.v.event.abort and not M.command(vim.fn.getcmdline()) then vim.cmd("let v:event.abort = v:true") end
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "FileType" }, {
    group = group,
    callback = function(event)
      vim.diagnostic.reset(ns, event.buf)
      if event.event == "FileType" and vim.bo[event.buf].filetype ~= "mail" then
        vim.api.nvim_buf_call(event.buf, function() unmap(event.buf) end)
        pcall(vim.api.nvim_buf_del_user_command, event.buf, "MailCheck")
      end
    end,
  })
end

return M
