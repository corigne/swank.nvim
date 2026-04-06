-- tests/unit/client_start_and_connect_malformed_portfile_spec.lua
-- Test client.start_and_connect malformed port-file handling

local client = require("swank.client")

describe("client.start_and_connect() malformed port file", function()
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

  it("notifies on malformed port file content", function()
    local swank = require("swank")
    swank.config = {
      autostart = { enabled = true, implementation = "dummy-binary" },
      server = { host = "127.0.0.1", port = 4005 },
      contribs = {},
    }

    vim.fn.jobstart = function(argv, _opts) return 123 end

    vim.uv.new_timer = function()
      return {
        start = function(self, _a, _b, cb)
          -- simulate immediate detection of a port file containing non-numeric data
          cb()
        end,
        stop  = function() end,
        close = function() end,
      }
    end

    vim.schedule_wrap = function(fn) return fn end

    io.open = function(path, mode)
      if mode == "r" then
        return { read = function(_, _p) return "not-a-number" end, close = function() end }
      else
        return { write = function() end, close = function() end }
      end
    end

    local captured_msg
    vim.notify = function(msg, level) captured_msg = msg end

    client.start_and_connect()

    assert.equals("swank.nvim: malformed port file", captured_msg)
  end)
end)
