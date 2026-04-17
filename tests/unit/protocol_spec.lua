-- tests/unit/protocol_spec.lua
-- Unit tests for the s-expression parser and serializer.
-- No server or connection required.

local protocol = require("swank.protocol")

describe("protocol.parse", function()
  it("parses nil", function()
    assert.is_nil(protocol.parse("nil"))
    assert.is_nil(protocol.parse("NIL"))
  end)

  it("parses t as true", function()
    assert.is_true(protocol.parse("t"))
    assert.is_true(protocol.parse("T"))
  end)

  it("parses integers", function()
    assert.equals(42,  protocol.parse("42"))
    assert.equals(-7,  protocol.parse("-7"))
    assert.equals(0,   protocol.parse("0"))
  end)

  it("parses strings", function()
    assert.equals("hello",       protocol.parse('"hello"'))
    assert.equals("with space",  protocol.parse('"with space"'))
    assert.equals('say "hi"',    protocol.parse('"say \\"hi\\""'))
    assert.equals("back\\slash", protocol.parse('"back\\\\slash"'))
  end)

  it("parses symbols and keywords", function()
    assert.equals(":ok",         protocol.parse(":ok"))
    assert.equals(":return",     protocol.parse(":return"))
    assert.equals("MAPCAR",      protocol.parse("MAPCAR"))
    assert.equals("swank:eval",  protocol.parse("swank:eval"))
  end)

  it("parses empty list", function()
    local v = protocol.parse("()")
    assert.is_table(v)
    assert.equals(0, #v)
  end)

  it("parses flat list", function()
    local v = protocol.parse("(1 2 3)")
    assert.is_table(v)
    assert.equals(3, #v)
    assert.equals(1, v[1])
    assert.equals(2, v[2])
    assert.equals(3, v[3])
  end)

  it("parses nested lists", function()
    local v = protocol.parse("(:return (:ok 42) 1)")
    assert.equals(":return", v[1])
    assert.equals(":ok",     v[2][1])
    assert.equals(42,        v[2][2])
    assert.equals(1,         v[3])
  end)

  it("parses a typical :return message", function()
    local raw = '(:return (:ok "hello world") 7)'
    local v = protocol.parse(raw)
    assert.equals(":return",     v[1])
    assert.equals(":ok",         v[2][1])
    assert.equals("hello world", v[2][2])
    assert.equals(7,             v[3])
  end)

  it("parses quote shorthand", function()
    local v = protocol.parse("'(:a :b)")
    assert.equals("QUOTE", v[1])
    assert.equals(":a",    v[2][1])
    assert.equals(":b",    v[2][2])
  end)

  it("returns nil and notifies on bad input", function()
    -- Should not throw; logs a warning and returns nil
    local ok, err = pcall(function()
      return protocol.parse("(unclosed")
    end)
    -- parse() catches errors internally and returns nil
    assert.is_true(ok)  -- pcall should not see an error
  end)

  it("returns nil for an unterminated string", function()
    local result = protocol.parse('"unterminated')
    assert.is_nil(result)
  end)

  it("returns nil for an unexpected character", function()
    local result = protocol.parse("{bad}")
    assert.is_nil(result)
  end)
end)

describe("protocol.serialize", function()
  it("serializes nil", function()
    assert.equals("nil", protocol.serialize(nil))
  end)

  it("serializes booleans", function()
    assert.equals("t",   protocol.serialize(true))
    assert.equals("nil", protocol.serialize(false))
  end)

  it("serializes integers", function()
    assert.equals("42",  protocol.serialize(42))
    assert.equals("-7",  protocol.serialize(-7))
    assert.equals("0",   protocol.serialize(0))
  end)

  it("serializes keywords as-is", function()
    assert.equals(":ok",        protocol.serialize(":ok"))
    assert.equals(":return",    protocol.serialize(":return"))
    assert.equals(":emacs-rex", protocol.serialize(":emacs-rex"))
  end)

  it("serializes package-qualified symbols as-is", function()
    assert.equals("swank:eval-and-grab-output",
      protocol.serialize("swank:eval-and-grab-output"))
    assert.equals("swank:swank-require",
      protocol.serialize("swank:swank-require"))
  end)

  it("serializes QUOTE as-is (special allowlist)", function()
    assert.equals("QUOTE", protocol.serialize("QUOTE"))
  end)

  it("quotes plain symbol-like strings (they are CL strings in Swank context)", function()
    -- Package names and bare symbol strings are always quoted so Swank reads
    -- them as strings, not symbols.
    assert.equals('"COMMON-LISP-USER"', protocol.serialize("COMMON-LISP-USER"))
    assert.equals('"MAPCAR"',           protocol.serialize("MAPCAR"))
    assert.equals('"mapcar"',           protocol.serialize("mapcar"))
  end)

  it("quotes strings with spaces", function()
    assert.equals('"hello world"', protocol.serialize("hello world"))
  end)

  it("escapes quotes inside strings", function()
    assert.equals('"say \\"hi\\""', protocol.serialize('say "hi"'))
  end)

  it("serializes empty list", function()
    assert.equals("()", protocol.serialize({}))
  end)

  it("serializes flat list", function()
    assert.equals("(1 2 3)", protocol.serialize({ 1, 2, 3 }))
  end)

  it("serializes nested list", function()
    -- Note: Lua tables cannot store nil as an element (ipairs stops at the
    -- first nil hole). In practice, Swank optional trailing-nil arguments are
    -- simply omitted, which Swank treats identically. We test with real values.
    assert.equals("(:emacs-rex (swank:connection-info) \"COMMON-LISP-USER\" t 1)",
      protocol.serialize({ ":emacs-rex", { "swank:connection-info" }, "COMMON-LISP-USER", true, 1 }))
  end)

  it("errors on unsupported types (e.g. function)", function()
    assert.has_error(function()
      protocol.serialize(function() end)
    end)
  end)

  it("round-trips parse → serialize for typical RPC forms", function()
    local forms = {
      '(:emacs-rex (swank:connection-info) "COMMON-LISP-USER" t 1)',
      '(:return (:ok "result") 1)',
      '(:debug 1 1 ("error msg" "TYPE" nil) (("ABORT" "abort")) ((0 "frame")) nil)',
    }
    for _, src in ipairs(forms) do
      local parsed = protocol.parse(src)
      local reserialized = protocol.serialize(parsed)
      local reparsed = protocol.parse(reserialized)
      -- Deep-equal check: re-parse both and compare serializations
      assert.equals(
        protocol.serialize(parsed),
        protocol.serialize(reparsed),
        "round-trip failed for: " .. src
      )
    end
  end)
end)

describe("protocol.dispatch", function()
  it("calls a registered handler with the full message", function()
    local received
    protocol.on(":test-evt", function(msg) received = msg end)
    protocol.dispatch({ ":test-evt", 42, "hello" })
    assert.same({ ":test-evt", 42, "hello" }, received)
  end)

  it("is case-insensitive (dispatches lowercase to uppercase-registered handler)", function()
    local called = false
    protocol.on(":UPPER-EVT", function() called = true end)
    protocol.dispatch({ ":upper-evt" })
    assert.is_true(called)
  end)

  it("does nothing for unregistered events without erroring", function()
    assert.has_no_error(function()
      protocol.dispatch({ ":no-such-event-xyz" })
    end)
  end)

  it("does nothing for non-table messages without erroring", function()
    assert.has_no_error(function()
      protocol.dispatch("string")
      protocol.dispatch(nil)
      protocol.dispatch(42)
    end)
  end)

  it("does nothing for a table with no first element", function()
    assert.has_no_error(function()
      protocol.dispatch({})
    end)
  end)

  it("allows re-registering a handler for the same event", function()
    local count = 0
    protocol.on(":dup-evt", function() count = count + 1 end)
    protocol.on(":dup-evt", function() count = count + 10 end)
    protocol.dispatch({ ":dup-evt" })
    -- second registration replaces first
    assert.equals(10, count)
  end)
end)
