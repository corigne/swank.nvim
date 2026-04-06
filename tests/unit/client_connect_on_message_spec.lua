-- tests/unit/client_connect_on_message_spec.lua
-- Tests for client.connect on_message dispatch and on_disconnect handling using a mocked transport factory

local client = require("swank.client")
local transport_mod = require("swank.transport")
local protocol = require("swank.protocol")

local function silence_notify()
  _G.__orig_notify = vim.notify
  vim.notify = function() end
end
local function restore_notify()
  if _G.__orig_notify then vim.notify = _G.__orig_notify; _G.__orig_notify = nil end
end

local function mock_ui()
  require("swank.ui.repl").show_result = function(_) end
  require("swank.ui.repl").show_input  = function(_) end
  require("swank.ui.repl").append      = function(_) end
  require("swank.ui.inspector").open   = function(_) end
  require("swank.ui.inspector").close  = function()  end
  require("swank.ui.sldb").open        = function(_) end
  require("swank.ui.sldb").close       = function()  end
  require("swank.ui.xref").show        = function(_) end
  require("swank.ui.notes").show       = function(_) end
  require("swank.ui.trace").set_specs  = function(_) end
  require("swank.ui.trace").push_entries = function(_) end
  require("swank.ui.trace").clear      = function()  end
end

describe("client.connect on_message/on_disconnect", function()
  local orig_transport
  before_each(function()
    silence_notify()
    mock_ui()
    client._test_reset()
    orig_transport = transport_mod.Transport
  end)
  after_each(function()
    transport_mod.Transport = orig_transport
    client._test_reset()
    restore_notify()
  end)

  it(":write-string from on_message dispatches to repl.append and on_disconnect clears state", function()
    local captured_on_message, captured_on_disconnect
    transport_mod.Transport = {
      new = function(on_message, on_disconnect)
        captured_on_message = on_message
        captured_on_disconnect = on_disconnect
        return {
          connect = function(self, host, port, cb) cb(nil) end,
          disconnect = function(self) end,
          send = function(self, _payload) end,
        }
      end,
    }

    -- ensure config exists so connect can be called with nils if needed
    require("swank").config = require("swank").config or {}

    client._test_reset()
    client.connect("127.0.0.1", 4005)
    assert.is_true(client.is_connected())

    local appended
    require("swank.ui.repl").append = function(s) appended = s end

    -- Deliver a :write-string event (protocol.parse expects an s-expression string)
    assert.is_function(captured_on_message)
    captured_on_message('(:write-string "hello\n")')
    assert.equals("hello\n", appended)

    -- Simulate a disconnect from the transport
    assert.is_function(captured_on_disconnect)
    captured_on_disconnect()
    -- transport cleared, connection_state → disconnected
    assert.is_false(client.is_connected())
  end)

  it(":ping causes a :emacs-pong to be sent via transport:send", function()
    local captured_on_message
    local last_sent
    transport_mod.Transport = {
      new = function(on_message, on_disconnect)
        captured_on_message = on_message
        return {
          connect = function(self, host, port, cb) cb(nil) end,
          disconnect = function(self) end,
          send = function(self, payload) last_sent = payload end,
        }
      end,
    }

    client._test_reset()
    client.connect("127.0.0.1", 4005)
    assert.is_true(client.is_connected())

    -- Fire a :ping event
    captured_on_message('(:ping 1 42)')
    assert.is_not_nil(last_sent)
    local parsed = protocol.parse(last_sent)
    assert.equals(":emacs-pong", parsed[1])
    assert.equals(1, parsed[2])
    assert.equals(42, parsed[3])
  end)
end)
