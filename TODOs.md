# swank.nvim — Stretch Goals & Future Work

Items here are intentionally deferred past 1.0. They are good ideas but
out of scope for the initial release.

---

## Arg completion hints (snippet-style)

When a completion item is accepted, insert a snippet or virtual-text hint
showing the lambda list for the selected symbol — similar to what LSP
servers provide for function signatures.

**Desired UX:** accepting `(mapcar` expands to `(mapcar function list)` with
the arguments as tab-stops (if a snippet engine is available) or as
dismissible virtual text (as a fallback).

**Approach:**
- On `CompletionItemAccepted` (or equivalent blink/nvim-cmp callback),
  fire `swank:operator-arglist` for the accepted symbol.
- If a snippet engine is active (LuaSnip, nvim-snippy, blink native),
  build a snippet string from the arglist and expand it.
- If no snippet engine is present, render the arglist as extmark virtual
  text to the right of the cursor; clear it on the next insert or `<Esc>`.
- The `item.labelDetails.description` field can carry a short arglist
  preview in the completion menu itself (no engine required).

**Blockers / considerations:**
- `swank:operator-arglist` is async; need to handle the race between
  acceptance and the RPC round-trip gracefully.
- Snippet engine detection should be soft (`pcall`) — never a hard
  dependency.
- blink.cmp and nvim-cmp have different post-accept hook APIs; needs
  separate integration paths.

---

## Live diagnostics

Show compiler errors/warnings inline (like LSP diagnostics) without
requiring an explicit eval.

**Note:** Swank has no push-based lint protocol. SBCL only reports
conditions when code is compiled or evaluated. True live diagnostics would
require periodic background compilation of the buffer, which is expensive
and changes semantics. This is a hard problem; consider only after
evaluating whether background `compile-string` is acceptable.

---

## omnifunc fallback

Implement `vim.bo.omnifunc` using `swank:completions` so that any
completion plugin honouring `omnifunc` gets basic symbol completion
without requiring a dedicated source.

**Note:** `omnifunc` is synchronous; the RPC must complete before the
callback returns. Use `vim.wait` or a coroutine-based approach. Document
clearly that this blocks the event loop briefly.

---


## Tests to add (coverage)
- Add unit tests covering transport._feed error branches, transport send/read error paths, and client._on_connect follow-ups to raise coverage >80