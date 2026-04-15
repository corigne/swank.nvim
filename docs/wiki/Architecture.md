# Architecture

swank.nvim is structured as a strict layered pipeline with clearly separated concerns.
No layer reaches upward or sideways; data flows top-down.

```
Editor events (keypress, autocmd, filetype)
         │
         ▼
   keymaps.lua   ←──  cursor, visual marks, vim.ui.input prompts
         │                editor context never crosses this line
         ▼
   client.lua    ←──  all high-level Swank RPC calls
         │                plain Lua strings only below here
         ▼
  protocol.lua   ←──  S-expression serialiser + event dispatcher
         │
         ▼
  transport.lua  ←──  vim.uv TCP socket, 6-hex-byte framing
         │
         ▼
  Swank server (sbcl/ccl/ecl…)
```

---

## Transport layer — `transport.lua`

Wraps a single `vim.uv.tcp` socket.

- **Message framing:** each Swank message is prefixed with a 6-character
  zero-padded hexadecimal byte count (e.g. `000042(+ 1 2)`).
- **Incoming:** a persistent read loop accumulates bytes into a buffer until a
  complete frame is received, then fires `on_message(raw_sexp)`.
- **Outgoing:** `transport:send(string)` prepends the header and calls
  `uv.tcp_write`.
- **Reconnect:** not automatic; the client must call `transport.connect()` again.

```lua
-- internal interface
transport.connect(host, port, on_message, on_error)
transport.send(payload)   -- raw sexp string, framing added here
transport.disconnect()
```

---

## Protocol layer — `protocol.lua`

### S-expression parser

A minimal recursive-descent parser supporting the subset Swank actually sends:
- Lists `(a b c)`
- Strings `"hello \"world\""`
- Keywords `:foo`, `:ok`, `:error`
- Symbols `T`, `NIL`, `swank-repl`
- Integers `-42`, `0`, `65536`

The parser is single-pass with no allocation beyond Lua tables.
It returns a plain Lua table tree with no special node types.

### Serialiser

Converts a Lua table back to Swank S-expression notation for outgoing
`:emacs-rex` calls. Booleans map to `T`/`NIL`, strings are escaped.

### Event dispatcher

```lua
protocol.on("return",          handler)  -- :return events
protocol.on("write-string",    handler)  -- REPL output
protocol.on("debug",           handler)  -- SLDB activate
protocol.on("debug-return",    handler)  -- SLDB exit
protocol.on("presentation-start", handler)
-- etc.
```

Incoming event names are normalised: `:write-string` → `"write-string"`.

---

## Client layer — `client.lua`

The main module. Contains:

### State
- `connection_state` — `"disconnected"` | `"connecting"` | `"connected"`
- `callbacks` — `{ [msg_id] = function(result) ... end }`
- `current_package` — active CL package (default `"COMMON-LISP-USER"`)
- `current_thread` — `:repl-thread` by default

### Low-level: `rex(form, callback)`

Wraps a form in `:emacs-rex` with the current package/thread/msg-id,
serialises it, sends it over transport, registers `callback` for the
`:return` response.

```lisp
;; wire format example
000047(:emacs-rex (swank:connection-info) "COMMON-LISP-USER" :repl-thread 1)
```

### High-level operations

| Function | Swank call |
|----------|-----------|
| `eval_toplevel(form, cb)` | `swank-repl:listener-eval` |
| `completions(prefix, cb)` | `swank:completions` |
| `fuzzy_completions(prefix, cb)` | `swank:fuzzy-completions` |
| `describe(symbol, cb)` | `swank:describe-symbol` |
| `autodoc(form, cb)` | `swank:autodoc` |
| `inspect_symbol(name, cb)` | `swank:inspect-in-emacs` |
| `xref_calls(name, cb)` | `swank:xref :calls` |
| `xref_references(name, cb)` | `swank:xref :references` |
| `find_definition(name, cb)` | `swank:find-definitions-for-emacs` |
| `compile_defun(form, cb)` | `swank:compile-string-for-emacs` |

### Async model

All callbacks fire inside `vim.schedule()` so they are safe to call
Neovim APIs (buffer writes, window opens, diagnostics) from within them.
Never call Neovim APIs directly inside a `vim.uv` callback; always
wrap in `vim.schedule`.

---

## UI layer — `ui/*.lua`

Each UI module is independent and calls `client.*` if it needs more data.

| Module | Displays |
|--------|---------|
| `repl.lua` | Side/bottom/float output buffer; auto-opens on new output |
| `inspector.lua` | Floating inspector window for `swank:inspect-in-emacs` results |
| `xref.lua` | Quickfix list populated from xref results |
| `sldb.lua` | Floating debugger: condition, backtrace, restarts |
| `notes.lua` | Compiler warnings/errors → `vim.diagnostic.set()` |
| `trace.lua` | Trace dialog for SWANK-TRACE-DIALOG contrib |

### REPL adaptive layout

`effective_pos("auto", size)` chooses position at runtime:

1. If `resolve_size(size, vim.o.columns) >= 80` → **right** (vertical split)
2. Else if `resolve_size(size, vim.o.lines) >= 12` → **bottom** (horizontal split)
3. Otherwise → **float**

`size` is a fraction (0–1) or a fixed column/row count (> 1).

---

## Keymaps layer — `keymaps.lua`

All buffer-local. This is the only layer that:
- Reads cursor position (`nvim_win_get_cursor`)
- Reads visual marks (`` `< `` / `` `> ``)
- Calls `vim.ui.input`
- Calls `vim.ui.select`

### LSP-first routing

`gd`, `K`, `gr`, `<C-k>` are registered as Swank fallbacks only when no LSP
client is attached at the time the buffer opens. If an LSP attaches later its
keymaps naturally overwrite these (last writer wins for buffer-local keymaps).
`LspDetach` is listened to on the buffer; when the last client leaves the
Swank fallbacks are re-registered.

`gR` (find callers) has no LSP equivalent and is always registered pointing to Swank.

| Keymap | When LSP attached | When no LSP |
|--------|-------------------|-------------|
| `gd` | LSP owns it | `client.find_definition(sym)` |
| `K` | LSP owns it | `client.describe(sym)` |
| `gr` | LSP owns it | `client.xref_references(sym)` |
| `<C-k>` | LSP owns it | `client.autodoc()` |
| `gR` | *(always Swank)* | `client.xref_calls(sym)` |

All other Swank keymaps (`<Leader>ee`, `<Leader>id`, REPL, compile, trace, …)
are unconditional — they have no LSP equivalents.

---

## blink.cmp source — `blink_source.lua`

Implements the blink.cmp `Source` interface. It has no direct vim.uv involvement;
it just calls `client.completions()` and maps the result to `CompletionItem[]`.

Prefix extraction: `ctx.line:sub(1, ctx.cursor[2])` (col is byte offset, 1-indexed).
Enabled only when `client.is_connected()`.

---

## Swank contribs loaded on connect

```
SWANK-ASDF
SWANK-REPL
SWANK-FUZZY
SWANK-ARGLISTS
SWANK-FANCY-INSPECTOR
SWANK-TRACE-DIALOG
SWANK-C-P-C
```
