local M = {}
local config = {}
local highlighters = setmetatable({}, { __mode = "v" })

local function visible_fences()
  local ok, loaded = pcall(vim.treesitter.language.add, "markdown")
  if not ok or not loaded then return {} end
  local parts = {}
  for _, path in ipairs(vim.treesitter.query.get_files("markdown", "highlights")) do
    parts[#parts + 1] = table.concat(vim.fn.readfile(path), "\n")
  end
  if #parts == 0 then return {} end
  -- Keep the installed Markdown highlights, but leave block syntax visible in
  -- this highlighter. In particular, conceal_lines makes fence lines disappear
  -- while composing. Renaming only the metadata keys also handles capture-local
  -- directives without having to parse their quoted values.
  local function visible(prefix, key, space)
    if key == "conceal" or key == "conceal_lines" then key = "mail_" .. key end
    return prefix .. key .. space
  end
  local source = table.concat(parts, "\n")
    :gsub("(%(#set!%s+)([%w_]+)(%s)", visible)
    :gsub("(%(#set!%s+@[%w_.%-]+%s+)([%w_]+)(%s)", visible)
  return { markdown = source }
end

function M.register()
  if not config.treesitter or not config.parser then
    return false
  end
  local ok, parsers = pcall(require, "nvim-treesitter.parsers")
  if not ok then
    return false
  end
  local install = vim.deepcopy(config.parser)
  if install.path then
    install.path = vim.fn.expand(install.path)
  end
  if type(parsers.get_parser_configs) == "function" then
    -- nvim-treesitter's legacy master branch.
    install.url = install.path or install.url
    install.path = nil
    install.files = { "src/parser.c", "src/scanner.c" }
    parsers.get_parser_configs().mail = { install_info = install, filetype = "mail" }
  else
    parsers.mail = { install_info = install }
  end
  return true
end

function M.setup(options)
  config = options
  local group = vim.api.nvim_create_augroup("mail_treesitter", { clear = true })
  vim.treesitter.language.register("mail", "mail")
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "TSUpdate",
    callback = function() M.register() end,
  })
  M.register()
end

function M.start(buf)
  if not config.treesitter then
    if vim.b[buf].mail_treesitter then
      vim.treesitter.stop(buf)
      vim.b[buf].mail_treesitter = nil
    end
    return false
  end
  if vim.treesitter.highlighter.active[buf] and vim.treesitter.highlighter.active[buf] == highlighters[buf] then
    return true
  end
  local ok, err = pcall(function()
    local parser = assert(vim.treesitter.get_parser(buf, "mail"))
    local queries = visible_fences()
    -- LazyVim may already have started the default highlighter on FileType.
    -- Replace it once so its injected Markdown query cannot hide fence lines.
    vim.treesitter.stop(buf)
    highlighters[buf] = vim.treesitter.highlighter.new(parser, { queries = queries })
  end)
  if ok then
    vim.b[buf].mail_treesitter = true
  else
    vim.notify_once("mail.nvim: " .. tostring(err)
      .. "\nRun :checkhealth mail. Use :TSInstall mail for a missing parser,"
      .. " or :TSInstall! mail to rebuild an outdated one, then restart Neovim.", vim.log.levels.WARN)
  end
  return ok
end

return M
