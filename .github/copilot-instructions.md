# swank.nvim — Copilot Instructions

## Project overview

**swank.nvim** is a pure-Lua, Neovim-native Common Lisp development environment
built on the [Swank](https://github.com/slime/slime) protocol. It aims for full
SLIME feature parity: REPL, eval, completion, introspection, xref, tracing,
debugging, and compiler notes — all using modern Neovim APIs.

- **Repo:** `corigne/swank.nvim`
- **Language:** Lua (Neovim plugin, Lua 5.1 / LuaJIT)
- **Neovim requirement:** 0.10+ (0.13+ recommended)
- **Test framework:** plenary.nvim busted
- **Coverage tool:** luacov

---

## Repository layout

```
lua/swank/
  init.lua          -- setup(), attach(), default_config
  client.lua        -- all RPC functions; the main module agents touch
  protocol.lua      -- S-expression parser/serialiser + event dispatcher
  transport.lua     -- vim.uv TCP transport + message framing
  keymaps.lua       -- buffer-local keymap registration; editor context only
  blink_source.lua  -- blink.cmp completion source (swank:completions)
  ui/
    repl.lua        -- REPL output buffer; auto-opens on output
    inspector.lua   -- Object inspector floating window
    trace.lua       -- Trace dialog
    xref.lua        -- Cross-reference quickfix
    sldb.lua        -- Debugger (SLDB) floating window
    notes.lua       -- Compiler notes → vim.diagnostic

tests/
  unit/             -- headless plenary busted tests (no server needed)
  integration/      -- live Swank server tests
  minimal_init.lua  -- minimal Neovim init for unit tests
  coverage_init.lua -- same but with luacov instrumentation

.github/
  workflows/ci.yml  -- unit tests, coverage gate, integration tests
  copilot-instructions.md  -- this file
```

---

## Architecture: layer responsibilities

| Layer | File | Responsibility |
|-------|------|---------------|
| Transport | `transport.lua` | Raw TCP via `vim.uv`; 6-hex-byte length-prefixed framing; `connect()`, `send()`, `disconnect()` |
| Protocol | `protocol.lua` | S-expression parse/serialise; `dispatch()` fires event handlers registered with `protocol.on()` |
| Client | `client.lua` | All Swank RPC: `rex()` low-level call, named high-level ops (`eval_toplevel`, `describe`, `xref_calls`, …); holds `connection_state`, `callbacks`, `current_package` |
| Keymaps | `keymaps.lua` | Resolves cursor position, visual selection, `vim.ui.input` prompts; calls client with plain strings; also registers LSP-compatible keymaps (`gd`, `K`, `gr`, `gR`, `<C-k>`) |
| UI | `ui/*.lua` | Display only: floating windows, side panels, quickfix. UI modules are excluded from the coverage gate |
| Init | `init.lua` | `setup(opts)` merges config; `attach(bufnr)` calls `keymaps.attach` and optionally `start_and_connect` |

**Golden rule:** editor context (cursor, visual marks, `vim.ui`) belongs in
`keymaps.lua`. `client.lua` receives only plain Lua strings.

---

## Key patterns

### Mock transport for unit tests

```lua
local function make_mock_transport()
  local sent = {}
  local t = {
    send        = function(self, payload) table.insert(sent, payload) end,
    disconnect  = function(self) self._closed = true end,
    _closed     = false,
  }
  return t, sent
end

-- Inject and reset
client._test_inject(mock)
-- ... test ...
client._test_reset()
```

### Decoding sent frames in tests

The real transport prepends a 6-char hex length prefix. The mock does NOT.
Decode a captured sent frame directly:

```lua
local parsed = protocol.parse(sent[#sent])
-- parsed = { ":emacs-rex", form, pkg, t, id }
local id = parsed[5]
```

### Firing fake Swank responses

```lua
protocol.dispatch({ ":return", { ":ok", result_value }, id })
```

### Test hooks in client.lua

- `M._test_inject(fake_transport)` — sets transport + state to "connected"
- `M._test_reset()` — clears all state (transport, callbacks, package, msg_id)
- `M.get_package()` — returns `current_package` (exposed for blink_source)

---

## REPL adaptive layout

`ui/repl.lua` `effective_pos("auto", size)`:
1. `resolve_size(size, vim.o.columns) >= 80` → `"right"` vertical split
2. `resolve_size(size, vim.o.lines) >= 12` → `"bottom"` horizontal split
3. otherwise → `"float"`

`resolve_size(size, total)`: if `size <= 1` treat as fraction, else as fixed int.

---

## blink.cmp completion source

`lua/swank/blink_source.lua` implements the blink.cmp source interface:
- `M:enabled()` — returns `client.is_connected()`
- `M:get_completions(ctx, callback)` — extracts CL symbol prefix from
  `ctx.line:sub(1, ctx.cursor[2])`, calls `swank:completions`, maps to
  `CompletionItem` list

Register in blink.cmp opts:
```lua
providers = { swank = { name = "Swank", module = "swank.blink_source" } }
per_filetype = { lisp = { "swank", "buffer" } }
```

---

## Contributing guidelines

> **Always read CONTRIBUTING.md before making changes.**

### Coverage floor: 80% (gate enforced in CI)

- `make coverage` runs luacov over unit tests and exits 1 if total < 80%
- CI runs `make coverage` — a failing gate blocks merge
- `lua/swank/ui/` and `keymaps.lua` are **excluded** from the gate (require
  a real editor window; logic is tested via exported helper functions)
- New modules must have tests. Uncoverable lines (e.g. live TCP callbacks)
  go in `tests/integration/`, not unit tests

### Test placement

| What | Where |
|------|-------|
| Pure logic, helpers, RPC dispatch | `tests/unit/` |
| Neovim buffer/window/cursor | `tests/unit/` (headless nvim API) |
| Live Swank round-trips | `tests/integration/` |
| Floating windows / real UI | Integration or manual only |

### Code style

- Pure Lua — no Vimscript, Python, or Fennel
- `vim.uv` for async I/O; all UI calls inside `vim.schedule()`
- `---@param` / `---@return` LuaLS annotations on all public functions
- `vim.notify` (not `print`) for user-visible messages
- Editor-context input (cursor, selection, prompts) stays in `keymaps.lua`

### Commands

```sh
make test           # unit tests
make test-integration  # requires live Swank on 127.0.0.1:4005
make coverage       # unit tests + luacov gate
make badge          # update README coverage badge
```

### Branch naming

`feature/`, `fix/`, `docs/`, `chore/` prefixes off `main`. Squash-merge only.

---

## Common pitfalls

- `require("swank").config` is `{}` in test context — always use safe fallbacks
  like `(c and c.ui and c.ui.repl) or defaults`
- `vim.wo[win]` crashes if the window ID is fake (test stub returns an int) —
  always guard with `vim.api.nvim_win_is_valid(win)`
- `vim.api.nvim_open_win = nil` in `after_each` nukes it globally — save and
  restore: `local orig = vim.api.nvim_open_win; ...; vim.api.nvim_open_win = orig`
- The mock transport does NOT prepend a length prefix — decode with
  `protocol.parse(sent[n])` not `protocol.parse(sent[n]:sub(7))`
- `swank:completions` returns `{{"comp1","comp2",...}, "longest-prefix"}` —
  the completion list is at `result[2][1]`, not `result[2]`
