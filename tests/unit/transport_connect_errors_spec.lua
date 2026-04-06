-- tests/unit/transport_connect_errors_spec.lua
-- Unit tests for transport:connect error and read error handling using mocked vim.uv

local function make_mock_uv_connect_error()
  local last_handle
  local uv = {}
  uv.new_tcp = function()
    local handle = {}
    handle.closed = false
    function handle:connect(host, port, cb)
      -- simulate immediate connect error
      cb("connect-failed")
    end
    function handle:close()
      self.closed = true
    end
    function handle:read_start(cb) end
    function handle:write(_) end
    last_handle = handle
    return handle
  end
  return uv, function() return last_handle end
end

local function make_mock_uv_connect_success()
  local last_handle
  local uv = {}
  uv.new_tcp = function()
    local handle = {}
    handle.closed = false
    function handle:connect(host, port, cb)
      -- simulate immediate successful connect
      cb(nil)
    end
    function handle:read_start(cb)
      -- store callback for later invocation by test
      self._read_cb = cb
    end
    function handle:write(_) end
    function handle:close()
      self.closed = true
    end
    last_handle = handle
    return handle
  end
  return uv, function() return last_handle end
end

local function silence_notify()
  _G.__orig_notify = vim.notify
  vim.notify = function() end
end
local function restore_notify()
  if _G.__orig_notify then vim.notify = _G.__orig_notify; _G.__orig_notify = nil end
end

describe("Transport.connect error/read handling", function()
  local orig_uv, orig_transport_mod

  after_each(function()
    -- restore globals
    vim.uv = orig_uv
    package.loaded["swank.transport"] = orig_transport_mod
    restore_notify()
  end)

  it("connect() passes error and closes handle on connect failure", function()
    silence_notify()
    orig_uv = vim.uv
    orig_transport_mod = package.loaded["swank.transport"]

    local mock_uv, get_last_handle = make_mock_uv_connect_error()
    vim.uv = mock_uv
    package.loaded["swank.transport"] = nil
    local transport_mod = require("swank.transport")

    local got_err = nil
    local t = transport_mod.Transport.new(function() end, function() end)
    t:connect("127.0.0.1", 4005, function(err) got_err = err end)

    assert.equals("connect-failed", got_err)
    local last_handle = get_last_handle()
    assert.is_true(last_handle.closed, "expected handle:close() to be called on connect error")
  end)

  it("read error triggers on_disconnect and clears handle", function()
    silence_notify()
    orig_uv = vim.uv
    orig_transport_mod = package.loaded["swank.transport"]

    local mock_uv, get_last_handle = make_mock_uv_connect_success()
    vim.uv = mock_uv
    package.loaded["swank.transport"] = nil
    local transport_mod = require("swank.transport")

    -- make vim.schedule synchronous for tests
    local orig_schedule = vim.schedule
    vim.schedule = function(fn) fn() end

    local disconnected = false
    local received = {}
    local t = transport_mod.Transport.new(function(msg) table.insert(received, msg) end, function() disconnected = true end)
    local conn_err = nil
    t:connect("127.0.0.1", 4005, function(err) conn_err = err end)

    assert.is_nil(conn_err)
    local last_handle = get_last_handle()
    -- simulate read error from uv
    assert.is_function(last_handle._read_cb)
    last_handle._read_cb("read-err", nil)

    assert.is_true(disconnected, "expected on_disconnect called on read error")
    assert.is_nil(t.handle, "expected transport.handle to be cleared")

    -- restore schedule
    vim.schedule = orig_schedule
  end)

  it("read data feeds messages to on_message via _feed", function()
    silence_notify()
    orig_uv = vim.uv
    orig_transport_mod = package.loaded["swank.transport"]

    local mock_uv, get_last_handle = make_mock_uv_connect_success()
    vim.uv = mock_uv
    package.loaded["swank.transport"] = nil
    local transport_mod = require("swank.transport")

    -- make vim.schedule synchronous for tests
    local orig_schedule = vim.schedule
    vim.schedule = function(fn) fn() end

    local received = {}
    local disconnected = false
    local t = transport_mod.Transport.new(function(msg) table.insert(received, msg) end, function() disconnected = true end)
    t:connect("127.0.0.1", 4005, function(_) end)

    local last_handle = get_last_handle()
    -- craft a framed message
    local body = "(hello)"
    local frame = string.format("%06x", #body) .. body
    assert.is_function(last_handle._read_cb)
    last_handle._read_cb(nil, frame)

    assert.equals(1, #received)
    assert.equals("(hello)", received[1])

    -- restore schedule
    vim.schedule = orig_schedule
  end)
end)
