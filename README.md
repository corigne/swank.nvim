# swank.nvim

[![CI](https://github.com/corigne/swank.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/corigne/swank.nvim/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/coverage-93%25-green?style=flat-square&logo=lua)](https://github.com/corigne/swank.nvim/actions/workflows/ci.yml)

A modern, pure-Lua Common Lisp development environment for Neovim, built on the [Swank](https://github.com/slime/slime/blob/master/swank/backend.lisp) protocol.

> **Status: Early development.** Not ready for daily use yet.

---

## Why another CL plugin?

| Plugin | Status | Notes |
|---|---|---|
| vlime | Active | clunky/limited by the nature of Vim and Vimscript |
| nvlime | **Archived** | Maintainer quit Lisp, sometimes works, but has existing bugs |
| conjure | Active | Multi-lang, but eval-only capability for CL |
| sextant.nvim | Inactive/Broken | LSP server incomplete, functionality cannot be verified |
 
This project is a ground-up rewrite targeting full SLIME feature parity using modern Neovim APIs, 
leveraging testing and GitHub CI. It is designed to be a drop-in replacement for vlime/nvlime.

## Goals

### 1.0 Release Candidate
- [x] Pure Lua; no Vimscript, Python or Fennel
- [x] Neovim 0.10+ only
- [x] `vim.uv` async TCP transport -> non-blocking
- [x] `vim.ui.input` / `vim.ui.select` everywhere -> snacks.nvim and other plugin api hooks just work
- [x] `vim.diagnostic` -> for compiler notes
- [x] blink.cmp as a first-class completion source
- [x] Self-contained; no helper plugin dependency
- [x] REPL with optional pane/floating output buffer
- [x] Eval: top-level form, region, interactive
- [x] Completion via `swank:completions` / `swank:fuzzy-completions` — native blink.cmp and nvim-cmp sources with lazy `describe-symbol` documentation
- [x] Arglist autodoc (`CursorHoldI` → echo area)
- [x] SLDB debugger; floating window, restart/frame/eval-in-frame
- [x] Object inspector; navigable parts, back/reinspect
- [x] Cross-reference (xref) -> by hooked picker or quickfix list / direct jump for single result
- [x] Trace dialog (SWANK-TRACE-DIALOG)
- [x] which-key integration
- [x] Autostart: spawn a CL implementation + Quicklisp when `require("swank").attach()` is called
- [ ] Compiler notes -> `vim.diagnostic`

### Stretch goals

- [] Optional first-class LSP support (NOTE: LSP would not be a replacement for SWANK, but could provide enhancements)
- [] Integration with popularly used CL libraries (e.g. CIDER's nREPL middleware, SLIME contribs) for enhanced features
- [] Integration with popular Neovim plugins (e.g. Telescope, Trouble, etc.) for enhanced UI/UX
- [] Full support for more CL implementations where possible (e.g. CCL, ECL, ABCL, CLISP, Allegro CL)
- [] Additional REPL features (e.g. input history, customizable prompt, etc.)
- [] Better support for remote Swank servers (e.g. via SSH tunnels, Docker containers, etc.)

## Prerequisites

### Neovim

**Neovim 0.10+** required. 0.13+ recommended (used for development and testing).

### Quick start (autostart; recommended)

The default configuration automatically launches your CL implementation and
connects to Swank when you open a `.lisp` file. **You don't need to write any
startup scripts or start a server manually.**

All you need is:

1. A Common Lisp implementation installed (e.g. `sbcl`)
2. [Quicklisp](https://www.quicklisp.org/) installed in the default location (`~/quicklisp/`)

**Install SBCL:**

```sh
# Debian/Ubuntu
sudo apt install sbcl

# Arch
sudo pacman -S sbcl

# macOS
brew install sbcl
```

**Install Quicklisp** (one-time setup, any implementation):

```sh
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --load quicklisp.lisp \
     --eval '(quicklisp-quickstart:install)' \
     --eval '(ql:add-to-init-file)' \
     --quit
```

That's it. Open a `.lisp` file in Neovim and swank.nvim handles the rest.

> **No Quicklisp?** SBCL bundles Swank via ASDF. swank.nvim will automatically
> fall back to `(require :swank)` if Quicklisp is not found.

### CL implementation support

| Implementation | Support | Notes |
|----------------|---------|-------|
| [SBCL](https://www.sbcl.org/) | ✅ Primary | Recommended. Best SWANK support. |
| [CCL (Clozure CL)](https://ccl.clozure.com/) | ⚠️ Untested, should work | SWANK is well-supported |
| [ECL](https://ecl.common-lisp.dev/) | ⚠️ Untested, Likely Partial Compatibility | SWANK works; some features limited |
| [ABCL](https://abcl.org/) | ⚠️ Untested, Likely Partial Compatibility | Runs on JVM; SWANK can be quirky |
| [CLISP](https://clisp.sourceforge.io/) | ❌ Untested, Not recommended | SWANK support is minimal |

To use a different implementation, set `autostart.implementation` in your config:

```lua
require("swank").setup({
  autostart = { implementation = "ccl" },  -- or "ecl", "abcl", "/usr/local/bin/sbcl", etc.
})
```

### Advanced: connecting to an existing server

If you want to manage the SWANK server yourself (remote machines, custom setups,
`autostart.enabled = false`), start it from your CL image:

```lisp
(ql:quickload "swank" :silent t)
(swank:create-server :port 4005 :dont-close t)
```

Then connect from Neovim with `<Leader>lc`.

---

## Installation

**lazy.nvim:**

Minimal config:
```lua
{
  "corigne/swank.nvim"
},
```

Default config:
```lua
{
  "corigne/swank.nvim",
  ft = { "lisp", "commonlisp" },
  opts = {
    -- leader prefix for all swank keybindings (default: "<Leader>")
    leader = "<Leader>",
    server = {
      host = "127.0.0.1",
      port = 4005,
    },
    autostart = {
      enabled = true,              -- spawn SBCL automatically on first attach
      implementation = "sbcl",    -- path or name of the Lisp binary
    },
    ui = {
      repl = {
        -- "auto"|"right"|"left"|"top"|"bottom"|"float"
        -- "auto" tries vertical split first (if REPL would get ≥80 cols),
        -- then horizontal split, then float as a last resort
        position = "auto",
        size = 0.45,  -- fraction (0–1) or fixed columns/rows
      },
    },
  },
  -- Wire up M.attach() so keymaps and autostart fire on FileType
  config = function(_, opts)
    require("swank").setup(opts)
  end,
}
```

Then add an autocmd to attach on Lisp buffers (or put this inside your `config` function):

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "lisp", "commonlisp" },
  callback = function(args)
    require("swank").attach(args.buf)
  end,
})
```

**Requires:** Neovim 0.10+. See [Prerequisites](#prerequisites) above.

## Documentation
### wiki
See [the wiki here](/wiki) for detailed documentation, guides and troubleshooting.

### vimdocs
See `:help swank.nvim` after installation.

## Completions

swank.nvim ships native sources for blink.cmp and nvim-cmp. Both support
lazy documentation previews via `swank:describe-symbol` when you dwell on
a completion item.

See **[Completions wiki page](wiki/Completions.md)** for full setup
instructions, source module paths, and engine-specific options.

## Default keybindings

See [the wiki](wiki/Keybindings.md) for a full list of default keybindings and how to customize them.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## Acknowledgements

- [SLIME](https://github.com/slime/slime) 
- [Swank](https://github.com/slime/slime/blob/master/swank.lisp)
- [vlime](https://github.com/vlime/vlime) and [nvlime](https://github.com/monkoose/nvlime) reference implementations for Vim and Neovim, thank you for paving the way
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [blink.cmp](https://github.com/Saghen/blink.cmp)

## License

MIT
