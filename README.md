# swank.nvim

[![CI](https://github.com/corigne/swank.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/corigne/swank.nvim/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen?style=flat-square&logo=lua)](https://github.com/corigne/swank.nvim/actions/workflows/ci.yml)

A modern, pure-Lua Common Lisp development environment for Neovim, built on the [Swank](https://github.com/slime/slime/blob/master/swank/backend.lisp) protocol.

> **Status: stable.** v1.0 release. Testing and issue submission welcome!

---

## Why?

I wanted a first-class Common Lisp development experience in Neovim without learning Emacs.
The existing options are either limited by Vimscript or no longer maintained.

| Plugin | Status | Notes |
|---|---|---|
| vlime | Active | Vimscript-based; limited Neovim integration |
| nvlime | **Archived** | Good foundation, but unmaintained with unresolved bugs |
| conjure | Active | Multi-language; eval-only for CL, no SLDB/inspector/xref |
| sextant.nvim | Active | LSP-based CL frontend; targets features covered by the LSP spec |

swank.nvim is a drop-in replacement for vlime/nvlime covering the full SLIME feature set:
interactive REPL, eval (top-level, region, expression), SLDB debugger, object inspector,
cross-reference, macro expansion, disassembly, tracing, profiling, thread management, and
compiler diagnostics. It is LSP-compatible -- navigation and completion delegate to any attached
LSP server, and Swank covers the features that fall outside the LSP spec.

See the [wiki](https://github.com/corigne/swank.nvim/wiki) for the full feature list and roadmap.

## Prerequisites

### Neovim

**Neovim 0.10+** required. 0.13+ recommended (used for development and testing).

### Quick start (autostart; recommended)

The default configuration automatically launches sbcl and connects to Swank when you open a `.lisp` file. 
**You don't need to write any startup scripts or start a server manually.**

All you need is:

1. A Common Lisp implementation installed (e.g. `sbcl`)
2. [Quicklisp](https://www.quicklisp.org/) installed in the default location (`~/quicklisp/`)

**Install SBCL:**

```sh
# Debian/Ubuntu
sudo apt install sbcl

# Arch
sudo pacman -S sbcl

# macOS
brew install sbcl
```

**Install Quicklisp** (one-time setup, any implementation):

```sh
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --load quicklisp.lisp \
     --eval '(quicklisp-quickstart:install)' \
     --eval '(ql:add-to-init-file)' \
     --quit
```

That's it. Open a `.lisp` file in Neovim and swank.nvim handles the rest.

> **No Quicklisp?** SBCL bundles Swank via ASDF. swank.nvim will automatically
> fall back to `(require :swank)` if Quicklisp is not found.

### CL implementation support

| Implementation | Support | Notes |
|----------------|---------|-------|
| [SBCL](https://www.sbcl.org/) | ✅ Primary | Recommended. Best SWANK support. |
| [CCL (Clozure CL)](https://ccl.clozure.com/) | ⚠️ Untested, should work | SWANK is well-supported |
| [ECL](https://ecl.common-lisp.dev/) | ⚠️ Untested, Likely Partial Compatibility | SWANK works; some features limited |
| [ABCL](https://abcl.org/) | ⚠️ Untested, Likely Partial Compatibility | Runs on JVM; SWANK can be quirky |
| [CLISP](https://clisp.sourceforge.io/) | ❌ Untested, Not recommended | SWANK support is minimal |

To use a different implementation, set `autostart.implementation` in your config:

```lua
opts = { autostart = { implementation = "ccl" } }  -- or "ecl", "abcl", "/usr/local/bin/sbcl", etc.
```

### Advanced: connecting to an existing server

If you want to manage the SWANK server yourself (remote machines, custom setups,
`autostart.enabled = false`), start it from your CL image:

```lisp
(ql:quickload "swank" :silent t)
(swank:create-server :port 4005 :dont-close t)
```

Then connect from Neovim with `<Leader>lc`.

---

## Installation

**lazy.nvim:**

```lua
{ "corigne/swank.nvim" }
```

Pass any options via `opts`. See the [Configuration wiki page](https://github.com/corigne/swank.nvim/wiki/Configuration) for the full reference.

**Requires:** Neovim 0.10+. See [Prerequisites](#prerequisites) above.

## Documentation
The [wiki](https://github.com/corigne/swank.nvim/wiki) contains more detailed documentation, guides and common troubleshooting steps.

### vimdocs
See `:help swank.nvim` after installation.

## Completions

See **[the wiki](https://github.com/corigne/swank.nvim/wiki/Completions)** for detailed completion instructions.

## Keybinds

Keybinds can be introspected with snacks.nvim's keybind tool (`<Leader> sk` by default)
See [the wiki](https://github.com/corigne/swank.nvim/wiki/Keybindings) for a full list of keybindings and how to customize them.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)

## Acknowledgements

- [SLIME](https://github.com/slime/slime) 
- [Swank](https://github.com/slime/slime/blob/master/swank.lisp)
- [vlime](https://github.com/vlime/vlime) and [nvlime](https://github.com/monkoose/nvlime) reference implementations for Vim and Neovim, thank you for paving the way
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [blink.cmp](https://github.com/Saghen/blink.cmp)

## License

MIT
