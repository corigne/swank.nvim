# Completions

swank.nvim ships native completion sources for blink.cmp and nvim-cmp.
Both engines get lazy documentation previews via `swank:describe-symbol`
when you dwell on an item. Completions come from `swank:completions`
(standard) or `swank:fuzzy-completions` (fuzzy matching, blink primary source).

---

## blink.cmp (recommended)

Two sources are available — use whichever fits your setup:

| Module | Backend | Fuzzy | Notes |
|---|---|---|---|
| `swank.blink_source` | `swank:completions` | No | Simpler, broader trigger |
| `swank.sources.blink` | `swank:fuzzy-completions` | Yes | Ranked results, `:` trigger |

```lua
-- plugins.lua or wherever blink.cmp is configured
{
  "saghen/blink.cmp",
  opts = {
    sources = {
      providers = {
        swank = {
          name   = "Swank",
          module = "swank.blink_source",  -- or "swank.sources.blink" for fuzzy
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

The source is automatically disabled when no Swank connection is active,
so it coexists safely with other sources without producing errors.

---

## nvim-cmp

swank.nvim ships a native nvim-cmp source at `lua/swank/sources/nvim_cmp.lua`.
Load it once (it self-registers), then add `"swank"` to your sources:

```lua
-- Anywhere before nvim-cmp completes its setup (e.g. in your plugin init)
require("swank.sources.nvim_cmp")

-- Per-filetype sources
local cmp = require("cmp")
cmp.setup.filetype({ "lisp", "commonlisp" }, {
  sources = cmp.config.sources({
    { name = "swank" },
    { name = "buffer" },
  }),
})
```

The source is automatically disabled when no Swank connection is active.

---

## Completion documentation

Both the blink.cmp and nvim-cmp sources implement `resolve()` — the lazy
callback each engine calls when you dwell on an item in the completion menu.
On resolve, the source fires `swank:describe-symbol` and populates the
`documentation` field (LSP `MarkupContent`) with the full symbol description.

No extra configuration is needed; this works automatically with any engine that
supports completion item resolve (blink.cmp, nvim-cmp).

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
