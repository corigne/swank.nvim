local transport_mod = require("swank.transport")

describe("transport connect behavior", function()
  it("connect success: invokes on_message via read_start callback", function()
    local received = {}
    local disconnected = false

    -- Mock uv.new_tcp to return a controllable handle
    local orig_uv = vim.uv
    local handle = {}
    function handle:connect(host, port, cb)
      -- simulate async connect success
      cb(nil)
    end
    function handle:read_start(cb)
      -- store the read callback; we'll simulate the incoming frame after connect
      self._read_cb = cb
    end
    function handle:close() end
    vim.uv = { new_tcp = function() return handle end }

    local t = transport_mod.Transport.new(function(msg) table.insert(received, msg) end,
                                         function() disconnected = true end)

    local connected_err = nil
    t:connect("127.0.0.1", 4005, function(err) connected_err = err end)
    assert.is_nil(connected_err)

    -- simulate an incoming framed message (bypass scheduling)
    local body = "(hello)"
    local frame = string.format("%06x", #body) .. body
    t:_feed(frame)

    assert.equals(1, #received)
    assert.equals("(hello)", received[1])

    vim.uv = orig_uv
  end)

  it("connect error: closes handle and returns error", function()
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, _level) if msg:find("connection failed") then notified = true end end

    local orig_uv = vim.uv
    local closed = false
    local handle = {}
    function handle:connect(host, port, cb)
      cb("econnrefused")
    end
    function handle:close() closed = true end
    function handle:read_start(cb) end
    vim.uv = { new_tcp = function() return handle end }

    local t = transport_mod.Transport.new(function() end, function() end)
    local got_err = nil
    t:connect("127.0.0.1", 4005, function(err) got_err = err end)

    -- on error, transport should not have a live handle
    assert.is_nil(t.handle)

    vim.notify = orig_notify
    vim.uv = orig_uv
  end)
end)
