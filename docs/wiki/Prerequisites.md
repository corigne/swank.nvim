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

## Common Lisp implementation

swank.nvim connects over TCP to a running [Swank](https://github.com/slime/slime)
server. Swank is a protocol library included with SLIME and usable standalone.
Any implementation that can load Swank should work.

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

---

## Quicklisp (recommended)

[Quicklisp](https://www.quicklisp.org/) is the standard CL package manager.
It's the easiest way to install and update Swank.

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

### Starting Swank via Quicklisp

Create a file (e.g. `~/.config/swank/start.lisp` or `./start-swank.lisp`):

```lisp
(ql:quickload "swank" :silent t)
(swank:create-server :port 4005 :dont-close t)
```

Start it:
```sh
sbcl --load ~/.config/swank/start.lisp
```

Then connect from Neovim with `<Space>sc`.

### Using autostart

If `autostart = true` in your swank.nvim config, the plugin will run
`sbcl --load <swank_script>` for you when you open a Lisp file.
Set `swank_script` to the path of your start file:

```lua
require("swank").setup({
  autostart    = true,
  swank_script = vim.fn.expand("~/.config/swank/start.lisp"),
  sbcl_cmd     = "sbcl",
})
```

---

## Without Quicklisp

SBCL ships with a bundled copy of Swank. You can start it without Quicklisp:

```lisp
;; start-swank-no-ql.lisp
(require :asdf)
(require :swank)
(swank:create-server :port 4005 :dont-close t)
```

Note: the bundled Swank may be older than the Quicklisp version and some
contribs (`swank-fuzzy`, `swank-arglists`, etc.) may not load.

---

## ASDF

[ASDF](https://asdf.common-lisp.dev/) is the de-facto build system for CL.

- **SBCL, CCL, ECL, ABCL**: bundled — no separate install needed
- Required for the `swank-asdf` contrib, which enables project-aware
  compilation (`:compile-and-load-file` on `.asd` systems)

---

## Port availability

The default Swank port is **4005**. Make sure nothing else is bound to it.
To use a different port, pass `:port` to `swank:create-server` and set
`port` in your swank.nvim config:

```lua
require("swank").setup({ port = 14005 })
```

---

## Summary checklist

- [ ] Neovim 0.10+
- [ ] SBCL (or another supported implementation) on `$PATH`
- [ ] Quicklisp installed (or bundled Swank available)
- [ ] A `start-swank.lisp` file, or `autostart` configured with `swank_script`
- [ ] Port 4005 free (or configured to an available port)
