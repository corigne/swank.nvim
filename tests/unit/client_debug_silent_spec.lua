-- tests/unit/client_debug_silent_spec.lua
-- Ensure protocol :debug events are suppressed during M.silent_rex

local client = require("swank.client")
local protocol = require("swank.protocol")

local function make_mock_transport()
  local sent = {}
  local t = {
    send       = function(self, payload) table.insert(sent, payload) end,
    disconnect = function(self) self._closed = true end,
    _closed    = false,
  }
  return t, sent
end

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
  require("swank.ui.sldb").open        = function(_) end
  require("swank.ui.sldb").close       = function() end
end

describe("protocol :debug suppression with silent_rex", function()
  local mock, sent

  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_reset()
    client._test_inject(mock)
    require("swank").config = {}
  end)

  after_each(function()
    client._test_reset()
    require("swank").config = {}
    restore_notify()
  end)

  it("suppresses :debug when silent_rex in flight and swank.config.debug = true", function()
    -- Enable debug logging in config so the suppression branch takes the pcall path
    require("swank").config = { debug = true }

    -- Stub io.open to avoid touching filesystem during test (pcall wraps this)
    local orig_io_open = io.open
    io.open = function(...) return { write = function() end, close = function() end } end

    -- Make sldb.open fatal if invoked (it should NOT be called while suppressed)
    require("swank.ui.sldb").open = function() error("sldb.open should not be called") end

    -- Start a silent rex; this increments silent_count and leaves it >0 until callback
    client.silent_rex({ "swank:eval-and-grab-output", "(+ 1 2)" }, function() end)

    -- Dispatch a :debug event while silent_rex is in flight. Should be suppressed.
    assert.has_no.errors(function()
      protocol.dispatch({ ":debug", { "payload" }, 1 })
    end)

    -- Restore io.open
    io.open = orig_io_open
  end)
end)
