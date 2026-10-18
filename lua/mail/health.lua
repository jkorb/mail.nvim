local M = {}

function M.check()
  vim.health.start("mail.nvim")
  local config = require("mail").config
  if config.treesitter then
    local ok, parser = pcall(vim.treesitter.language.add, "mail")
    if ok and parser then
      local queries_ok, err = pcall(function()
        assert(vim.treesitter.query.get("mail", "highlights"), "Missing highlights")
        assert(vim.treesitter.query.get("mail", "injections"), "Missing injections")
      end)
      if queries_ok then
        vim.health.ok("Mail parser and queries loaded")
      else
        vim.health.error("Mail queries do not match the loaded parser: " .. tostring(err), {
          "Rebuild the mail parser or run :TSInstall! mail, then restart Neovim.",
          ":TSInstall mail skips an already installed parser.",
        })
      end
    else
      vim.health.warn("Mail parser missing; configure parser.url or parser.path, then :TSInstall mail")
    end
  else
    vim.health.info("Tree-sitter disabled")
  end
  if config.cmp_contacts and config.contacts_eval then
    local ok = pcall(require, "cmp")
    if ok then
      vim.health.ok("Contact source available; enable cmp-contacts in your completion sources")
    else
      vim.health.warn("Contact completion needs nvim-cmp or blink.compat")
    end
  else
    vim.health.info("Contact completion disabled or contacts_eval unset")
  end
end

return M
