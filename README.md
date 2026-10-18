# ✉️ mail.nvim

A small Neovim plugin for editing plain-text email.

- 🧭 Start new messages at `To:` and replies at the body; keep your place when returning.
- 🎨 Highlight headers, nested quotes, and Markdown with a custom Tree-sitter grammar.
- 📇 Complete contacts in address fields with nvim-cmp or blink.compat.

Install this repo and [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter), then call:

```lua
require("mail").setup({
  parser = { url = "https://github.com/jkorb/tree-sitter-mail" },
  contacts_eval = "fetch_contacts {input}", -- optional; use your contact lookup command
})
```

Run `:TSInstall mail markdown markdown_inline`. Add `cmp-contacts` to your completion sources; the lookup command must return JSON such as `[{"Alice":"alice@example.org"}]`.

Jump with `:MailTo`, `:MailCc`, `:MailBcc`, `:MailSubject`, and `:MailBody`. See `:help mail.nvim` for setup details and local grammar paths. Requires Neovim 0.11+; nvim-treesitter's `main` branch requires 0.12+.

AI disclosure: OpenAI Codex helped with code review, fixes, tests, and documentation.
