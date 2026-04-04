# Contributing to swank.nvim

Thank you for your interest in contributing. This document covers the conventions, workflow, and quality standards expected for all contributions.

---

## Prerequisites

- Neovim ≥ 0.10 (0.13+ recommended)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) available in your Neovim data path
- [luarocks](https://luarocks.org/) with Lua 5.1 support (for coverage)
- A running Swank server for integration tests (SBCL + Quicklisp recommended)

Install the coverage tooling once:

```sh
luarocks install luacov --local --lua-version 5.1
luarocks install luacov-reporter-lcov --local --lua-version 5.1
```

---

## Running the test suite

```sh
make test          # unit tests only (no server required)
make test-integration  # integration tests (requires Swank on 127.0.0.1:4005)
make test-all      # both
make coverage      # unit tests + luacov report
```

The integration tests auto-skip when no server is reachable — `SWANK_PORT` overrides the default port.

---

## Code coverage requirements

**Every contribution must meet an 80 % line coverage floor. 100 % is the target.**

| Threshold | Meaning |
|-----------|---------|
| < 80 %    | Pull request will not be merged |
| 80 – 99 % | Acceptable; a comment explaining the uncovered lines is expected |
| 100 %     | Goal for all new modules |

Check your coverage before submitting:

```sh
make coverage
```

The report is printed to the terminal and written to `luacov.report.out`. Lines marked `0` in the report are uncovered — add tests for them or explain in the PR why coverage is not feasible (e.g. vim.uv TCP callbacks that require a live server, which belong in integration tests instead).

### What counts

- Unit tests (`tests/unit/`) count toward the coverage gate.
- Integration tests (`tests/integration/`) provide additional signal but are not counted in the gate because they require a live server in CI.
- UI modules (`lua/swank/ui/`) are excluded from the luacov run (they need a real Neovim window). Cover their logic through unit-testable helper functions extracted into the core modules.

---

## Writing tests

Tests use [plenary.nvim busted](https://github.com/nvim-lua/plenary.nvim#plenarybusted). Follow the patterns already established in `tests/unit/`.

```lua
describe("module.function", function()
  it("does the expected thing", function()
    assert.equals(expected, actual)
  end)
end)
```

- One `describe` block per public function or behaviour area.
- Name `it` blocks as plain-English sentences starting with a verb.
- Use real Neovim buffers/windows for cursor-dependent tests (see `client_spec.lua` for examples).
- Do not mock internal state unless it is genuinely impossible to exercise the real path.

### Unit vs integration

| Concern | Where |
|---------|-------|
| Pure logic: parsing, serialisation, helpers | `tests/unit/` |
| Neovim buffer/window/cursor behaviour | `tests/unit/` (real nvim API, headless) |
| TCP framing with fake callbacks | `tests/unit/` |
| Live Swank RPC round-trips | `tests/integration/` |
| UI floating windows | Integration or manual only |

---

## Code style

- Pure Lua — no Vimscript, no Python, no Fennel.
- Neovim 0.10+ APIs throughout (`vim.uv`, `vim.api`, `vim.diagnostic`, `vim.ui`).
- All public functions have `---@param` / `---@return` LuaLS annotations.
- Prefer explicit `nil` checks over truthiness where the distinction matters.
- No `print()` in production code — use `vim.notify` with an appropriate log level.
- All TCP/libuv callbacks must call UI code inside `vim.schedule()`.
- Keep editor-context gathering (cursor position, visual selection, `vim.ui.input`) in `keymaps.lua`. Client functions take plain strings.

---

## Submitting a pull request

swank.nvim uses **GitHub Flow**: all work happens on short-lived branches that are opened as PRs and squash-merged into `main`.

### Branch naming

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feature/<short-description>` | `feature/sldb-eval-in-frame` |
| Bug fix | `fix/<short-description>` | `fix/inspector-part-index` |
| Docs | `docs/<short-description>` | `docs/keybindings-table` |
| Chore / infra | `chore/<short-description>` | `chore/update-ci-node` |

Branch directly off `main` and keep the branch focused on one thing.

### PR checklist

1. Branch off `main` with an appropriate `feature/`, `fix/`, `docs/`, or `chore/` prefix.
2. Make your changes with tests.
3. Run `make coverage` and confirm the 80 % gate is met.
4. Run `make test` to confirm nothing regressed.
5. Open a pull request with a clear description of what changed and why.
6. CI must be green before merge — unit tests, coverage, and (where possible) integration tests.

PRs are **squash-merged** to keep `main`'s history clean and linear. Write your PR title as you would a commit subject line (imperative mood, ≤ 72 chars).

If coverage drops below 80 % for any file you touched, the PR description must explain why and propose a path to closing the gap.

---

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md) (Phase 6, in progress) for a full walkthrough of how the transport, protocol, client, UI, and keymap layers fit together.
