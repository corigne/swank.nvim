# swank.nvim — Stretch Goals & Future Work

Items here are intentionally deferred past 1.0. They are good ideas but
out of scope for the initial release.

## Tests to add (coverage)
- ~~Add unit tests covering transport._feed error branches, transport send/read error paths, and client._on_connect follow-ups to raise coverage >80~~ ✓ Done in PR #21 — coverage is at 92.54% (gate: 80%).

---

## Sextant LSP integration — adopted

Sextant (https://github.com/parenworks/sextant) is an actively maintained Common Lisp LSP
server. swank.nvim now treats any attached LSP client as first-class and uses Swank only as
a fallback when no LSP is present.

**What changed:**
- `gd`, `K`, `gr`, `gR`, `<C-k>` are registered as Swank fallbacks only when no LSP is attached. If an LSP is present its own keymaps take precedence; the Swank bindings are restored via `LspDetach` when the last client leaves.
- All three completion sources (`blink_source`, `sources/blink`, `sources/nvim_cmp`) disable themselves when an LSP is attached, preventing duplicate completions.
- Detection is generic: any attached LSP client triggers LSP-first behaviour, not just Sextant.
- Swank retains exclusive ownership of: REPL, eval, compile, trace, debug (SLDB), inspector, apropos — none of these have LSP equivalents.

**Setup:** configure Sextant (or any CL LSP) via nvim-lspconfig as normal. swank.nvim detects it automatically.
