-- tests/unit/client_describe_debug_log_spec.lua
-- Ensure client.describe writes debug sanitize log when swank.config.debug = true

local client = require("swank.client")

local function silence_notify()
  _G.__orig_notify = vim.notify
  vim.notify = function() end
end
local function restore_notify()
  if _G.__orig_notify then vim.notify = _G.__orig_notify; _G.__orig_notify = nil end
end

describe("client.describe() debug logging", function()
  local orig_io_open
  before_each(function()
    silence_notify()
    client._test_reset()
    orig_io_open = io.open
  end)
  after_each(function()
    io.open = orig_io_open
    client._test_reset()
    restore_notify()
    require("swank").config = {}
  end)

  it("writes sanitize debug info when config.debug is true", function()
    require("swank").config = { debug = true }

    local wrote = false
    local wrote_data = nil
    io.open = function(path, mode)
      -- simulate successful open for append
      return {
        write = function(_, data) wrote = true; wrote_data = data end,
        close = function() end,
      }
    end

    -- call describe; it will try to open the debug log before validating symbol
    client.describe("mapcar")
    assert.is_true(wrote)
    assert.truthy(type(wrote_data) == "string")
    assert.truthy(wrote_data:find("raw=") or wrote_data:find("sanitized="))
  end)
end)
