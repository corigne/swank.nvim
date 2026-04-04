-- swank.nvim — high-level Swank client
-- Manages connection lifecycle, emacs-rex call/response, and event routing.

local M = {}

local transport_mod = require("swank.transport")
local protocol = require("swank.protocol")

---@type SwankTransport|nil
local transport = nil

---@type integer  monotonically increasing message ID
local msg_id = 0

---@type table<integer, fun(result: any)>  pending RPC callbacks
local callbacks = {}

---@type string  current package context
local current_package = "COMMON-LISP-USER"

local function next_id()
  msg_id = msg_id + 1
  return msg_id
end

-- ---------------------------------------------------------------------------
-- Connection management
-- ---------------------------------------------------------------------------

--- Connect to a running Swank server
---@param host string|nil  defaults to config
---@param port integer|nil defaults to config
function M.connect(host, port)
  local cfg = require("swank").config
  host = host or cfg.server.host
  port = port or cfg.server.port

  transport = transport_mod.Transport.new(
    function(raw)  -- on_message
      local msg = protocol.parse(raw)
      if msg then protocol.dispatch(msg) end
    end,
    function()     -- on_disconnect
      transport = nil
      vim.notify("swank.nvim: disconnected", vim.log.levels.WARN)
    end
  )

  transport:connect(host, port, function(err)
    if err then
      vim.notify("swank.nvim: connection failed: " .. err, vim.log.levels.ERROR)
      transport = nil
      return
    end
    vim.notify("swank.nvim: connected to " .. host .. ":" .. port, vim.log.levels.INFO)
    M._on_connect()
  end)
end

--- Start SBCL + Swank server then connect (placeholder — will use vim.fn.jobstart)
function M.start_and_connect()
  vim.notify("swank.nvim: start_and_connect not yet implemented", vim.log.levels.WARN)
end

--- Disconnect from the server
function M.disconnect()
  if transport then
    transport:disconnect()
    transport = nil
    vim.notify("swank.nvim: disconnected", vim.log.levels.INFO)
  end
end

--- Returns true if currently connected
---@return boolean
function M.is_connected()
  return transport ~= nil
end

-- ---------------------------------------------------------------------------
-- Low-level RPC
-- ---------------------------------------------------------------------------

--- Send an :emacs-rex call and register a callback for the response
---@param form table  s-expression as a Lua table
---@param cb fun(result: any)
---@param pkg string|nil  package context
function M.rex(form, cb, pkg)
  if not transport then
    vim.notify("swank.nvim: not connected", vim.log.levels.ERROR)
    return
  end
  local id = next_id()
  callbacks[id] = cb
  local payload = protocol.serialize({
    ":emacs-rex",
    form,
    pkg or current_package,
    true,
    id,
  })
  transport:send(payload)
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------

protocol.on(":return", function(msg)
  -- msg = (:return (:ok result) id)  or  (:return (:abort condition) id)
  local id = msg[3]
  local cb = callbacks[id]
  if cb then
    callbacks[id] = nil
    cb(msg[2])
  end
end)

protocol.on(":write-string", function(msg)
  require("swank.ui.repl").append(msg[2] or "")
end)

protocol.on(":debug", function(msg)
  require("swank.ui.sldb").open(msg)
end)

protocol.on(":debug-return", function(_)
  require("swank.ui.sldb").close()
end)

protocol.on(":new-features", function(_) end)  -- acknowledge, no-op for now

-- ---------------------------------------------------------------------------
-- Eval operations
-- ---------------------------------------------------------------------------

--- Eval the top-level form under the cursor
function M.eval_toplevel()
  local form = M._form_at_cursor()
  if not form then return end
  M.rex({ "swank:eval-and-grab-output", form }, function(result)
    require("swank.ui.repl").show_result(result)
  end)
end

--- Eval visually selected region
function M.eval_region()
  local lines = M._get_visual_selection()
  if not lines then return end
  M.rex({ "swank:eval-and-grab-output", lines }, function(result)
    require("swank.ui.repl").show_result(result)
  end)
end

--- Eval with interactive input via vim.ui.input
function M.eval_interactive()
  vim.ui.input({ prompt = "Eval: " }, function(input)
    if not input or input == "" then return end
    M.rex({ "swank:eval-and-grab-output", input }, function(result)
      require("swank.ui.repl").show_result(result)
    end)
  end)
end

--- Describe symbol at cursor
function M.describe_symbol()
  local sym = vim.fn.expand("<cword>")
  M.rex({ "swank:describe-symbol", sym }, function(result)
    if result and result[2] then
      require("swank.ui.repl").append(result[2])
    end
  end)
end

--- Apropos query via vim.ui.input
function M.apropos()
  vim.ui.input({ prompt = "Apropos: " }, function(input)
    if not input or input == "" then return end
    M.rex({ "swank:apropos-list-for-emacs", input, false, false, nil }, function(result)
      require("swank.ui.repl").show_result(result)
    end)
  end)
end

--- Inspect value at cursor
function M.inspect_value()
  local sym = vim.fn.expand("<cword>")
  M.rex({ "swank:inspect-value", sym }, function(result)
    require("swank.ui.inspector").open(result)
  end)
end

--- Load current file
function M.load_file()
  local path = vim.api.nvim_buf_get_name(0)
  M.rex({ "swank:load-file", path }, function(result)
    require("swank.ui.repl").show_result(result)
  end)
end

--- Compile current file
function M.compile_file()
  local path = vim.api.nvim_buf_get_name(0)
  M.rex({ "swank:compile-file-if-needed", path, false }, function(result)
    require("swank.ui.notes").show(result)
  end)
end

--- Compile form at cursor
function M.compile_form()
  local form = M._form_at_cursor()
  if not form then return end
  local bufname = vim.api.nvim_buf_get_name(0)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  M.rex({ "swank:compile-string-for-emacs", form, bufname, col, row, nil }, function(result)
    require("swank.ui.notes").show(result)
  end)
end

-- XRef
function M.xref_calls()
  local sym = vim.fn.expand("<cword>")
  M.rex({ "swank:xref", ":calls", sym }, function(r) require("swank.ui.xref").show(r, "calls") end)
end

function M.xref_references()
  local sym = vim.fn.expand("<cword>")
  M.rex({ "swank:xref", ":references", sym }, function(r) require("swank.ui.xref").show(r, "references") end)
end

function M.find_definition()
  local sym = vim.fn.expand("<cword>")
  M.rex({ "swank:find-definitions-for-emacs", sym }, function(r) require("swank.ui.xref").show(r, "definition") end)
end

-- ---------------------------------------------------------------------------
-- Post-connect initialisation
-- ---------------------------------------------------------------------------

function M._on_connect()
  local cfg = require("swank").config
  -- Load contribs
  M.rex({
    "swank:swank-require",
    cfg.contribs,
  }, function(_)
    vim.notify("swank.nvim: contribs loaded", vim.log.levels.INFO)
  end)
end

-- ---------------------------------------------------------------------------
-- Helpers (placeholders — will use treesitter in future)
-- ---------------------------------------------------------------------------

function M._form_at_cursor()
  -- Naive: grab the line. Will be replaced with treesitter s-expr detection.
  return vim.api.nvim_get_current_line()
end

function M._get_visual_selection()
  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(0, s[2] - 1, e[2], false)
  if #lines == 0 then return nil end
  return table.concat(lines, "\n")
end

return M
