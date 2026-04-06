-- tests/unit/client_on_connect_spec.lua
-- Test client._on_connect post-connect initialisation behaviour

local client = require("swank.client")

describe("client._on_connect", function()
  local orig_rex, orig_notify, orig_config
  before_each(function()
    client._test_reset()
    orig_rex = client.rex
    orig_notify = vim.notify
    orig_config = require("swank").config
  end)
  after_each(function()
    client.rex = orig_rex
    vim.notify = orig_notify
    require("swank").config = orig_config
    client._test_reset()
  end)

  it("notifies with implementation name and version from connection-info", function()
    local swank = require("swank")
    swank.config = { contribs = {} }

    client.rex = function(form, cb)
      local cmd = form[1]
      if cmd == "swank:connection-info" then
        cb({ ":ok", { ":lisp-implementation", { ":name", "SBCL", ":version", "1.2.3" } } })
      else
        cb({ ":ok", true })
      end
    end

    local captured
    vim.notify = function(msg, level) captured = msg end

    client._on_connect()

    assert.equals("swank.nvim: SBCL 1.2.3", captured)
  end)
end)
