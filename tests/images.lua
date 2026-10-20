vim.opt.runtimepath = { vim.fn.getcwd(), vim.env.VIMRUNTIME }
vim.opt.packpath = {}
vim.o.swapfile = false
vim.o.hidden = true
vim.o.virtualedit = "onemore"
local checks = 0
local function eq(actual, expected, message)
  checks = checks + 1
  assert(vim.deep_equal(actual, expected), message .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual))
end
local function drain() vim.wait(10, function() return false end, 1) end
local root = vim.fn.getcwd() .. "/tmp/image-tests"
vim.fn.mkdir(root, "p")
local path = root .. "/résumé (draft) #50% [x].png"
local second = root .. "/second.png"
local function write(file, contents)
  local stream = assert(io.open(file, "wb"))
  stream:write(contents)
  stream:close()
end
local png = vim.base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aCgAAAABJRU5ErkJggg==")
write(path, png)
write(second, png)
write(root .. "/not-image.txt", "text")
local expected_path = root .. "/r%c3%a9sum%c3%a9%20(draft)%20%2350%25%20%5bx%5d.png"
local mail, images = require("mail"), require("mail.images")
local notices, prompts, request, started, stopped = {}, {}, nil, 0, 0
vim.notify = function(message) notices[#notices + 1] = message end
local original_start, original_stop = vim.fn.jobstart, vim.fn.jobstop
local function mock_jobs()
  vim.fn.jobstart = function(command, opts)
    started = started + 1
    request = { command = command, opts = opts, win = vim.api.nvim_get_current_win(), buf = vim.api.nvim_get_current_buf() }
    return 999
  end
  vim.fn.jobstop = function() stopped = stopped + 1 end
end
mock_jobs()
local answer = "Description [one] *two*"
vim.ui.input = function(opts, callback)
  prompts[#prompts + 1] = opts
  callback(answer)
end
local function setup(opts)
  mail.setup(vim.tbl_extend("force", { treesitter = false, cmp_contacts = false, image_picker = vim.v.progpath }, opts or {}))
  drain()
end
setup()
local function draft(lines, row, col)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "To: ", "Subject: Test", "", "Before  after" })
  vim.bo[buf].filetype = "mail"
  drain()
  vim.api.nvim_win_set_cursor(0, { row or 4, col or 7 })
  return buf
end
local function finish(paths, code)
  if paths then write(request.command[6], table.concat(paths, "\0") .. "\0") end
  request.opts.on_exit(999, code or 0)
  drain()
  eq(vim.fn.filereadable(request.command[6]), 0, "selection file was not cleaned up")
  eq(vim.api.nvim_win_is_valid(request.win), false, "picker window was not closed")
  eq(vim.api.nvim_buf_is_valid(request.buf), false, "terminal buffer leaked")
