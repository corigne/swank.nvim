# Features

swank.nvim targets full SLIME feature parity via the Swank protocol. It is LSP-compatible:
navigation and completion delegate to any attached LSP server, and Swank covers the features
that fall outside the LSP spec.

## Implemented

| Feature | Notes |
|---------|-------|
| REPL | Pane or floating output buffer, input history |
| Eval | Top-level form, expression before cursor, region, interactive |
| Completion | blink.cmp and nvim-cmp sources; fuzzy and exact; yields to LSP when present |
| Autodoc | Arglist echo on `CursorHoldI` |
| Compiler diagnostics | `vim.diagnostic` integration; auto-compile-on-save when no LSP is attached |
| Eval status | In-flight notification; interrupt with `<Leader>eI` |
| Compile file | Compile, compile-and-load, load file |
| SLDB debugger | Floating window; restarts, frame inspection, eval-in-frame, stepping |
| Object inspector | Navigable parts, back/reinspect |
| Cross-reference | Callers, references, bindings, sets, macroexpands, specializes |
| Macro expansion | `macroexpand-1` and `macroexpand-all` |
| Disassembly | |
| Trace dialog | SWANK-TRACE-DIALOG |
| Profiling | |
| Thread management | |
| LSP-first navigation | `gd`, `K`, `gr`, `<C-k>` delegate to LSP; Swank fills the gap when no LSP is present |
| Autostart | Spawns a CL implementation + Quicklisp automatically |
| which-key integration | |

## Roadmap

- Compile region (compile a visual selection, not just a top-level form)
- Telescope and Trouble integration for xref and diagnostics
- Broader CL implementation testing (CCL, ECL, ABCL)
- Remote Swank server improvements (SSH tunnel helpers, connection profiles)
- Multiple simultaneous Swank connections
