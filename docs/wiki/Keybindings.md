# Keybindings

All keymaps use `<LocalLeader>` as the prefix and are configurable via `maplocalleader`.
The examples below assume `maplocalleader = " "` (i.e. Space) — adjust to match your config.
See [Configuration](Configuration) for setup details.

---

## Connection

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<LocalLeader>lc` | Connect to Swank server |
| n | `<LocalLeader>ld` | Disconnect |
| n | `<LocalLeader>lp` | Set current CL package (prompts) |
| n | `<LocalLeader>rr` | Start configured CL implementation and connect (autostart) |

---

## Evaluation

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<LocalLeader>ee` | Eval top-level form (outermost `(...)` around cursor) |
| v | `<LocalLeader>ee` | Eval visual selection |
| n | `<LocalLeader>ei` | Eval expression interactively (prompts for input) |

---

## REPL

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<LocalLeader>rw` | Toggle REPL window |

---

## Introspection

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<LocalLeader>id` | Describe symbol under cursor |
| v | `<LocalLeader>id` | Describe selected symbol |
| n | `<LocalLeader>ia` | Apropos (prompts for query) |
| n | `<LocalLeader>iA` | Apropos symbol under cursor |
| v | `<LocalLeader>ia` | Apropos selected symbol |
| n | `<LocalLeader>ii` | Inspect value of symbol under cursor |

---

## Cross-reference

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<LocalLeader>xc` | Who calls symbol under cursor |
| n | `<LocalLeader>xr` | Who references symbol under cursor |
| n | `<LocalLeader>xd` | Find definition of symbol under cursor |

---

## File / Compilation

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<LocalLeader>fl` | Load file into Lisp image |
| n | `<LocalLeader>fc` | Compile file |
| n | `<LocalLeader>fs` | Compile form at cursor |

---

## Trace

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<LocalLeader>tt` | Open trace dialog |
| n | `<LocalLeader>td` | Toggle trace on symbol under cursor (prompts if none) |
| n | `<LocalLeader>tD` | Untrace all |
| n | `<LocalLeader>tc` | Clear trace entries |
| n | `<LocalLeader>tg` | Refresh trace entries |

---

## LSP-compatible overrides

Buffer-local overrides so standard editor muscle-memory works in Lisp buffers:

| Mode | Keymap | Action | Standard LSP equivalent |
|------|--------|--------|------------------------|
| n | `gd` | Find definition | `vim.lsp.buf.definition` |
| n | `K` | Describe symbol | `vim.lsp.buf.hover` |
| n | `gr` | Who references | `vim.lsp.buf.references` |
| n | `gR` | Who calls | *(no standard equivalent)* |
| n/i | `<C-k>` | Autodoc (arglist) | `vim.lsp.buf.signature_help` |

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
    vim.keymap.set("n", "<LocalLeader>E", function()
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
| `<LocalLeader>` | swank |
| `<LocalLeader>l` | connection |
| `<LocalLeader>e` | eval |
| `<LocalLeader>r` | repl/server |
| `<LocalLeader>i` | inspect |
| `<LocalLeader>x` | xref |
| `<LocalLeader>f` | file/compile |
| `<LocalLeader>t` | trace |
