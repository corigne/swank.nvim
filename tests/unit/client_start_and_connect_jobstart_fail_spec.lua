-- tests/unit/client_start_and_connect_jobstart_fail_spec.lua
-- Test client.start_and_connect when jobstart returns non-positive id (failed to start)

local client = require("swank.client")

describe("client.start_and_connect() jobstart failure", function()
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

  it("notifies when jobstart returns non-positive id", function()
    local swank = require("swank")
    swank.config = {
      autostart = { enabled = true, implementation = "dummy-binary" },
      server = { host = "127.0.0.1", port = 4005 },
      contribs = {},
    }

    -- jobstart returns non-positive to simulate failure
    vim.fn.jobstart = function(argv, _opts) return 0 end

    -- stub writer so script write succeeds
    io.open = function(path, mode)
      if mode == "w" then return { write = function() end, close = function() end } end
      return nil
    end

    local captured_msg
    vim.notify = function(msg, level) captured_msg = msg end

    client.start_and_connect()

    assert.equals("swank.nvim: failed to start dummy-binary", captured_msg)
  end)
end)
