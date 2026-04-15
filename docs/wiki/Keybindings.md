# Keybindings

All keymaps use `<Leader>` as the prefix by default (configurable via `config.leader`).
All bindings are **buffer-local** to Lisp buffers so they never shadow global mappings
in other filetypes. Because most users set `mapleader` and `maplocalleader` to the same
key, two bindings use capital letters to avoid known conflicts with Snacks/LazyVim:
`<Leader>fC` (compile file) and `<Leader>fD` (disassemble) avoid `<Leader>fc` (Find
Config File) and `<Leader>fd` (common LSP definition binding).

---

## Connection / Server

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>lc` | Connect to Swank server |
| n | `<Leader>ld` | Disconnect |
| n | `<Leader>lp` | Set current CL package (prompts) |
| n | `<Leader>rr` | Start configured CL implementation and connect (autostart) |

---

## Evaluation

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>ee` | Eval top-level form (outermost `(...)` around cursor) |
| v | `<Leader>ee` | Eval visual selection |
| n | `<Leader>ei` | Eval expression interactively (prompts for input) |
| n | `<Leader>em` | Macroexpand-1 form at cursor |
| n | `<Leader>eM` | Macroexpand-all form at cursor |

---

## REPL

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>rw` | Toggle REPL window |
| n | `<Leader>e<Up>` | Re-open eval prompt pre-filled with older history entry |
| n | `<Leader>e<Down>` | Re-open eval prompt pre-filled with newer history entry |

---

## Introspection

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>id` | Describe symbol under cursor |
| v | `<Leader>id` | Describe selected symbol |
| n | `<Leader>ia` | Apropos (prompts for query) |
| n | `<Leader>iA` | Apropos symbol under cursor |
| v | `<Leader>ia` | Apropos selected symbol |
| n | `<Leader>ii` | Inspect value of symbol under cursor |

---

## Cross-reference

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>xc` | Who calls symbol under cursor |
| n | `<Leader>xr` | Who references symbol under cursor |
| n | `<Leader>xb` | Who binds symbol under cursor |
| n | `<Leader>xs` | Who sets symbol under cursor |
| n | `<Leader>xm` | Who macroexpands symbol under cursor |
| n | `<Leader>xS` | Who specializes on symbol under cursor |
| n | `<Leader>xd` | Find definition of symbol under cursor |

---

## File / Compilation

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>fl` | Load file into Lisp image |
| n | `<Leader>fC` | Compile file |
| n | `<Leader>fs` | Compile form at cursor |
| n | `<Leader>fD` | Disassemble symbol at cursor |

---

## Trace

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>tt` | Open trace dialog |
| n | `<Leader>td` | Toggle trace on symbol under cursor (prompts if no symbol) |
| n | `<Leader>tD` | Untrace all |
| n | `<Leader>tc` | Clear trace entries |
| n | `<Leader>tg` | Refresh trace entries |

---

## Profiling

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>pp` | Profile symbol at cursor |
| n | `<Leader>pP` | Unprofile all functions |
| n | `<Leader>pr` | Show profiling report |
| n | `<Leader>p0` | Reset profiling counters |

---

## Threads

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>Tl` | List threads; select a thread to kill it |

---

## LSP-compatible fallbacks

These bindings are registered as Swank fallbacks only when no LSP client is attached
to the buffer. If an LSP client attaches later its own keymaps take precedence. When
the last LSP client detaches the Swank fallbacks are automatically restored.

| Mode | Keymap | Action | LSP equivalent |
|------|--------|--------|----------------|
| n | `gd` | Find definition (Swank fallback) | `vim.lsp.buf.definition` |
| n | `K` | Describe symbol (Swank fallback) | `vim.lsp.buf.hover` |
| n | `gr` | Who references (Swank fallback) | `vim.lsp.buf.references` |
| n | `gR` | Who calls (Swank fallback) | *(no standard LSP equivalent)* |
| n | `<C-k>` | Autodoc / signature help (Swank fallback) | `vim.lsp.buf.signature_help` |

---

## Customising keymaps

swank.nvim does not currently expose a per-keymap config option.
To override individual keys, add your own `vim.keymap.set` calls after
`require("swank").attach(bufnr)`:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "lisp", "commonlisp" },
  callback = function(ev)
    require("swank").attach(ev.buf)
    -- override eval-toplevel to a different key
    vim.keymap.set("n", "<Leader>E", function()
      require("swank.client").eval_toplevel()
    end, { buffer = ev.buf })
  end,
})
```

---

## which-key integration

If which-key is installed, swank.nvim registers group labels automatically:

| Prefix | Label |
|--------|-------|
| `<Leader>` | swank |
| `<Leader>e` | eval/expand |
| `<Leader>r` | repl/server |
| `<Leader>i` | inspect |
| `<Leader>x` | xref |
| `<Leader>f` | file/compile |
| `<Leader>l` | connection |
| `<Leader>t` | trace |
| `<Leader>p` | profiling |
| `<Leader>T` | threads |
