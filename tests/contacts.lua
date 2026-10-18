local mode, input = arg[1], arg[2]
if mode == "invalid" then
  io.write("not json")
elseif mode == "empty" then
  io.write("")
elseif mode == "object" then
  io.write('{"Alice":"alice@example.org"}')
elseif mode == "failure" then
  io.write('[{"Alice":"alice@example.org"}]')
  os.exit(2)
elseif mode == "slow" then
  vim.wait(500)
  io.write('[{"Late":"late@example.org"}]')
elseif mode == "echo" then
  io.write(vim.json.encode({ { [input] = "echo@example.org" } }))
else
  io.write(vim.json.encode({
    { Alice = "alice@example.org" },
    { [""] = "bare@example.org" },
    { ['A "quoted" \\ name'] = "quoted@example.org" },
    { Alice = "alice@example.org" },
    { Invalid = 42 },
    { ["New\nline"] = "bad@example.org" },
    { Bad = "bad\r\nBcc: other@example.org" },
    vim.NIL,
  }))
end
