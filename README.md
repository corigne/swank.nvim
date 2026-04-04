# swank.nvim

[![CI](https://github.com/corigne/swank.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/corigne/swank.nvim/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/coverage-82%25-green?style=flat-square&logo=lua)](luacov.report.out)

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
- [x] Completion via `swank:completions` — native blink.cmp source (`swank.blink_source`), nvim-cmp wrapper documented
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
    -- leader prefix for all swank keybindings (default: "<LocalLeader>")
    leader = "<LocalLeader>",
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
        -- "auto" picks based on editor width: >=120 cols→right, >=80→bottom, else float
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

**Requires:** Neovim 0.10+, SBCL + Quicklisp (for autostart)

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
wired by setting the buffer option — swank.nvim does **not** set `omnifunc`
automatically, so add this to your FileType autocmd if needed:

```lua
vim.bo[args.buf].omnifunc = "v:lua.require'swank.client'.complete_omnifunc"
```

*(A proper `complete_omnifunc` shim is planned; for now blink.cmp and nvim-cmp
are the recommended paths.)*

## Default keybindings

All `<Leader>` bindings are buffer-local and prefixed with the configured `leader` (default `<LocalLeader>`).

| Key | Mode | Action |
|-----|------|--------|
| `<Leader>cc` | n | Connect to Swank server |
| `<Leader>rr` | n | Start SBCL and connect |
| `<Leader>cd` | n | Disconnect |
| `<Leader>cp` | n | Set current package |
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
| `gr` | Find references → quickfix |
| `gR` | Find callers → quickfix |
| `<C-k>` | Arglist / signature help (normal + insert) |

## Documentation

See `:help swank.nvim` after installation.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — includes coverage requirements (80% floor, 100% goal) and test instructions.

## License

MIT
