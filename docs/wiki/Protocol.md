# Protocol

Internal reference for contributors working on `transport.lua` and `protocol.lua`.

---

## Message framing

Every Swank message (in both directions) is prefixed with a 6-character
zero-padded hexadecimal byte count:

```
000047(:emacs-rex (swank:connection-info) "COMMON-LISP-USER" :repl-thread 1)
^^^^^^ ──────────────────────────────────────────────────────────────────────
 hex   payload (S-expression string)
 len
```

The 6-byte header `000047` = 71 decimal = length of the payload in bytes.

swank.nvim's `transport.lua` handles framing:
- **Send:** prepend `string.format("%06x", #payload)` before writing to TCP
- **Receive:** accumulate bytes in a buffer; once `tonumber(buf:sub(1,6), 16)`
  bytes are available after the header, fire `on_message` and consume

---

## S-expression subset

Swank communicates in Common Lisp S-expressions, but only a small subset appears
in actual messages:

| Syntax | Lua representation |
|--------|--------------------|
| `(:keyword "str" 42 NIL T)` | `{ ":keyword", "str", 42, false, true }` |
| `NIL` | `false` or `{}` (empty list) |
| `T` | `true` |
| `:keyword` | `":keyword"` (string with leading colon) |
| `symbol` | `"symbol"` (string without colon) |
| `"string"` | `"string"` |
| `42`, `-1` | number |
| nested lists | nested Lua tables |

---

## Common event shapes

### `:return` (response to `:emacs-rex`)

```lisp
(:return (:ok result-value) msg-id)
(:return (:abort condition-string) msg-id)
```

Lua dispatch key: `"return"`.

### `:write-string` (REPL output)

```lisp
(:write-string "output text" :repl-result)
```

Lua dispatch key: `"write-string"`.

### `:presentation-start` / `:presentation-end`

```lisp
(:presentation-start presentation-id)
(:presentation-end   presentation-id)
```

### `:debug` (SLDB activate)

```lisp
(:debug thread-id level
  ("condition message" "extra info" NIL)
  (("Use value" "use a different value" T) ...)  ; restarts
  (("0: frame desc" ...)  ...)                   ; backtrace
  NIL)
```

Lua dispatch key: `"debug"`.

### `:debug-return` (SLDB dismiss)

```lisp
(:debug-return thread-id level NIL)
```

### `:ping` / `:pong`

```lisp
(:ping thread-id tag)
(:pong thread-id tag)
```

The client must respond to every `:ping` with a matching `:pong`.

---

## Outgoing: `:emacs-rex`

```lisp
(:emacs-rex
  (swank:some-function arg1 arg2)  ; form
  "COMMON-LISP-USER"               ; package
  :repl-thread                     ; thread
  42)                              ; msg-id (incrementing integer)
```

The client increments `msg_id` for each call and stores a callback keyed by
the id. When `:return` arrives with the same id, the callback fires and the
entry is removed.

---

## Swank contribs

On connect, swank.nvim loads a standard set of contribs using
`swank:load-contribs`:

```lisp
(swank:load-contribs
  '(swank-asdf swank-repl swank-fuzzy swank-arglists
    swank-fancy-inspector swank-trace-dialog swank-c-p-c))
```

Some functions (`swank-repl:listener-eval`, `swank-fuzzy:fuzzy-completions`, …)
are only available after their contrib is loaded.

---

## References

- [SLIME source — swank.lisp](https://github.com/slime/slime/blob/master/swank.lisp)
- [SLIME protocol notes](https://github.com/slime/slime/blob/master/doc/slime.texi)
- [nvlime protocol commentary](https://github.com/HiPhish/nvlime) (archived, useful reference)
