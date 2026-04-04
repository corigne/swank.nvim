# Configuration

Full reference for `require("swank").setup(opts)`.

All keys are optional. Any key not provided keeps its default value.

---

## Top-level options

```lua
require("swank").setup({
  host         = "127.0.0.1",  -- Swank server host
  port         = 4005,         -- Swank server port
  autostart    = false,        -- spawn sbcl automatically on attach
  swank_script = nil,          -- path to start-swank.lisp (required if autostart = true)
  sbcl_cmd     = "sbcl",       -- sbcl binary name or path
  ui           = {             -- see UI section below
    repl = { ... },
  },
})
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `host` | `string` | `"127.0.0.1"` | Hostname or IP of the Swank server |
| `port` | `number` | `4005` | TCP port |
| `autostart` | `boolean` | `false` | Start sbcl and load `swank_script` on attach |
| `swank_script` | `string\|nil` | `nil` | Path to a `.lisp` file that starts the Swank server |
| `sbcl_cmd` | `string` | `"sbcl"` | Command used to invoke sbcl when `autostart = true` |
| `ui.repl` | `table` | see below | REPL window configuration |

---

## REPL UI options — `ui.repl`

```lua
require("swank").setup({
  ui = {
    repl = {
      position = "auto",  -- "auto" | "right" | "bottom" | "float"
      size     = 0.45,    -- fraction (0–1) or fixed column/row count
    }
  }
})
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `position` | `string` | `"auto"` | Window placement strategy |
| `size` | `number` | `0.45` | Width (for `"right"`) or height (for `"bottom"`) as fraction or integer |

### Position values

| Value | Behaviour |
|-------|-----------|
| `"auto"` | Picks the best layout at runtime based on terminal size (see [Architecture: REPL adaptive layout](Architecture#repl-adaptive-layout)) |
| `"right"` | Always a vertical split on the right |
| `"bottom"` | Always a horizontal split below |
| `"float"` | Always a floating window centred on screen |

### Size

- `0.45` (default) — 45% of the relevant dimension
- `0.33` — one third
- `80` — exactly 80 columns/rows
- For `"auto"`, size is checked against the 80-column threshold to decide
  between `"right"` and `"bottom"` — see [Architecture](Architecture)

---

## Example: minimal config

```lua
require("swank").setup({})
-- connects to 127.0.0.1:4005, vertical split REPL at 45%
```

## Example: full config

```lua
require("swank").setup({
  host         = "127.0.0.1",
  port         = 4005,
  autostart    = true,
  swank_script = vim.fn.expand("~/.config/nvim/start-swank.lisp"),
  sbcl_cmd     = "sbcl",
  ui = {
    repl = {
      position = "auto",
      size     = 0.33,
    }
  }
})
```

## Example: lazy.nvim with opts

```lua
{
  "corigne/swank.nvim",
  ft    = { "lisp", "commonlisp" },
  opts  = {
    autostart    = true,
    swank_script = vim.fn.expand("~/.sbcl/start-swank.lisp"),
    ui = { repl = { position = "auto", size = 0.45 } },
  },
}
```
