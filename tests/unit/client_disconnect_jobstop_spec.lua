-- tests/unit/client_disconnect_jobstop_spec.lua
-- Ensure client.disconnect stops impl job when impl_job_id is set

local client = require("swank.client")

local function silence_notify()
  _G.__orig_notify = vim.notify
  vim.notify = function() end
end
local function restore_notify()
  if _G.__orig_notify then vim.notify = _G.__orig_notify; _G.__orig_notify = nil end
end

describe("client.disconnect() stops impl job when present", function()
  local orig_jobstart, orig_jobstop, orig_uv_new_timer, orig_io_open
  before_each(function()
    silence_notify()
    client._test_reset()
    orig_jobstart = vim.fn.jobstart
    orig_jobstop  = vim.fn.jobstop
    orig_uv_new_timer = vim.uv.new_timer
    orig_io_open = io.open
  end)
  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.fn.jobstop  = orig_jobstop
    vim.uv.new_timer = orig_uv_new_timer
    io.open = orig_io_open
    client._test_reset()
    restore_notify()
  end)

  it("calls jobstop on impl_job_id when disconnecting", function()
    local swank = require("swank")
    swank.config = {
      autostart = { enabled = true, implementation = "dummy-bin" },
      server = { host = "127.0.0.1", port = 4005 },
      contribs = {},
    }

    -- jobstart returns a positive id
    local returned_job_id = 4242
    vim.fn.jobstart = function(argv, opts)
      -- emulate starting; return the job id
      return returned_job_id
    end

    local jobstop_called_with
    vim.fn.jobstop = function(id) jobstop_called_with = id end

    -- stub timer so it doesn't attempt to poll or call callbacks
    vim.uv.new_timer = function()
      return { start = function() end, stop = function() end, close = function() end }
    end

    -- stub io.open when writing script
    io.open = function(path, mode)
      return { write = function() end, close = function() end }
    end

    -- Run start_and_connect so impl_job_id is set
    client.start_and_connect()

    -- Now disconnect should call jobstop with the same id
    client.disconnect()
    assert.equals(returned_job_id, jobstop_called_with)
  end)
end)
