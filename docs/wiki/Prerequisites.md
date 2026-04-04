# Prerequisites

Everything you need to install before using swank.nvim.

---

## Neovim

**Minimum:** Neovim 0.10  
**Recommended:** Neovim 0.13+ (used for development and CI)

swank.nvim uses `vim.uv` (libuv bindings), `vim.api.nvim_open_win` with the
`relative = "editor"` field, and `vim.diagnostic.set`. All of these are
available in 0.10; some behaviour is improved in 0.13.

No Vimscript compatibility layer is needed — this plugin is pure Lua.

---

## Quick start (autostart — recommended)

The default configuration automatically launches your CL implementation and
connects to Swank when you open a `.lisp` file. **You don't need to write any
startup scripts or start a server manually.**

All you need is a supported CL implementation and Quicklisp.

---

## Common Lisp implementation

| Implementation | Support | Notes |
|----------------|---------|-------|
| [SBCL](https://www.sbcl.org/) | ✅ Primary | Recommended. Fastest, best Swank coverage. |
| [CCL (Clozure CL)](https://ccl.clozure.com/) | ✅ Should work | Swank well-supported, slightly less tested |
| [ECL](https://ecl.common-lisp.dev/) | ⚠️ Partial | Embeddable; some Swank contribs limited |
| [ABCL](https://abcl.org/) | ⚠️ Partial | JVM-based; Swank works but can be slow to start |
| [CLISP](https://clisp.sourceforge.io/) | ❌ Not recommended | Swank support is minimal; REPL only |
| Allegro CL | 🔲 Untested | Commercial; Swank support exists in theory |

### Installing SBCL

**Linux (apt):**
```sh
sudo apt install sbcl
```

**Linux (pacman):**
```sh
sudo pacman -S sbcl
```

**macOS:**
```sh
brew install sbcl
```

**From source / prebuilt binaries:** https://www.sbcl.org/getting.html

To use a different implementation, set `autostart.implementation` in your config:

```lua
require("swank").setup({
  autostart = { implementation = "ccl" },  -- or "ecl", "abcl", "/usr/local/bin/sbcl", etc.
})
```

---

## Quicklisp

[Quicklisp](https://www.quicklisp.org/) is the standard CL package manager.
Install it once and swank.nvim will use it automatically to load Swank.

### One-time setup

```sh
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --load quicklisp.lisp \
     --eval '(quicklisp-quickstart:install)' \
     --eval '(ql:add-to-init-file)' \
     --quit
```

This installs Quicklisp to `~/quicklisp/` and adds an auto-load snippet to
`~/.sbclrc` so it's available in every SBCL session.

> **No Quicklisp?** SBCL bundles a copy of Swank via ASDF. swank.nvim will
> automatically fall back to `(require :swank)` if Quicklisp is not found.
> Note: the bundled Swank may be older and some contribs may not load.

---

## ASDF

[ASDF](https://asdf.common-lisp.dev/) is the de-facto build system for CL.

- **SBCL, CCL, ECL, ABCL**: bundled — no separate install needed
- Required for the `swank-asdf` contrib, which enables project-aware
  compilation (`:compile-and-load-file` on `.asd` systems)

---

## Advanced: connecting to an existing server

If you want to manage the Swank server yourself (remote machines, custom
setups, or `autostart.enabled = false`), start it from your CL image:

```lisp
(ql:quickload "swank" :silent t)
(swank:create-server :port 4005 :dont-close t)
```

Then connect from Neovim with `<Leader>lc`.

Port **4005** is the default for external servers. If you use autostart, the
plugin starts Swank on an ephemeral port (`:port 0`) and connects
automatically — no port configuration needed.

---

## Summary checklist

- [ ] Neovim 0.10+
- [ ] SBCL (or another supported implementation) on `$PATH`
- [ ] Quicklisp installed at `~/quicklisp/` (or bundled Swank available via ASDF)
