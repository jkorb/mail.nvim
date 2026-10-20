local M = {}
local headers = require("mail.headers")
local namespace = vim.api.nvim_create_namespace("mail_images")
local active
local extensions = {
  png = true, jpg = true, jpeg = true, gif = true, webp = true, svg = true,
  bmp = true, tif = true, tiff = true, avif = true, ico = true, heic = true, heif = true,
}

local function notify(message)
  vim.notify("mail.nvim: " .. message, vim.log.levels.WARN)
end

local function body_position(buf, row)
  if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].filetype ~= "mail" then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local _, separator = headers.parse(lines)
  -- The final empty line may still be the separator in a new draft.
  return separator and (row > separator or row == separator and row == #lines), row == separator
end

local function window_options()
  local width = math.max(1, math.min(math.floor(vim.o.columns * 0.85), vim.o.columns - 4))
  local height = math.max(1, math.min(math.floor(vim.o.lines * 0.75), vim.o.lines - 4))
  return {
    relative = "editor", style = "minimal", border = "rounded",
    width = width, height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    title = " Mail image ", title_pos = "center",
    footer = " Enter: pick · Space: select · Ctrl-C: cancel ", footer_pos = "center",
  }
end

function M.open(directory)
  if active then
    if active.win and vim.api.nvim_win_is_valid(active.win) then
      vim.api.nvim_set_current_win(active.win)
      vim.cmd.startinsert()
    end
    return
  end
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  if not body_position(buf, cursor[1]) or not vim.bo[buf].modifiable then
    notify("Place the cursor in an editable mail body first.")
    return
  end
  local executable = require("mail").config.image_picker
  if vim.fn.executable(executable) ~= 1 then
    notify("Image picker not found: " .. executable .. ". Install nnn or set image_picker.")
    return
  end
  directory = directory and directory ~= "" and directory or vim.fn.getcwd()
  directory = vim.fn.fnamemodify(vim.fs.normalize(directory), ":p")
  if vim.fn.isdirectory(directory) ~= 1 then
    notify("Not a directory: " .. directory)
    return
  end
  local state = {
    selection = vim.fn.tempname(),
    mark = vim.api.nvim_buf_set_extmark(buf, namespace, cursor[1] - 1, cursor[2], { right_gravity = false }),
    group = vim.api.nvim_create_augroup("mail_image_picker", { clear = true }),
  }
  active = state

  local function release()
    state.done = true
    if active == state then active = nil end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_del_extmark, buf, namespace, state.mark)
    end
    vim.api.nvim_del_augroup_by_id(state.group)
    vim.fn.delete(state.selection)
  end
  local function close_window()
    state.closing = true
    local focused = vim.api.nvim_get_current_win() == state.win
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
    end
    if state.terminal and vim.api.nvim_buf_is_valid(state.terminal) then
      vim.api.nvim_buf_delete(state.terminal, { force = true })
    end
    if focused and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_set_current_win(win)
    end
    if focused then vim.cmd.stopinsert() end
  end
  local function cancel()
    if state.done then return end
    if state.job then pcall(vim.fn.jobstop, state.job) end
    close_window()
    release()
  end
  local function insert(links)
    if state.done then return end
    if not vim.api.nvim_buf_is_loaded(buf) or not vim.bo[buf].modifiable then
      release()
      return
    end
    local position = vim.api.nvim_buf_get_extmark_by_id(buf, namespace, state.mark, {})
    local in_body, separator = body_position(buf, (position[1] or -1) + 1)
    if #position == 0 or not in_body then
      notify("The image insertion point is no longer in the mail body.")
      release()
      return
    end
    if separator then table.insert(links, 1, "") end
    vim.api.nvim_buf_set_text(buf, position[1], position[2], position[1], position[2], links)
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      local col = #links[#links] + (#links == 1 and position[2] or 0)
      vim.api.nvim_win_set_cursor(win, { position[1] + #links, col })
    end
    release()
  end
  local function describe(paths, index, links)
    if state.done then return end
    if not paths[index] then return insert(links) end
    local path = paths[index]
    vim.ui.input({ prompt = "Image description: ", default = vim.fn.fnamemodify(path, ":t:r"):gsub("[%c]", " ") }, function(description)
      if state.done then return end
      if description == nil then return release() end
      -- Treat the description as literal text, including Markdown punctuation.
      description = description:gsub("[%c]", " "):gsub("([%p])", "\\%1")
      -- An absolute path works in Pandoc and MarkdownPreview's image server.
      links[#links + 1] = "![" .. description .. "](<" .. vim.uri_encode(path) .. ">)"
      vim.schedule(function() describe(paths, index + 1, links) end)
    end)
  end
  local function finished(code)
    -- A cancelled job can exit after cleanup; remove any late selection file.
    if state.done then
      vim.fn.delete(state.selection)
      return
    end
    local file = io.open(state.selection, "rb")
    local selected = file and file:read("*a") or ""
    if file then file:close() end
    close_window()
    vim.fn.delete(state.selection)
    if code ~= 0 then
      notify("Image picker exited with status " .. code .. ".")
      release()
      return
    end
    local paths, seen = {}, {}
    for path in selected:gmatch("[^%z]+") do
      local extension = path:match("%.([^./]+)$")
      if not extension or not extensions[extension:lower()] or vim.fn.filereadable(path) ~= 1 then
        notify("Not a readable image: " .. path)
        release()
        return
      end
      if not seen[path] then
        paths[#paths + 1], seen[path] = path, true
      end
    end
    if #paths == 0 then return release() end
    vim.schedule(function() describe(paths, 1, {}) end)
  end

  state.terminal = vim.api.nvim_create_buf(false, true)
  local ok, result = pcall(vim.api.nvim_open_win, state.terminal, true, window_options())
  if not ok then
    cancel()
    notify("Could not open image picker: " .. tostring(result))
    return
  end
  state.win = result
  vim.bo[state.terminal].bufhidden = "wipe"
  vim.keymap.set({ "t", "n" }, "<C-c>", cancel, { buffer = state.terminal, desc = "Cancel image picker" })
  vim.keymap.set("n", "<Esc>", cancel, { buffer = state.terminal, desc = "Cancel image picker" })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = state.group, pattern = tostring(state.win),
    callback = function() if not state.closing then vim.schedule(cancel) end end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = state.group, buffer = buf, callback = function() vim.schedule(cancel) end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = state.group,
    callback = function()
      if vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_set_config(state.win, window_options())
      end
    end,
  })
  ok, result = pcall(vim.fn.jobstart, { executable, "-0", "-J", "-Q", "-p", state.selection, directory }, {
    term = true,
    -- Keep nnn's cd-on-quit helper from changing the shell's saved directory.
    env = { NNN_TMPFILE = "/dev/null" },
    on_exit = function(_, code) vim.schedule(function() finished(code) end) end,
  })
  if not ok or result <= 0 then
    cancel()
    notify("Could not start image picker: " .. tostring(result))
    return
  end
  state.job = result
  vim.cmd.startinsert()
  return state.job
end

function M.attach(buf)
  vim.api.nvim_buf_create_user_command(buf, "MailImage", function(args)
    if #args.fargs > 1 then
      notify("Use :MailImage [directory]; escape spaces in the directory name.")
      return
    end
    M.open(args.fargs[1])
  end, { nargs = "*", complete = "dir", desc = "Pick an inline image with nnn" })
  vim.api.nvim_buf_call(buf, function()
    local previous = vim.b[buf].mail_image_key
    if previous and vim.fn.maparg(previous, "n", false, true).callback == M.open then
      vim.keymap.del("n", previous, { buffer = buf })
    end
    vim.b[buf].mail_image_key = nil
    local key = require("mail").config.image_keymap
    if key and vim.fn.maparg(key, "n") == "" then
      vim.keymap.set("n", key, M.open, { buffer = buf, desc = "Insert mail image" })
      vim.b[buf].mail_image_key = vim.fn.maparg(key, "n", false, true).lhs
    end
  end)
end

return M
