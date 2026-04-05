# Completions

swank.nvim ships a native blink.cmp source and documents an nvim-cmp wrapper.
Completions come from `swank:completions` (standard) and optionally
`swank:fuzzy-completions` (fuzzy matching).

---

## blink.cmp (recommended)

Add `swank` to your blink.cmp provider list for Lisp buffers:

```lua
-- plugins.lua or wherever blink.cmp is configured
{
  "saghen/blink.cmp",
  opts = {
    sources = {
      providers = {
        swank = {
          name   = "Swank",
          module = "swank.blink_source",
        },
      },
      per_filetype = {
        lisp        = { "swank", "buffer" },
        commonlisp  = { "swank", "buffer" },
      },
    },
  },
}
```

The source is automatically disabled when no Swank connection is active
(`client.is_connected()` returns false), so it coexists safely with other
sources without producing errors.

### What it provides

- Symbol completions scoped to the current package
- Package-qualified completions (`package:symbol`)
- Package prefix completions (`package:`)
- Completion items include kind (`Function`, `Variable`, `Type`, etc.) when
  Swank provides it

---

## nvim-cmp

nvim-cmp doesn't support the blink source interface. Register swank as a
custom source:

```lua
local cmp = require("cmp")

cmp.register_source("swank", {
  is_available = function()
    return require("swank.client").is_connected()
  end,

  get_keyword_pattern = function()
    -- match CL symbols including package prefix and special chars
    return [[\k\+]]
  end,

  complete = function(self, request, callback)
    local line_before = request.context.cursor_before_line
    local prefix = line_before:match("[%w%-:]+$") or ""
    if prefix == "" then callback({ items = {}, isIncomplete = false }); return end

    require("swank.client"):completions(prefix, function(result)
      if not result then callback({ items = {}, isIncomplete = false }); return end
      local completions = result[2] and result[2][1] or {}
      local items = {}
      for _, comp in ipairs(completions) do
        table.insert(items, { label = comp, kind = cmp.lsp.CompletionItemKind.Function })
      end
      callback({ items = items, isIncomplete = false })
    end)
  end,
})

-- Then add "swank" to your sources:
cmp.setup.filetype({ "lisp", "commonlisp" }, {
  sources = cmp.config.sources({
    { name = "swank" },
    { name = "buffer" },
  }),
})
```

---

## omnifunc (fallback)

For any completion plugin that respects `omnifunc`, set:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "lisp", "commonlisp" },
  callback = function()
    vim.bo.omnifunc = "v:lua.require'swank.client'.omnifunc"
  end,
})
```

Trigger with `<C-x><C-o>` in insert mode.

---

## Troubleshooting

### Completions don't appear

1. Check that swank is connected: `:lua print(require("swank.client").is_connected())`
2. Verify the source name matches exactly; blink is case-sensitive.
3. Make sure you don't have a conflicting omnifunc set (e.g. from a previous
   Vlime install: `blink.cmp opts = { complete_func = "vlime#..." }`)

### Error: `attempt to call field 'complete_func' (a string value)`

This is a leftover Vlime blink.cmp config. Remove any `complete_func` key from
your blink.cmp opts for Lisp filetypes.
