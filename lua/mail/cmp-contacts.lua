local source = {}
local headers = require("mail.headers")

function source.new(config)
  return setmetatable({ config = config or {} }, { __index = source })
end

function source:get_keyword_pattern()
  -- Keep names with spaces together, but never consume a recipient separator.
  return [[[^[:space:],;:<>"][^,;:<>"]*]]
end

function source:get_trigger_characters()
  return { ":", ",", " " }
end

function source:is_available()
  if not self.config.contacts_eval then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  return headers.address_field(vim.api.nvim_get_current_buf(), cursor[1], cursor[2]) ~= nil
end

function source:get_debug_name()
  return "cmp-contacts"
end

function source:get_position_encoding_kind()
  return "utf-8"
end

-- Find the current recipient without splitting quoted names, comments or <...>.
local function recipient(context, field)
  local row, col = context.cursor.row, #context.cursor_before_line
  local lines = vim.api.nvim_buf_get_lines(context.bufnr, field.row - 1, row, false)
  lines[#lines] = context.cursor_before_line
  local start_row, start_col = field.row, #field.name + 1
  local quoted, escaped, angle, comment = false, false, false, 0
  local address_row, address_col, address_end
  local function delimiter(char, at_row, at_col)
    if escaped then
      escaped = false
    elseif char == "\\" and (quoted or comment > 0) then
      escaped = true
    elseif char == '"' and comment == 0 then
      quoted = not quoted
    elseif not quoted then
      if char == "(" then
        comment = comment + 1
      elseif char == ")" then
        comment = math.max(0, comment - 1)
      elseif comment == 0 then
        if char == "<" then
          angle = true
          address_row, address_col, address_end = at_row, at_col, nil
        elseif char == ">" then
          angle = false
          address_end = at_col and at_col - 1
        elseif not angle and (char == "," or char == ";" or char == ":") then
          address_row, address_col, address_end = nil, nil, nil
          return true
        end
      end
    end
    return false
  end
  for index, line in ipairs(lines) do
    local first = index == 1 and #field.name + 2 or 1
    for i = first, #line do
      if delimiter(line:sub(i, i), field.row + index - 1, i) then
        start_row, start_col = field.row + index - 1, i
      end
    end
  end
  local parts = {}
  for r = start_row, row do
    local line = lines[r - field.row + 1]
    local first = r == start_row and start_col or 0
    local value = line:sub(first + 1)
    if #parts == 0 then
      local whitespace = value:match("^[ \t]*")
      start_row, start_col = r, first + #whitespace
      value = value:sub(#whitespace + 1)
    end
    if value ~= "" then
      parts[#parts + 1] = value
    end
  end
  -- nvim-cmp accepts only single-line completion edits. Do not damage a
  -- recipient whose name itself spans lines; folded recipient lists work.
  if start_row ~= row then
    return nil
  end
  local input = vim.trim(table.concat(parts, " "))
  local filter_prefix
  if address_row == row then
    input = vim.trim(context.cursor_before_line:sub(address_col + 1, address_end))
    filter_prefix = context.cursor_before_line:sub(start_col + 1, address_col)
  elseif input:sub(1, 1) == '"' then
    input = input:gsub('^"', ""):gsub('"$', ""):gsub("\\(.)", "%1")
  end
  if not filter_prefix and input:find("@", 1, true) then
    filter_prefix = ""
  end
  local line = context.cursor_line
  local last = #line
  for i = col + 1, #line do
    if delimiter(line:sub(i, i)) then
      last = i - 1
      break
    end
  end
  -- Preserve whitespace before the next comma when completing mid-recipient.
  while last > col and line:sub(last, last):match("[ \t]") do
    last = last - 1
  end
  return input, {
    start = { line = start_row - 1, character = start_col },
    ["end"] = { line = row - 1, character = last },
  }, filter_prefix
end

local function command_for(template, input)
  if type(template) == "string" then
    return (template:gsub("{input}", function() return vim.fn.shellescape(input) end))
  end
  if type(template) == "table" and vim.islist(template) and #template > 0 then
    local command = {}
    for i, arg in ipairs(template) do
      if type(arg) ~= "string" then
        return nil
      end
      command[i] = arg:gsub("{input}", function() return input end)
    end
    return command
  end
end

local function decode_items(output, range, filter_prefix)
  local ok, contacts = pcall(vim.json.decode, output)
  if not ok or type(contacts) ~= "table" or not vim.islist(contacts) then
    return nil
  end
  local items, seen = {}, {}
  for _, contact in ipairs(contacts) do
    if type(contact) == "table" then
      for name, address in pairs(contact) do
        if type(name) == "string" and type(address) == "string" and address ~= ""
          and not name:find("[%c]") and not address:find("[%c]") then
          local label = address
          if name ~= "" then
            label = '"' .. name:gsub('[\\"]', '\\%0') .. '" <' .. address .. '>'
          end
          if not seen[label] then
            seen[label] = true
            items[#items + 1] = {
              label = label,
              filterText = filter_prefix and (filter_prefix .. address .. " " .. name) or label,
              sortText = label:lower(),
              insertText = label,
              textEdit = { newText = label, range = vim.deepcopy(range) },
              kind = vim.lsp.protocol.CompletionItemKind.Text,
            }
          end
        end
      end
    end
  end
  table.sort(items, function(a, b) return a.label < b.label end)
  return items
end

function source:cancel()
  local request = self.request
  if request then
    request.finish({}, true)
    if request.job and request.job > 0 then
      pcall(vim.fn.jobstop, request.job)
    end
  end
end

function source:complete(params, callback)
  self:cancel()
  local context = params.context
  local field = headers.address_field(context.bufnr, context.cursor.row, #context.cursor_before_line)
  if not self.config.contacts_eval or not field then
    callback({ items = {}, isIncomplete = false })
    return
  end
  local input, range, filter_prefix = recipient(context, field)
  if not input then
    callback({ items = {}, isIncomplete = false })
    return
  end
  local command = command_for(self.config.contacts_eval, input)
  if not command or command == "" then
    callback({ items = {}, isIncomplete = false })
    return
  end
  local tick = vim.api.nvim_buf_get_changedtick(context.bufnr)
  local request = { output = "" }
  self.request = request
  request.finish = function(items, incomplete)
    if request.done then
      return
    end
    request.done = true
    if request.timer and not request.timer:is_closing() then
      request.timer:stop()
      request.timer:close()
    end
    if self.request == request then
      self.request = nil
    end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(context.bufnr)
        or vim.api.nvim_buf_get_changedtick(context.bufnr) ~= tick then
        items, incomplete = {}, true
      end
      callback({ items = items, isIncomplete = incomplete })
    end)
  end
  local ok, job = pcall(vim.fn.jobstart, command, {
    stdout_buffered = true,
    on_stdout = function(_, data) request.output = table.concat(data or {}, "\n") end,
    on_exit = function(_, code)
      vim.schedule(function()
        local items = code == 0 and decode_items(request.output, range, filter_prefix) or nil
        -- Queries may be filtered by the command, so ask again as input changes.
        request.finish(items or {}, true)
      end)
    end,
  })
  if not ok or job <= 0 then
    request.finish({}, true)
    return
  end
  request.job = job
  request.timer = vim.defer_fn(function()
    request.finish({}, true)
    pcall(vim.fn.jobstop, job)
  end, self.config.contacts_timeout or 3000)
end

return source
