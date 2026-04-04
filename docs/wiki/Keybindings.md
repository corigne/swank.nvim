# Keybindings

All keymaps use `<Leader>` as the prefix. Set `mapleader` in your Neovim config to choose your preferred key.
See [Configuration](Configuration) for setup details.

---

## Connection

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

---

## REPL

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>rw` | Toggle REPL window |

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
| n | `<Leader>xd` | Find definition of symbol under cursor |

---

## File / Compilation

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>fl` | Load file into Lisp image |
| n | `<Leader>fc` | Compile file |
| n | `<Leader>fs` | Compile form at cursor |

---

## Trace

| Mode | Keymap | Action |
|------|--------|--------|
| n | `<Leader>tt` | Open trace dialog |
| n | `<Leader>td` | Toggle trace on symbol under cursor (prompts if none) |
| n | `<Leader>tD` | Untrace all |
| n | `<Leader>tc` | Clear trace entries |
| n | `<Leader>tg` | Refresh trace entries |

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
| `<Leader>l` | connection |
| `<Leader>e` | eval |
| `<Leader>r` | repl/server |
| `<Leader>i` | inspect |
| `<Leader>x` | xref |
| `<Leader>f` | file/compile |
| `<Leader>t` | trace |
