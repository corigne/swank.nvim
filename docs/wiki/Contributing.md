# Contributing

Thank you for contributing to swank.nvim!

---

## Before you start

- Check [open issues](https://github.com/corigne/swank.nvim/issues) to avoid
  duplicating work
- For significant features, open an issue to discuss the approach first
- Read the [Architecture](Architecture) page so you understand which layer
  owns which concerns

---

## Development setup

```sh
git clone https://github.com/corigne/swank.nvim
cd swank.nvim
# plenary.nvim must be on the runtimepath for tests
# either install normally with your plugin manager, or:
git clone https://github.com/nvim-lua/plenary.nvim /tmp/plenary
```

Run tests:

```sh
make test              # unit tests only (no server needed)
make coverage          # unit tests + luacov coverage gate
make test-integration  # requires live Swank on 127.0.0.1:4005
```

---

## Coverage floor: 80%

The CI pipeline enforces `MIN_COV=80`. A PR that drops coverage below this
threshold will not be merged.

- New functions need unit tests
- UI modules (`lua/swank/ui/`) and `keymaps.lua` are **excluded** from
  the gate; they require a real editor window and cannot be unit-tested
- Logic in excluded files should be extracted into helpers that can be tested

Check your coverage before pushing:

```sh
make coverage
```

---

## Test placement

| What | Where |
|------|-------|
| Protocol parsing / serialisation | `tests/unit/protocol_spec.lua` |
| Transport framing | `tests/unit/transport_spec.lua` |
| Client RPC helpers, dispatch | `tests/unit/client_spec.lua` |
| REPL layout logic | `tests/unit/repl_spec.lua` |
| Any function that requires a buffer or window | `tests/unit/` (headless nvim API is available) |
| Live server round-trips | `tests/integration/` |

Headless tests run via `nvim --headless` with `tests/minimal_init.lua`.
They have access to `vim.api`, `vim.fn`, and so on, but not a real display.

---

## Writing unit tests

Tests use [plenary.nvim busted](https://github.com/nvim-lua/plenary.nvim#plenarybusted).

### Mock transport pattern

```lua
local client = require("swank.client")
local protocol = require("swank.protocol")

describe("my feature", function()
  local sent = {}

  before_each(function()
    sent = {}
    client._test_inject({
      send       = function(_, payload) table.insert(sent, payload) end,
      disconnect = function() end,
    })
  end)

  after_each(function()
    client._test_reset()
  end)

  it("sends the right form", function()
    client:my_function("arg")
    assert.is_not_nil(sent[1])
    local parsed = protocol.parse(sent[1])
    assert.equals(":emacs-rex", parsed[1])
  end)
end)
```

### Firing fake server responses

```lua
-- After calling client:something(), fire the :return response
local id = ... -- captured from parsed sent frame
protocol.dispatch({ ":return", { ":ok", expected_result }, id })
```

### Don't stub out `nvim_open_win` permanently

Always save and restore:

```lua
local orig_open = vim.api.nvim_open_win
after_each(function()
  vim.api.nvim_open_win = orig_open
end)
```

---

## Code style

- **Pure Lua** — no Vimscript, Python, Fennel
- **Neovim 0.10+ only** — no Vim compatibility shims
- `vim.uv` for async I/O; **wrap all Neovim API calls in `vim.schedule()`**
  when calling from a `vim.uv` callback
- `---@param` / `---@return` LuaLS annotations on all public functions
- `vim.notify` for user-visible messages, not `print`
- Editor context (cursor, visual marks, `vim.ui.*`) stays in `keymaps.lua`
- New modules should have a `M._test_inject` / `M._test_reset` pattern
  if they hold stateful connections or singletons

---

## Branch and PR conventions

- Branch prefix: `feature/`, `fix/`, `docs/`, `chore/`
- Target `main`
- Squash-merge only
- PR title should be imperative: "Add fuzzy completion source", "Fix REPL
  auto-open on float layout"
- CI must be green (unit tests + coverage gate)

---

## What needs help

See the [open issues](https://github.com/corigne/swank.nvim/issues) and
the plan milestones:

| Phase | Status |
|-------|--------|
| Transport + Protocol + Eval | ✅ |
| Completion + Autodoc | ✅ |
| Debugger (SLDB) | ✅ |
| Inspector + XRef | ✅ |
| Compiler notes | ✅ |
| Trace dialog | ✅ |
| Full vimdoc | 🚧 Planned |
