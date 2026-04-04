# Configuration

Full reference for `require("swank").setup(opts)`.

All keys are optional. Unset keys keep their default values.

A machine-readable **JSON Schema** is available at
[`schemas/swank.nvim.json`](https://github.com/corigne/swank.nvim/blob/main/schemas/swank.nvim.json).
If you use [neoconf.nvim](https://github.com/folke/neoconf.nvim), swank.nvim registers the schema
automatically during `setup()`, enabling completions and validation in `.neoconf.json`.

---

## Full schema with defaults

```lua
require("swank").setup({
  -- Key prefix for all swank.nvim keymaps (default: "<LocalLeader>")
  leader = "<LocalLeader>",

  -- Swank server connection settings
  server = {
    host = "127.0.0.1",
    port = 4005,
  },

  -- Autostart: spawn a CL implementation and connect automatically on attach
  autostart = {
    enabled        = true,      -- start the implementation on FileType attach
    implementation = "sbcl",    -- binary name or full path
  },

  -- UI settings
  ui = {
    repl = {
      position = "auto",  -- "auto" | "left" | "right" | "top" | "bottom" | "float"
      size     = 0.45,    -- fraction (0 < size <= 1) or fixed columns/rows
    },
    floating = {
      border = "rounded", -- border style for floating windows
    },
  },

  -- Swank contribs to load on connect
  contribs = {
    ":swank-asdf",
    ":swank-repl",
    ":swank-fuzzy",
    ":swank-arglists",
    ":swank-fancy-inspector",
    ":swank-trace-dialog",
    ":swank-c-p-c",
    ":swank-package-fu",
  },
})
```

---

## Top-level options

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `leader` | `string` | `"<LocalLeader>"` | Prefix for all swank.nvim keymaps |
| `server` | `table` | see below | Connection settings |
| `autostart` | `table` | see below | Autostart settings |
| `ui` | `table` | see below | Window and layout settings |
| `contribs` | `string[]` | *(list above)* | Swank contribs loaded on connect |

---

## Server options — `server`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `server.host` | `string` | `"127.0.0.1"` | Hostname or IP of the Swank server |
| `server.port` | `number` | `4005` | TCP port (only used when connecting to an external server) |

---

## Autostart options — `autostart`

When `autostart.enabled = true`, swank.nvim generates a startup script, runs
the configured CL implementation, starts Swank on an **ephemeral port**
(`:port 0`), and connects automatically. You do not need to manage a start
file or port yourself.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `autostart.enabled` | `boolean` | `true` | Spawn the implementation on `attach()` |
| `autostart.implementation` | `string` | `"sbcl"` | Binary name or full path of the CL implementation |

To disable autostart and connect manually:

```lua
require("swank").setup({
  autostart = { enabled = false },
})
```

Then connect with `<LocalLeader>lc` (or `<LocalLeader>rr` to start + connect).

---

## REPL UI options — `ui.repl`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ui.repl.position` | `string` | `"auto"` | Window placement strategy |
| `ui.repl.size` | `number` | `0.45` | Width (for vertical splits) or height (for horizontal) as fraction `(0 < size <= 1)` or fixed integer |

### Position values

| Value | Behaviour |
|-------|-----------|
| `"auto"` | Picks the best layout at runtime — see [Architecture: REPL adaptive layout](Architecture#repl-adaptive-layout) |
| `"right"` | Vertical split on the right |
| `"left"` | Vertical split on the left |
| `"bottom"` | Horizontal split below |
| `"top"` | Horizontal split above |
| `"float"` | Floating window centred on screen |

### Size

- `0.45` (default) — 45% of the relevant editor dimension
- `0.33` — one third
- `80` — exactly 80 columns or rows

---

## Floating window options — `ui.floating`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ui.floating.border` | `string` | `"rounded"` | Any border value accepted by Neovim for `nvim_open_win()` — see `:h nvim_open_win()`. Common values: `"rounded"`, `"single"`, `"double"`, `"solid"`, `"none"` |

---

## Contribs — `contribs`

List of Swank contrib keyword symbols loaded on connect. The defaults cover
all standard SLIME-equivalent features. Removing a contrib disables the
functionality that depends on it:

| Contrib | Provides |
|---------|---------|
| `:swank-asdf` | ASDF system loading |
| `:swank-repl` | REPL listener |
| `:swank-fuzzy` | Fuzzy completion |
| `:swank-arglists` | Autodoc / arglist hints |
| `:swank-fancy-inspector` | Object inspector |
| `:swank-trace-dialog` | Trace dialog |
| `:swank-c-p-c` | Compound prefix completion |
| `:swank-package-fu` | Package management helpers |

---

## Examples

### Minimal (all defaults)

```lua
require("swank").setup({})
```

### Manual connect, specific port

```lua
require("swank").setup({
  autostart = { enabled = false },
  server    = { host = "127.0.0.1", port = 14005 },
})
```

### CCL with bottom REPL

```lua
require("swank").setup({
  autostart = { enabled = true, implementation = "ccl" },
  ui        = { repl = { position = "bottom", size = 0.35 } },
})
```

### lazy.nvim

```lua
{
  "corigne/swank.nvim",
  ft   = { "lisp", "commonlisp" },
  opts = {
    leader    = "<LocalLeader>",
    autostart = { enabled = true, implementation = "sbcl" },
    ui        = { repl = { position = "auto", size = 0.45 } },
  },
}
```
