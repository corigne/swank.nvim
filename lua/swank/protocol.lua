-- swank.nvim — Swank protocol: s-expression parser + serializer + event dispatch
-- Parses only the subset of s-expressions used in Swank messages.

local M = {}

-- ---------------------------------------------------------------------------
-- S-expression reader (minimal, Swank-message subset)
-- Handles: lists, strings, symbols, keywords, integers, nil/t
-- ---------------------------------------------------------------------------

---@param src string
---@param pos integer  (1-based)
---@return any, integer  (value, next_pos)
local function read(src, pos)
  -- skip whitespace
  while pos <= #src and src:sub(pos, pos):match("%s") do pos = pos + 1 end
  if pos > #src then error("unexpected end of input") end

  local ch = src:sub(pos, pos)

  -- list
  if ch == "(" then
    local result = {}
    pos = pos + 1
    while true do
      while pos <= #src and src:sub(pos, pos):match("%s") do pos = pos + 1 end
      if src:sub(pos, pos) == ")" then return result, pos + 1 end
      local val
      val, pos = read(src, pos)
      table.insert(result, val)
    end

  -- string
  elseif ch == '"' then
    local s = ""
    pos = pos + 1
    while pos <= #src do
      local c = src:sub(pos, pos)
      if c == "\\" then
        pos = pos + 1
        s = s .. src:sub(pos, pos)
      elseif c == '"' then
        return s, pos + 1
      else
        s = s .. c
      end
      pos = pos + 1
    end
    error("unterminated string")

  -- keyword or symbol
  elseif ch:match("[%a%d:%-_#%%%.%+%*%?%!%@%$%^%&%=%<%>%/%%|~`]") then
    local s = ""
    while pos <= #src and not src:sub(pos, pos):match("[%s%(%)\"']") do
      s = s .. src:sub(pos, pos)
      pos = pos + 1
    end
    local upper = s:upper()
    if upper == "NIL" then return nil, pos
    elseif upper == "T" then return true, pos
    elseif s:match("^%-?%d+$") then return tonumber(s), pos
    else return s, pos  -- symbol or keyword as plain string
    end

  -- quote shorthand
  elseif ch == "'" then
    local val
    val, pos = read(src, pos + 1)
    return { "QUOTE", val }, pos

  else
    error("unexpected character: " .. ch)
  end
end

--- Parse a Swank s-expression message string into a Lua value
---@param src string
---@return any
function M.parse(src)
  local ok, val = pcall(function()
    local v, _ = read(src, 1)
    return v
  end)
  if not ok then
    vim.notify("swank.nvim: parse error: " .. tostring(val), vim.log.levels.ERROR)
    return nil
  end
  return val
end

-- ---------------------------------------------------------------------------
-- S-expression serializer
-- ---------------------------------------------------------------------------

---@param val any
---@return string
function M.serialize(val)
  local t = type(val)
  if val == nil then
    return "nil"
  elseif t == "boolean" then
    return val and "t" or "nil"
  elseif t == "number" then
    return tostring(math.floor(val))
  elseif t == "string" then
    -- keywords start with ':', package-qualified symbols contain ':'
    -- both emit as-is; anything with whitespace or parens is quoted
    if val:match("^:[%a%d%-_%.]+$")
      or val:match("^[%a%d%-_%%%.%+%*%?%!%@%$%^%&%=%<%>%/%%|~][%a%d%-_%%%.%+%*%?%!%@%$%^%&%=%<%>%/%%|~:]*$")
    then
      return val
    else
      return '"' .. val:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
    end
  elseif t == "table" then
    local parts = {}
    for _, v in ipairs(val) do
      table.insert(parts, M.serialize(v))
    end
    return "(" .. table.concat(parts, " ") .. ")"
  else
    error("cannot serialize type: " .. t)
  end
end

-- ---------------------------------------------------------------------------
-- Event dispatcher
-- ---------------------------------------------------------------------------

---@type table<string, fun(payload: any)>
local handlers = {}

--- Register a handler for a Swank event type
---@param event string  e.g. ":return", ":debug", ":write-string"
---@param fn fun(payload: any)
function M.on(event, fn)
  handlers[event:upper()] = fn
end

--- Dispatch a parsed Swank message to the appropriate handler
---@param msg any  parsed s-expression (a list)
function M.dispatch(msg)
  if type(msg) ~= "table" or not msg[1] then return end
  local event = tostring(msg[1]):upper()
  local handler = handlers[event]
  if handler then
    handler(msg)
  else
    vim.notify("swank.nvim: unhandled event: " .. event, vim.log.levels.DEBUG)
  end
end

return M
