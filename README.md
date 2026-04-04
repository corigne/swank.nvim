# swank.nvim

[![Coverage](https://img.shields.io/badge/coverage-30%25-red?style=flat-square&logo=lua)](luacov.report.out)

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

## Features

- [x] REPL with floating output buffer
- [x] Eval: top-level form, region, interactive
- [x] Completion via blink.cmp (`swank:fuzzy-completions`)
- [x] Arglist autodoc (`CursorHoldI` → echo area)
- [x] SLDB debugger — floating window, restart/frame/eval-in-frame
- [x] Object inspector — navigable parts, back/reinspect
- [x] Cross-reference (xref) → quickfix / direct jump
- [x] Compiler notes → `vim.diagnostic`
- [x] Trace dialog (SWANK-TRACE-DIALOG)
- [x] which-key integration
- [x] Autostart: spawn sbcl + Quicklisp on `:SwankAttach`

## Installation

**lazy.nvim:**

```lua
{
  "corigne/swank.nvim",
  ft = { "lisp", "commonlisp" },
  opts = {
    -- leader prefix for all keybindings (default: ",")
    leader = ",",
    server = {
      host = "127.0.0.1",
      port = 4005,
    },
    autostart = {
      enabled = true,   -- spawn sbcl automatically on attach
      lisp = "sbcl",    -- path to the Lisp binary
    },
  },
}
```

**Requires:** Neovim 0.10+, [plenary.nvim](https://github.com/nvim-lua/plenary.nvim), SBCL + Quicklisp (for autostart)

## Default keybindings

All bindings are buffer-local and prefixed with the configured `leader` (default `,`).

| Key | Action |
|-----|--------|
| `,cc` | Connect to Swank server |
| `,rr` | Start sbcl and connect |
| `,cd` | Disconnect |
| `,cp` | Set current package |
| `,ee` | Eval top-level form |
| `,ei` | Eval (prompt) |
| `,rw` | Toggle REPL window |
| `,id` | Describe symbol at cursor |
| `,ia` | Apropos (prompt) |
| `,iA` | Apropos symbol at cursor |
| `,ii` | Inspect value at cursor |
| `,xd` | Find definition |
| `,xc` | Who calls symbol |
| `,xr` | Who references symbol |
| `,fl` | Load file |
| `,fc` | Compile file |
| `,fs` | Compile form at cursor |
| `,tt` | Open trace dialog |
| `,td` | Toggle trace on symbol |
| `,tD` | Untrace all |

Visual mode: `,ee` eval region, `,id` describe selection, `,ia` apropos selection.

## Documentation

See `:help swank.nvim` after installation.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — includes coverage requirements (80% floor, 100% goal) and test instructions.

## License

MIT
