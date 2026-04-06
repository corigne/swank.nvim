# swank.nvim — Stretch Goals & Future Work

Items here are intentionally deferred past 1.0. They are good ideas but
out of scope for the initial release.

## Tests to add (coverage)
- Add unit tests covering transport._feed error branches, transport send/read error paths, and client._on_connect follow-ups to raise coverage >80

---

## Investigate Sextant LSP as an alternative backend over SWANK. 
- Discuss whether it make sense to create an alternative or even supplementary backend to SWANK using standard LSP implementations, targeting sextant, see: https://github.com/parenworks/sextant
- - Consider the implications for existing SWANK-specific features parity with SLIME, and what our plugin must still cover to bridge the gap. 
- - Evaluate the performance and feature parity of Sextant compared to SWANK, especially in areas like completions, arg hints, and diagnostics.
- - Consider the limits of Sextant's nvim plugin compared to swank.nvim.   
- - Make sure we can even connect to the running SWANK server in the sextant sbcl process, and if so, whether we can use it to support features that are not provided by the LSP.
- - Investigate the nvim plugin for Sextant as a possible reference implementation for the LSP backend, see if any code can be shared between the two implementations. See: https://github.com/parenworks/sextant.nvim
- - If all is reasonable, adopt sextant, create a plan to refactor the plugin such that the currently mocked LSP capabilities are maintained as a fallback when LSP is unavailable, but otherwise treat LSP capabilities as first-class; nvim-lspconfig should be respected.
