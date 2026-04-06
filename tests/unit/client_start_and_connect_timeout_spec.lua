-- tests/unit/client_start_and_connect_timeout_spec.lua
-- Test client.start_and_connect timeout path (attempts >= 60)

local client = require("swank.client")

describe("client.start_and_connect() timeout", function()
  local orig_jobstart, orig_uv_new_timer, orig_schedule_wrap, orig_io, orig_notify
  before_each(function()
    client._test_reset()
    orig_jobstart = vim.fn.jobstart
    orig_uv_new_timer = vim.uv.new_timer
    orig_schedule_wrap = vim.schedule_wrap
    orig_io = io.open
    orig_notify = vim.notify
  end)
  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.uv.new_timer = orig_uv_new_timer
    vim.schedule_wrap = orig_schedule_wrap
    io.open = orig_io
    vim.notify = orig_notify
    client._test_reset()
  end)

  it("times out when port file not created within attempts", function()
    local swank = require("swank")
    swank.config = {
      autostart = { enabled = true, implementation = "dummy-binary" },
      server = { host = "127.0.0.1", port = 4005 },
      contribs = {},
    }

    -- stub jobstart to return positive pid
    vim.fn.jobstart = function(argv, _opts) return 123 end

    -- stub timer to call the poll callback 61 times to trigger timeout
    vim.uv.new_timer = function()
      return {
        start = function(self, _a, _b, cb)
          for i = 1, 61 do cb() end
        end,
        stop  = function() end,
        close = function() end,
      }
    end

    vim.schedule_wrap = function(fn) return fn end

    -- always fail to open the port file for reads; provide writer for script_file
    io.open = function(path, mode)
      if mode == "r" then return nil end
      return { write = function() end, close = function() end }
    end

    local captured_msg
    vim.notify = function(msg, level) captured_msg = msg end

    client.start_and_connect()

    assert.equals("swank.nvim: timed out waiting for Swank server", captured_msg)
  end)
end)
