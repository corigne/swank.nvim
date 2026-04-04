-- swank.nvim — async TCP transport layer
-- Uses vim.uv (libuv) for non-blocking socket I/O.
-- Swank message framing: 6-hex-digit length prefix + s-expression payload.

local M = {}

local uv = vim.uv

---@class SwankTransport
---@field handle uv_tcp_t|nil
---@field buffer string
---@field on_message fun(msg: string)
---@field on_disconnect fun()
local Transport = {}
Transport.__index = Transport

--- Create a new transport instance
---@param on_message fun(msg: string) called for each complete message received
---@param on_disconnect fun() called on socket close/error
---@return SwankTransport
function Transport.new(on_message, on_disconnect)
  return setmetatable({
    handle = nil,
    buffer = "",
    on_message = on_message,
    on_disconnect = on_disconnect,
  }, Transport)
end

--- Connect to a Swank server
---@param host string
---@param port integer
---@param on_connect fun(err: string|nil)
function Transport:connect(host, port, on_connect)
  local handle = uv.new_tcp()
  handle:connect(host, port, function(err)
    if err then
      handle:close()
      on_connect(err)
      return
    end
    self.handle = handle
    on_connect(nil)
    handle:read_start(function(read_err, data)
      vim.schedule(function()
        if read_err or not data then
          self:_on_close()
          return
        end
        self:_feed(data)
      end)
    end)
  end)
end

--- Send a raw message string (will be length-prefixed)
---@param payload string
function Transport:send(payload)
  if not self.handle then
    vim.notify("swank.nvim: not connected", vim.log.levels.ERROR)
    return
  end
  local frame = string.format("%06x", #payload) .. payload
  self.handle:write(frame)
end

--- Disconnect the socket
function Transport:disconnect()
  if self.handle then
    self.handle:close()
    self.handle = nil
  end
end

--- Internal: handle raw data from socket
---@param data string
function Transport:_feed(data)
  self.buffer = self.buffer .. data
  while true do
    if #self.buffer < 6 then break end
    local len = tonumber(self.buffer:sub(1, 6), 16)
    if not len then
      vim.notify("swank.nvim: bad message frame", vim.log.levels.ERROR)
      self.buffer = ""
      break
    end
    if #self.buffer < 6 + len then break end
    local msg = self.buffer:sub(7, 6 + len)
    self.buffer = self.buffer:sub(7 + len)
    self.on_message(msg)
  end
end

--- Internal: handle socket close
function Transport:_on_close()
  self.handle = nil
  self.on_disconnect()
end

M.Transport = Transport
return M
