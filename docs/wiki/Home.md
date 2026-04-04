# swank.nvim Wiki

> Pure-Lua Neovim-native Common Lisp development via the Swank protocol.

## Contents

| Page | Description |
|------|-------------|
| [Architecture](Architecture) | How the layers fit together; async model; event dispatch |
| [Configuration](Configuration) | Full `setup()` option reference |
| [Completions](Completions) | blink.cmp, nvim-cmp, and omnifunc setup |
| [Keybindings](Keybindings) | Default keymaps, LSP-compatible overrides, customisation |
| [REPL](REPL) | REPL usage, window layout, auto-open behaviour |
| [Protocol](Protocol) | Swank S-expression framing internals (for contributors) |
| [Contributing](Contributing) | Coverage floor, test placement, code style |
| [Testing](Testing) | Test infrastructure, how to run tests, writing new tests |

---

## Quick start

### 1. Install

**lazy.nvim:**
```lua
{
  "corigne/swank.nvim",
  ft = { "lisp", "commonlisp" },
  opts = {},
}
```

### 2. Wire up per-buffer

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "lisp", "commonlisp" },
  callback = function(ev)
    require("swank").attach(ev.buf)
  end,
})
```

### 3. Start Swank in your Lisp project

```lisp
;; start-swank.lisp
(require :swank)
(swank:create-server :port 4005 :dont-close t)
```

```sh
sbcl --load start-swank.lisp
```

### 4. Connect from Neovim

```
<LocalLeader>lc  (Connect to Swank server)
```

---

## Feature overview

| Feature | Status |
|---------|--------|
| TCP transport | ✅ |
| REPL (eval + output) | ✅ |
| Completion (blink.cmp) | ✅ |
| Autodoc / arglist | ✅ |
| Describe symbol | ✅ (floating popup) |
| Inspect object | ✅ |
| Cross-reference (xref) | ✅ |
| Find definition | ✅ |
| Compiler notes (diagnostics) | ✅ |
| Debugger (SLDB) | ✅ |
| Trace dialog | ✅ |
