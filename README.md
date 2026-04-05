# swank.nvim

[![CI](https://github.com/corigne/swank.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/corigne/swank.nvim/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/coverage-82%25-green?style=flat-square&logo=lua)](luacov.report.out)

A modern, pure-Lua Common Lisp development environment for Neovim, built on the [Swank](https://github.com/slime/slime/blob/master/swank/backend.lisp) protocol.

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
- [x] Completion via `swank:completions` — native blink.cmp source (`swank.blink_source`), nvim-cmp wrapper documented
- [x] Arglist autodoc (`CursorHoldI` → echo area)
- [x] SLDB debugger — floating window, restart/frame/eval-in-frame
- [x] Object inspector — navigable parts, back/reinspect
- [x] Cross-reference (xref) → picker or quickfix / direct jump for single result
- [x] Compiler notes → `vim.diagnostic`
- [x] Trace dialog (SWANK-TRACE-DIALOG)
- [x] which-key integration
- [x] Autostart: spawn a CL implementation + Quicklisp when `require("swank").attach()` is called (typically from a `FileType` autocmd)

## Prerequisites

### Neovim

**Neovim 0.10+** required. 0.13+ recommended (used for development and testing).

### Quick start (autostart — recommended)

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
| [SBCL](https://www.sbcl.org/) | ✅ Primary | Recommended. Best Swank support. |
| [CCL (Clozure CL)](https://ccl.clozure.com/) | ✅ Should work | Swank is well-supported |
| [ECL](https://ecl.common-lisp.dev/) | ⚠️ Partial | Swank works; some features limited |
| [ABCL](https://abcl.org/) | ⚠️ Partial | Runs on JVM; Swank can be quirky |
| [CLISP](https://clisp.sourceforge.io/) | ❌ Not recommended | Swank support is minimal |
| Allegro CL | 🔲 Untested | Swank support exists in theory |

To use a different implementation, set `autostart.implementation` in your config:

```lua
require("swank").setup({
  autostart = { implementation = "ccl" },  -- or "ecl", "abcl", "/usr/local/bin/sbcl", etc.
})
```

### ASDF

ASDF is bundled with SBCL, CCL, and most modern implementations. No separate
install needed. Required for the `swank-asdf` contrib (project-aware compilation).

### Advanced: connecting to an existing server

If you want to manage the Swank server yourself (remote machines, custom setups,
`autostart.enabled = false`), start it from your CL image:

```lisp
(ql:quickload "swank" :silent t)
(swank:create-server :port 4005 :dont-close t)
```

Then connect from Neovim with `<Leader>lc`.

---

## Installation

**lazy.nvim:**

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

## Completions

swank.nvim ships a native completion source in `lua/swank/blink_source.lua`.
It calls `swank:completions` on every keystroke when a server is connected,
and is a no-op when disconnected (falls back to whatever other sources you have).

### blink.cmp

```lua
require("blink.cmp").setup({
  sources = {
    per_filetype = {
      lisp       = { "swank", "buffer" },
      commonlisp = { "swank", "buffer" },
    },
    providers = {
      swank = {
        name   = "Swank",
        module = "swank.blink_source",
      },
    },
  },
})
```

### nvim-cmp

nvim-cmp uses a different source interface. Add this thin wrapper anywhere on
your runtime path (e.g. `lua/cmp_swank.lua`):

```lua
-- lua/cmp_swank.lua
local M = {}

M.new = function()
  return setmetatable({}, { __index = M })
end

M.get_keyword_pattern = function()
  return [[[a-zA-Z0-9\-\+\*\/\<\>\=\!\?\:\&\#\@\$\^\~\.]+]]
end

M.complete = function(_, params, callback)
  local ok, client = pcall(require, "swank.client")
  if not ok or not client.is_connected() then
    callback({ items = {}, isIncomplete = false })
    return
  end
  local prefix = params.context.cursor_before_line:match("[%w%-%+%*%/%<%>%=%!%?%:%&%#%@%$%%^~%.]+$") or ""
  if prefix == "" then
    callback({ items = {}, isIncomplete = false })
    return
  end
  client.rex({ "swank:completions", prefix, client.get_package() }, function(result)
    if type(result) ~= "table" or result[1] ~= ":ok" then
      callback({ items = {}, isIncomplete = false })
      return
    end
    local list = (type(result[2]) == "table" and result[2][1]) or {}
    local items = {}
    for _, c in ipairs(list) do
      if type(c) == "string" then
        table.insert(items, { label = c, kind = vim.lsp.protocol.CompletionItemKind.Function })
      end
    end
    callback({ items = items, isIncomplete = false })
  end)
end

return M
```

Then register it:

```lua
require("cmp").setup.filetype({ "lisp", "commonlisp" }, {
  sources = {
    { name = "swank" },
    { name = "buffer" },
  },
})
require("cmp").register_source("swank", require("cmp_swank"))
```

### Other plugins

Any plugin that honours `omnifunc` (coq_nvim, mini.completion, etc.) can be
wired by setting the buffer option. swank.nvim does **not** set `omnifunc`
automatically, so add this to your FileType autocmd if needed:

```lua
vim.bo[args.buf].omnifunc = "v:lua.require'swank.client'.complete_omnifunc"
```

*(A proper `complete_omnifunc` shim is planned; for now blink.cmp and nvim-cmp
are the recommended paths.)*

## Default keybindings

All `<Leader>` bindings are buffer-local and prefixed with the configured `leader` (default `<Leader>`).

| Key | Mode | Action |
|-----|------|--------|
| `<Leader>lc` | n | Connect to Swank server |
| `<Leader>rr` | n | Start configured CL implementation and connect |
| `<Leader>ld` | n | Disconnect |
| `<Leader>lp` | n | Set current package |
| `<Leader>ee` | n | Eval top-level form |
| `<Leader>ee` | v | Eval region |
| `<Leader>ei` | n | Eval (prompt) |
| `<Leader>rw` | n | Toggle REPL window |
| `<Leader>id` | n/v | Describe symbol (floating popup) |
| `<Leader>ia` | n/v | Apropos (prompt / selection) |
| `<Leader>iA` | n | Apropos symbol at cursor |
| `<Leader>ii` | n | Inspect value at cursor |
| `<Leader>xd` | n | Find definition |
| `<Leader>xc` | n | Who calls symbol |
| `<Leader>xr` | n | Who references symbol |
| `<Leader>fl` | n | Load file |
| `<Leader>fc` | n | Compile file |
| `<Leader>fs` | n | Compile form at cursor |
| `<Leader>tt` | n | Open trace dialog |
| `<Leader>td` | n | Toggle trace on symbol |
| `<Leader>tD` | n | Untrace all |
| `<Leader>tc` / `<Leader>tg` | n | Clear / refresh trace entries |

### LSP-compatible keymaps

These standard Neovim keymaps are set as buffer-local overrides for Lisp buffers,
so the familiar muscle memory works without a Language Server:

| Key | Action |
|-----|--------|
| `gd` | Go to definition (Swank xref) |
| `K` | Describe / hover (floating popup) |
| `gr` | Find references → picker or quickfix |
| `gR` | Find callers → picker or quickfix |
| `<C-k>` | Arglist / signature help (normal + insert) |

## Documentation

See `:help swank.nvim` after installation.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for coverage requirements (80% floor, 100% goal) and test instructions.

## Acknowledgements

- [SLIME](https://github.com/slime/slime) — the original Swank protocol and the Emacs CL environment this is modelled after
- [Swank](https://github.com/slime/slime/blob/master/swank.lisp) — the server-side protocol implementation included with SBCL and other implementations
- [vlime](https://github.com/vlime/vlime) and [nvlime](https://github.com/monkoose/nvlime) — prior Neovim/Vim Swank clients that proved the concept
- [Conjure](https://github.com/Olical/conjure) — inspiration for a clean Neovim-native Lisp workflow
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) — test harness (busted runner) used throughout the test suite
- [blink.cmp](https://github.com/Saghen/blink.cmp) — completion framework with a clean source API

## License

MIT
