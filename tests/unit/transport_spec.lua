-- tests/unit/transport_spec.lua
-- Unit tests for the message-framing logic in transport._feed().
-- We test _feed() in isolation by instantiating a Transport with a collector
-- callback instead of a real TCP socket.

local transport_mod = require("swank.transport")

--- Helper: create a Transport that collects received messages into a table
local function make_transport()
  local received = {}
  local t = transport_mod.Transport.new(
    function(msg) table.insert(received, msg) end,
    function() end
  )
  return t, received
end

describe("transport message framing", function()
  it("delivers a single complete message", function()
    local t, received = make_transport()
    local body = "(hello)"
    local frame = string.format("%06x", #body) .. body
    t:_feed(frame)
    assert.equals(1, #received)
    assert.equals(body, received[1])
  end)

  it("delivers multiple messages in one chunk", function()
    local t, received = make_transport()
    local msgs = { "(foo)", "(bar)", "(baz)" }
    local chunk = ""
    for _, m in ipairs(msgs) do
      chunk = chunk .. string.format("%06x", #m) .. m
    end
    t:_feed(chunk)
    assert.equals(3, #received)
    for i, m in ipairs(msgs) do
      assert.equals(m, received[i])
    end
  end)

  it("handles a message split across two chunks", function()
    local t, received = make_transport()
    local body = "(split message)"
    local frame = string.format("%06x", #body) .. body
    -- Split after the 6-byte length prefix
    t:_feed(frame:sub(1, 8))
    assert.equals(0, #received)
    t:_feed(frame:sub(9))
    assert.equals(1, #received)
    assert.equals(body, received[1])
  end)

  it("handles a message split inside the length prefix", function()
    local t, received = make_transport()
    local body = "(tiny)"
    local frame = string.format("%06x", #body) .. body
    -- Only send 3 bytes of the 6-byte prefix
    t:_feed(frame:sub(1, 3))
    assert.equals(0, #received)
    t:_feed(frame:sub(4))
    assert.equals(1, #received)
    assert.equals(body, received[1])
  end)

  it("delivers many small messages fed byte by byte", function()
    local t, received = make_transport()
    local body = "(x)"
    local frame = string.format("%06x", #body) .. body
    -- Repeat it 5 times, feed one byte at a time
    local big = frame:rep(5)
    for i = 1, #big do
      t:_feed(big:sub(i, i))
    end
    assert.equals(5, #received)
    for _, m in ipairs(received) do
      assert.equals(body, m)
    end
  end)

  it("handles a large message body", function()
    local t, received = make_transport()
    local body = "(\"" .. string.rep("x", 10000) .. "\")"
    local frame = string.format("%06x", #body) .. body
    t:_feed(frame)
    assert.equals(1, #received)
    assert.equals(body, received[1])
  end)
end)

describe("transport send framing", function()
  it("send() prepends a 6-hex-digit length prefix", function()
    -- We can verify by feeding the output back through _feed
    local t, received = make_transport()
    local t2, received2 = make_transport()

    -- Intercept what t.handle:write() would send
    local written = {}
    t.handle = { write = function(_, data) table.insert(written, data) end }

    local payload = "(swank:connection-info)"
    t:send(payload)

    assert.equals(1, #written)
    local frame = written[1]
    local prefix = frame:sub(1, 6)
    local body   = frame:sub(7)
    assert.equals(tostring(#payload), tostring(tonumber(prefix, 16)))
    assert.equals(payload, body)

    -- And the framed output should round-trip through _feed
    t2:_feed(frame)
    assert.equals(1, #received2)
    assert.equals(payload, received2[1])
  end)
end)
