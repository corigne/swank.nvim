-- tests/unit/client_start_and_connect_timer_spec.lua
-- Test client.start_and_connect timer/polling behaviour (port-file detection)

local client = require("swank.client")
local orig_io_open = io.open

local function silence_notify()
  _G.__orig_notify = vim.notify
  vim.notify = function() end
end
local function restore_notify()
  if _G.__orig_notify then vim.notify = _G.__orig_notify; _G.__orig_notify = nil end
end

describe("client.start_and_connect() timer/port-file polling", function()
  local orig_jobstart, orig_uv_new_timer, orig_schedule_wrap, orig_io
  before_each(function()
    silence_notify()
    client._test_reset()
    orig_jobstart = vim.fn.jobstart
    orig_uv_new_timer = vim.uv.new_timer
    orig_schedule_wrap = vim.schedule_wrap
    orig_io = io.open
  end)
  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.uv.new_timer = orig_uv_new_timer
    vim.schedule_wrap = orig_schedule_wrap
    io.open = orig_io
    client._test_reset()
    restore_notify()
  end)

  it("reads port file and invokes M.connect with discovered port", function()
    local swank = require("swank")
    swank.config = {
      autostart = { enabled = true, implementation = "dummy-binary" },
      server = { host = "127.0.0.1", port = 4005 },
      contribs = {},
    }

    -- stub jobstart to return positive pid
    vim.fn.jobstart = function(argv, _opts) return 123 end

    -- stub timer to immediately call the callback
    vim.uv.new_timer = function()
      return {
        start = function(self, _a, _b, cb) cb() end,
        stop  = function() end,
        close = function() end,
      }
    end

    -- schedule_wrap should return identity so the timer receives the inner fn
    vim.schedule_wrap = function(fn) return fn end

    -- stub io.open: when opened for reading the port file, return an object with read
    io.open = function(path, mode)
      if mode == "r" then
        return { read = function(_, _p) return tostring(4005) end, close = function() end }
      else
        -- writing the script: provide a stub with write/close
        return { write = function() end, close = function() end }
      end
    end

    -- Capture calls to client.connect
    local called_host, called_port
    local orig_connect = client.connect
    client.connect = function(host, port) called_host = host; called_port = port end

    -- Run start_and_connect; timer:start will immediately invoke the poll callback
    client.start_and_connect()

    -- Expect that client.connect was invoked with the port read from the file
    assert.equals(4005, called_port)

    -- restore connect
    client.connect = orig_connect
  end)
end)