end
local function text(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
local buf = draft()
eq(vim.api.nvim_buf_get_commands(buf, {}).MailImage ~= nil, true, "mail command missing")
eq(vim.fn.maparg("<localleader>mi", "n", false, true).callback, images.open, "mail shortcut missing")
local before = text(buf)
local origin = vim.api.nvim_get_current_win()
vim.cmd({ cmd = "MailImage", args = { root } })
eq(request.command[2], "-0", "picker must use NUL-separated paths")
eq(request.opts.term, true, "picker is not a terminal")
eq(request.command[7], root .. "/", "picker start directory lost")
eq(vim.api.nvim_win_get_config(request.win).relative, "editor", "picker is not floating")
vim.api.nvim_exec_autocmds("VimResized", {})
eq(vim.api.nvim_win_is_valid(request.win), true, "resizing closed the picker")
local count = started
images.open()
eq(started, count, "second invocation launched a second picker")
finish({ path })
local link = "![Description \\[one\\] \\*two\\*](<" .. expected_path .. ">)"
eq(text(buf), { "To: ", "Subject: Test", "", "Before " .. link .. " after" }, "image insertion damaged text or escaping")
eq(vim.api.nvim_get_current_win(), origin, "picker did not restore the draft window")
eq(prompts[1].default, "résumé (draft) #50% [x]", "description default lost filename")
vim.cmd.undo()
eq(text(buf), before, "undo removed more than the image insertion")
vim.cmd.redo()
-- Keep the generated Markdown for a check against the user's HTML renderer.
write(root .. "/inserted.md", link)

local spaced_dir = root .. "/with spaces (test)"
vim.fn.mkdir(spaced_dir, "p")
vim.cmd("MailImage " .. vim.fn.fnameescape(spaced_dir))
eq(request.command[7], spaced_dir .. "/", "escaped start directory was not unescaped")
finish(nil)

-- Filenames containing newlines must remain one selection and one Markdown line.
local newline_path = root .. "/line\nbreak.png"
write(newline_path, png)
buf = draft({ "To: ", "", "" }, 3, 0)
images.open(root)
answer = "A\nB"
finish({ newline_path })
eq(text(buf)[3], "![A B](<" .. root .. "/line%0abreak.png>)", "newline in filename split the selection")

buf = draft({ "To: ", "Subject: Test", "" }, 3, 0)
images.open(root)
answer = ""
finish({ path })
eq(text(buf), { "To: ", "Subject: Test", "", "![](<" .. expected_path .. ">)" }, "empty draft lost its header separator")

buf = draft()
before = text(buf)
images.open(root)
finish(nil)
eq(text(buf), before, "quitting without a selection changed the draft")
images.open(root)
answer = nil
finish({ path })
eq(text(buf), before, "cancelling description changed the draft")
images.open(root)
finish({ path }, 1)
eq(text(buf), before, "failed picker changed the draft")
eq(notices[#notices]:match("status 1") ~= nil, true, "picker error was not reported")
for _, invalid in ipairs({ root .. "/missing.png", root .. "/not-image.txt", root }) do
  images.open(root)
  finish({ invalid })
  eq(text(buf), before, "invalid selection changed the draft")
end

images.open(root)
vim.api.nvim_win_close(request.win, true)
drain()
eq(stopped > 0, true, "closing popup did not stop the picker")
finish({ path }) -- late process output must never insert after cancellation
eq(text(buf), before, "closed picker inserted a late selection")
images.open(root)
local cancel = vim.fn.maparg("<C-c>", "t", false, true).callback
eq(type(cancel), "function", "terminal cancel shortcut is missing")
cancel()
finish({ path })
eq(text(buf), before, "Ctrl-C inserted a late selection")

local inputs = 0
vim.ui.input = function(_, callback)
  inputs = inputs + 1
  callback(inputs == 1 and "First" or nil)
end
images.open(root)
finish({ path, second })
eq(text(buf), before, "cancelling a later description left a partial insertion")
vim.ui.input = function(_, callback) callback(answer) end

images.open(root)
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "X-Test: added while picking" })
answer = "A"
finish({ path, second, path })
eq(text(buf)[5], "Before ![A](<" .. expected_path .. ">)", "insertion point did not track edits")
eq(text(buf)[6], "![A](<" .. second .. ">) after", "multiple selection/duplicate handling failed")

buf = draft()
before = text(buf)
local pending
vim.ui.input = function(_, callback) pending = callback end
images.open(root)
finish({ path })
vim.api.nvim_buf_delete(buf, { force = true })
drain()
pending("too late")
drain()
buf = draft()
images.open(root)
finish(nil)
eq(text(buf), before, "wiping draft left the picker stuck")

count = started
vim.api.nvim_win_set_cursor(0, { 1, 4 })
images.open(root)
eq(started, count, "picker launched in headers")
vim.api.nvim_win_set_cursor(0, { 4, 7 })
vim.bo[buf].modifiable = false
images.open(root)
eq(started, count, "picker launched in nonmodifiable buffer")
vim.bo[buf].modifiable = true
images.open(root .. "/missing")
eq(started, count, "picker launched in missing directory")
setup({ image_picker = "mail-nvim-missing-picker" })
images.open(root)
eq(started, count, "missing executable was launched")
setup({ image_keymap = false })
eq(vim.fn.maparg("<localleader>mi", "n"), "", "disabling keymap left the old mapping")
local custom = function() end
vim.keymap.set("n", "<localleader>mi", custom, { buffer = buf })
setup()
eq(vim.fn.maparg("<localleader>mi", "n", false, true).callback, custom, "user mapping was overwritten")

local windows = #vim.api.nvim_list_wins()
vim.fn.jobstart = function() return -1 end
images.open(root)
eq(#vim.api.nvim_list_wins(), windows, "failed process start leaked the popup")
eq(notices[#notices]:find("Could not start", 1, true) ~= nil, true, "failed start was not reported")
mock_jobs()
images.open(root)
finish(nil)

-- Exercise the real nnn picker over a PTY when explicitly requested.
if vim.env.MAIL_NVIM_NNN then
  vim.fn.jobstart, vim.fn.jobstop = original_start, original_stop
  vim.ui.input = function(_, callback) callback("Picked with nnn") end
  setup({ image_picker = vim.env.MAIL_NVIM_NNN })
  local single = root .. "/single"
  vim.fn.mkdir(single, "p")
  write(single .. "/image.png", png)
  buf = draft({ "To: ", "", "" }, 3, 0)
  local job = images.open(single)
  eq(type(job), "number", "real nnn did not start")
  local terminal = vim.api.nvim_get_current_buf()
  eq(vim.wait(2000, function()
    return table.concat(vim.api.nvim_buf_get_lines(terminal, 0, -1, false), "\n"):find("image.png", 1, true) ~= nil
  end, 10), true, "nnn did not display the image")
  vim.fn.chansend(job, "\r")
  eq(vim.wait(2000, function() return not vim.api.nvim_buf_is_valid(terminal) end, 10), true, "nnn did not finish selection")
  eq(text(buf)[3], "![Picked with nnn](<" .. single .. "/image.png>)", "real nnn selection was not inserted")
  local saved = text(buf)
  job = images.open(single)
  terminal = vim.api.nvim_get_current_buf()
  eq(vim.wait(2000, function()
    return table.concat(vim.api.nvim_buf_get_lines(terminal, 0, -1, false), "\n"):find("image.png", 1, true) ~= nil
  end, 10), true, "second nnn did not start")
  vim.fn.chansend(job, "q")
  eq(vim.wait(2000, function() return not vim.api.nvim_buf_is_valid(terminal) end, 10), true, "nnn did not quit")
  eq(text(buf), saved, "quitting real nnn changed the draft")
end
print(("%d image picker checks passed"):format(checks))
