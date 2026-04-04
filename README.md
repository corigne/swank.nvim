# swank.nvim

[![Coverage](https://img.shields.io/badge/coverage-43%25-orange?style=flat-square&logo=lua)](luacov.report.out)

A modern, pure-Lua Common Lisp development environment for Neovim, built on the [Swank](https://github.com/slime/slime/blob/master/swank-backend.lisp) protocol.

> **Status: Early development.** Not ready for daily use yet.

---

## Why another CL plugin?

| Plugin | Status | Notes |
|---|---|---|
| vlime | Active | Vimscript, clunky UI |
| nvlime | **Archived** | Maintainer quit Lisp |
| conjure | Active | Multi-lang, eval-only for CL |

swank.nvim is a ground-up Lua rewrite targeting full SLIME feature parity, built with modern Neovim APIs throughout.

## Goals

- Pure Lua — no Vimscript, no Python, no Fennel
- Neovim 0.10+ only
- `vim.uv` async TCP transport — no blocking
- `vim.ui.input` / `vim.ui.select` everywhere → snacks.nvim works automatically
- `vim.diagnostic` for compiler notes
- blink.cmp as a first-class completion source
- Self-contained — no helper plugin dependency

## Features (planned)

- [ ] REPL with floating output buffer
- [ ] Eval: top-level form, region, interactive
- [ ] Completion via blink.cmp (swank:fuzzy-completions)
- [ ] Arglist autodoc in virtual text
- [ ] SLDB debugger with `vim.ui.select` restarts
- [ ] Object inspector
- [ ] Cross-reference (xref) → quickfix/picker
- [ ] Compiler notes as `vim.diagnostic`
- [ ] Trace dialog
- [ ] which-key integration

## Installation

Not yet published. Watch this repo.

## License

MIT
