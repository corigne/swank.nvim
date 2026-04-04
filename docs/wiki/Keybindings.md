# Keybindings

All keymaps are buffer-local and only active in `lisp` / `commonlisp` buffers
once `require("swank").attach(bufnr)` has been called.

The `<Space>` prefix is the `<LocalLeader>` key (configurable — see [Configuration](Configuration)).

---

## Connection

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>sc` | Connect to Swank server |
| n | `<Space>sd` | Disconnect |
| n | `<Space>sp` | Set current CL package (prompts) |
| n | `<Space>rr` | Start CL implementation + connect (autostart) |

---

## Evaluation

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>ee` | Eval top-level form (outermost `(...)` around cursor) |
| v | `<Space>ee` | Eval visual selection |
| n | `<Space>ei` | Eval expression interactively (prompts for input) |

---

## REPL

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>rw` | Toggle REPL window |

---

## Introspection

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>id` | Describe symbol under cursor |
| v | `<Space>id` | Describe selected symbol |
| n | `<Space>ia` | Apropos (prompts for query) |
| n | `<Space>iA` | Apropos symbol under cursor |
| v | `<Space>ia` | Apropos selected symbol |
| n | `<Space>ii` | Inspect value of symbol under cursor |

---

## Cross-reference

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>xc` | Who calls symbol under cursor |
| n | `<Space>xr` | Who references symbol under cursor |
| n | `<Space>xd` | Find definition of symbol under cursor |

---

## File / Compilation

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>fl` | Load file into Lisp image |
| n | `<Space>fc` | Compile file |
| n | `<Space>fs` | Compile form at cursor |

---

## Trace

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>tt` | Open trace dialog |
| n | `<Space>td` | Toggle trace on symbol under cursor (prompts if none) |
| n | `<Space>tD` | Untrace all |
| n | `<Space>tc` | Clear trace entries |
| n | `<Space>tg` | Refresh trace entries |

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
| `<Space>` | swank |
| `<Space>s` | connection |
| `<Space>e` | eval |
| `<Space>r` | repl/server |
| `<Space>i` | inspect |
| `<Space>x` | xref |
| `<Space>f` | file/compile |
| `<Space>t` | trace |
