# Keybindings

All keymaps are buffer-local and only active in `lisp` / `commonlisp` buffers
once `require("swank").attach(bufnr)` has been called.

The `<Space>` prefix is the `<leader>` key (configurable — see below).

---

## Connection

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>sc` | Connect to Swank server |
| n | `<Space>sd` | Disconnect |
| n | `<Space>sr` | Reconnect |

---

## Evaluation

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>ee` | Eval top-level form (the outermost `(...)` around cursor) |
| v | `<Space>ee` | Eval visual selection |
| n | `<Space>ei` | Eval expression interactively (prompts for input) |
| n | `<Space>eb` | Eval entire buffer |
| n | `<Space>el` | Eval current line |

---

## REPL

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>ro` | Open / focus REPL window |
| n | `<Space>rc` | Clear REPL buffer |
| n | `<Space>rp` | Switch CL package (prompts for package name) |

---

## Introspection

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>ds` | Describe symbol under cursor (floating popup) |
| n | `<Space>is` | Inspect value of symbol under cursor |
| n/i | `<Space>aa` | Autodoc — show argument list for operator at cursor |

---

## Cross-reference

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>xc` | Who calls symbol under cursor |
| n | `<Space>xr` | Who references symbol under cursor |
| n | `<Space>xd` | Find definition of symbol under cursor |

---

## Compilation

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Space>cd` | Compile defun (top-level form) under cursor |
| n | `<Space>cf` | Compile and load file |

---

## LSP-compatible overrides

These are set as buffer-local overrides so standard editor muscle-memory works:

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
    vim.keymap.set("n", "<Space>x", function()
      require("swank.client"):eval_toplevel(
        require("swank.keymaps")._form_at_cursor()
      )
    end, { buffer = ev.buf })
  end,
})
```

---

## which-key integration

If which-key is installed, swank.nvim registers group labels automatically:

| Prefix | Label |
|--------|-------|
| `<Space>s` | Swank |
| `<Space>e` | Eval |
| `<Space>r` | REPL |
| `<Space>d` | Describe |
| `<Space>i` | Inspect |
| `<Space>x` | XRef |
| `<Space>c` | Compile |
