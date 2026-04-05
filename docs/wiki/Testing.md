# Testing

swank.nvim uses [plenary.nvim busted](https://github.com/nvim-lua/plenary.nvim#plenarybusted)
for both unit and integration tests.

---

## Running tests

```sh
make test              # unit tests (headless, no server needed)
make test-integration  # integration tests (requires live Swank)
make coverage          # unit tests + luacov report + 80% gate
```

---

## Unit tests

Location: `tests/unit/`

Run headless, with no display or server needed. Neovim's full Lua API is available
(`vim.api`, `vim.fn`, `vim.uv` stubs, etc.).

### Test files

| File | What it covers |
|------|---------------|
| `protocol_spec.lua` | S-expression parser and serialiser (round-trip, edge cases, malformed input) |
| `transport_spec.lua` | Message framing: `_feed()` with partial frames, multiple frames, split boundaries |
| `client_spec.lua` | RPC helpers (`_is_symbol_like`, `_plist`), cursor form extraction, callback dispatch |
| `repl_spec.lua` | REPL adaptive layout logic: `effective_pos`, `resolve_size`, auto-open behaviour |
| `inspector_spec.lua` | Inspector content rendering: section parsing, action list display |
| `sldb_spec.lua` | SLDB buffer rendering: frame formatting, restart list display |
| `trace_spec.lua` | Trace dialog: `parse_entry` logic, `push_entries`/`set_specs` state management |
| `notes_spec.lua` | Compiler notes / diagnostics helpers: note-to-diagnostic conversion |
| `xref_spec.lua` | Cross-reference location parsing (`_extract_location`) and quickfix list building (`_refs_to_qflist`) |
| `init_spec.lua` | Plugin init module: `setup()` option merging, `attach()` autocmd registration |

### Minimal init

Tests run with `tests/minimal_init.lua`, which adds only plenary and swank.nvim
to the runtimepath. No user config is loaded.

### Coverage init

`tests/coverage_init.lua` is identical but also loads luacov for instrumented runs.

---

## Integration tests

Location: `tests/integration/`

Require a live Swank server on `127.0.0.1:4005`. Tests are automatically
**skipped** if no server is reachable, so they never fail in CI without one.

To run locally:

```sh
sbcl --load tests/start-swank.lisp &
make test-integration
```

### Test files

| File | What it covers |
|------|---------------|
| `connection_spec.lua` | Connect, `swank:connection-info`, disconnect, reconnect |
| `eval_spec.lua` | `eval-and-grab-output`, error responses, package switching |
| `introspection_spec.lua` | `describe-symbol`, `apropos-list-for-emacs`, `operator-arglist` |
| `compile_spec.lua` | `compile-string-for-emacs`, `:compilation-result` structure |

---

## Coverage

Coverage is tracked with [luacov](https://github.com/lunarmodules/luacov).

```sh
make coverage
```

This runs the unit tests with luacov instrumentation and then checks that
the total line coverage is at least **80%**.

### Excluded from coverage

The following paths are excluded from the gate (they require a real display
or network and cannot be meaningfully unit-tested):

- `lua/swank/ui/` — floating windows, split buffers
- `lua/swank/keymaps.lua` — cursor reads, visual marks, `vim.ui.*` prompts

Logic in these files that is worth testing should be extracted to a helper
function in a non-excluded module.

### Checking coverage locally

```sh
make coverage
# See the summary:
cat luacov.report.out | grep -A2 "^Summary"
```

---

## Mock transport pattern

The mock transport lets unit tests exercise `client.lua` without a TCP connection.

```lua
local sent = {}
local mock_transport = {
  send       = function(_, payload) table.insert(sent, payload) end,
  disconnect = function() end,
}

before_each(function()
  client._test_inject(mock_transport)
end)

after_each(function()
  client._test_reset()
end)
```

`client._test_inject(t)` sets the internal transport and marks state as
`"connected"`. `client._test_reset()` clears all state and resets `msg_id` to 0.

---

## Dispatching fake server responses

After calling a client function that registers a callback, fire the response:

```lua
-- 1. Call the client function
client:eval_toplevel("(+ 1 2)", function(result)
  received = result
end)

-- 2. Parse the outgoing frame to get the msg-id
local parsed = protocol.parse(sent[#sent])
local id = parsed[5]  -- msg-id is always the 5th element of :emacs-rex

-- 3. Fire the :return event
protocol.dispatch({ ":return", { ":ok", "3" }, id })

-- 4. Assert
assert.equals("3", received)
```

---

## Adding new tests

1. Place the file in `tests/unit/` (or `tests/integration/` for server-dependent tests)
2. Follow existing naming: `module_spec.lua`
3. Use `before_each` / `after_each` to set up and tear down state
4. Always restore any global stubs (`vim.api.nvim_open_win`, `vim.cmd`, etc.)
5. Run `make coverage` before pushing to verify the gate still passes
