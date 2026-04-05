# REPL

The REPL in swank.nvim is a read-only output buffer that displays all output
from the Swank server: evaluation results, `format t` output, warnings, and
interactive prompts.

---

## Opening the REPL

The REPL window opens automatically whenever new output arrives from the server.
You can also toggle it manually:

```
<Leader>rw
```

---

## Layout

Three layouts are available: vertical split (right), horizontal split (bottom),
and floating window.

### `"auto"` (default)

The plugin picks the best layout based on your terminal dimensions:

1. **Vertical split (right)** — if the configured size gives the REPL at least
   80 columns. At the default 45%, this requires ~178 terminal columns.
2. **Horizontal split (bottom)** — if the vertical split would be too narrow but
   a horizontal split gives at least 12 rows.
3. **Float** — if the terminal is too small for either split.

### Explicit layouts

```lua
require("swank").setup({
  ui = {
    repl = {
      position = "right",   -- always vertical split
      -- position = "bottom", -- always horizontal split
      -- position = "float",  -- always floating
      size     = 0.45,
    }
  }
})
```

### Size

`size` controls the width (for `"right"`) or height (for `"bottom"`) of the
REPL window.

| Value | Meaning |
|-------|---------|
| `0.45` | 45% of the relevant editor dimension (default) |
| `0.33` | 33% (one-third) |
| `0.25` | 25% |
| `80` | exactly 80 columns or rows |

---

## Switching packages

```
<Leader>lp
```

Prompts for a package name and tells the Swank server to switch the active
evaluation context to that package. This is a connection-level setting and is
available from any Lisp buffer, not just the REPL.

---

## Output types

The REPL buffer shows output from multiple Swank event types:

| Swank event | What you see |
|-------------|-------------|
| `:write-string` | Raw output from `(format t ...)`, `(print ...)`, etc. |
| `:presentation-start` / `:presentation-end` | Result presentations from eval |
| `:read-string` | Interactive read prompt (e.g. `(read)`) |
| `:debug-activate` | Debugger entered — shown inline before SLDB window |

---

## Interacting with the REPL buffer

The REPL buffer (`swank://repl`) is normally read-only. To send an expression
to the server, use `<Leader>ei` (interactive eval with prompt) or the eval
keymaps from a Lisp source buffer.

---

## Troubleshooting

### REPL doesn't open automatically

Check that `require("swank").attach(bufnr)` is being called for your Lisp buffers.
The auto-open is triggered from `ui/repl.lua:M.append()`, which is only called
if the client is wired up.

### REPL opens in the wrong place

Explicitly set `position` to `"right"`, `"bottom"`, or `"float"` in your config
to bypass the auto-detection logic.

### Startup noise from SBCL

swank.nvim silently discards stderr from the sbcl process during normal startup.
The Swank contrib compilation STYLE-WARNINGs you see in a terminal are suppressed.
Stderr is only surfaced as a notification if sbcl exits with a non-zero exit code.
