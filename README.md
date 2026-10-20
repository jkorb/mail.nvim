# ✉️ mail.nvim

A small Neovim plugin for editing plain-text email.

- 🧭 Start new messages at `To:` and replies at the body; keep your place when returning.
- 🎨 Colored quote bars, links, and aligned Markdown tables. Toggle the view with `:MailViewToggle` or `<localleader>mv`; disable by default with `view = false`.
- 📇 Complete contacts with `@name` and phrases with `!best`, `!groetjes`, or `!sounds`, using nvim-cmp or blink.compat. Customize `phrases` for your own sign-offs.
- 🖼️ Pick inline images with `:MailImage` or `<localleader>mi`; requires `nnn` and a Markdown-to-HTML mail workflow.
- 🧵 Older nested replies fold away; the reply you're answering stays open. Check drafts with `:MailCheck`, or when quitting with `:q` / `:wq`.

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
