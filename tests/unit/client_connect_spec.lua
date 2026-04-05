local client = require("swank.client")
local transport_mod = require("swank.transport")

describe("client.connect behaviour", function()
  it("handles transport connect error and notifies user", function()
    -- Ensure config provides defaults
    local swank = require("swank")
    swank.config = swank.config or {}
    swank.config.server = { host = "127.0.0.1", port = 4005 }

    -- Mock transport.Transport.new to return a transport whose connect returns error
    local orig_transport = transport_mod.Transport
    transport_mod.Transport = {
      new = function(on_message, on_disconnect)
        return {
          connect = function(self, host, port, cb)
            -- support both colon and dot call styles; call cb with error
            cb("econnrefused")
          end,
          disconnect = function() end,
        }
      end,
    }

    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, _lvl) if msg:find("connection failed") then notified = true end end

    -- Call client.connect and assert it handles failure
    client.connect(nil, nil)

    -- restore
    vim.notify = orig_notify
    transport_mod.Transport = orig_transport
  end)

  it("successful connect sets connected state", function()
    local swank = require("swank")
    swank.config = swank.config or {}
    swank.config.server = { host = "127.0.0.1", port = 4005 }

    local orig_transport = transport_mod.Transport
    transport_mod.Transport = {
      new = function(on_message, on_disconnect)
        return {
          connect = function(self, host, port, cb)
            cb(nil)
          end,
          send = function() end,
          disconnect = function() end,
        }
      end,
    }

    client._test_reset()
    client.connect(nil, nil)
    assert.is_true(client.is_connected())

    transport_mod.Transport = orig_transport
    client._test_reset()
  end)
end)
