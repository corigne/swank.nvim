-- swank.nvim — trace dialog (Phase 5)
-- Displays SWANK-TRACE-DIALOG trace entries in a floating window.
-- Traces accumulate as Swank pushes :trace-dialog-update events.
-- Keymaps: t toggle trace on symbol, T untrace all, c clear, g refresh, q quit.

local M = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

---@class TraceEntry
---@field id      integer
---@field spec    string   function name
---@field args    string   argument list as a string
---@field retvals string   return values as a string
---@field depth   integer  call depth (for indenting)

---@type TraceEntry[]
local entries = {}

---@type string[]  specs currently being traced
local traced_specs = {}

local state = {
  bufnr = nil,
  winnr = nil,
  ns    = vim.api.nvim_create_namespace("swank_trace"),
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function client() return require("swank.client") end

local function destroy()
  if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
    vim.api.nvim_win_close(state.winnr, true)
  end
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end
  state.winnr = nil
  state.bufnr = nil
end

--- Render a single trace entry as display lines
---@param e TraceEntry
---@return string[]
local function render_entry(e)
  local indent = string.rep("  ", e.depth)
  local header = string.format("%s[%d] %s", indent, e.id, e.spec)
  local args    = string.format("%s  args:    %s", indent, e.args)
  local retvals = string.format("%s  returns: %s", indent, e.retvals)
  return { header, args, retvals, "" }
end

local function build_lines()
  local lines = {}
  if #traced_specs > 0 then
    table.insert(lines, "  Tracing: " .. table.concat(traced_specs, ", "))
  else
    table.insert(lines, "  Tracing: (none)")
  end
  table.insert(lines, string.rep("─", 60))
  if #entries == 0 then
    table.insert(lines, "  (no trace entries yet — call a traced function)")
    table.insert(lines, "")
  else
    for _, e in ipairs(entries) do
      for _, l in ipairs(render_entry(e)) do
        table.insert(lines, l)
      end
    end
  end
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, "  t trace  T untrace-all  c clear  g refresh  q quit")
  return lines
end

local function redraw()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
  local lines = build_lines()
  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false
  -- Highlight the header line of each entry
  vim.api.nvim_buf_clear_namespace(state.bufnr, state.ns, 0, -1)
  for i, line in ipairs(lines) do
    if line:match("^%s*%[%d+%]") then
      vim.api.nvim_buf_add_highlight(state.bufnr, state.ns, "Function", i - 1, 0, -1)
    elseif line:match("^%s*args:") or line:match("^%s*returns:") then
      vim.api.nvim_buf_add_highlight(state.bufnr, state.ns, "Comment", i - 1, 0, -1)
    elseif line:match("^%s*Tracing:") then
      vim.api.nvim_buf_add_highlight(state.bufnr, state.ns, "Special", i - 1, 0, -1)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Swank RPC helpers (used internally and by client.lua)
-- ---------------------------------------------------------------------------

--- Parse a trace entry s-expr from Swank
---@param raw table  raw s-expr list for one entry
---@return TraceEntry|nil
local function parse_entry(raw)
  if type(raw) ~= "table" then return nil end
  -- Format: (id spec args retvals depth)
  local id      = tonumber(raw[1]) or 0
  local spec    = tostring(raw[2] or "?")
  local args_t  = raw[3]
  local rets_t  = raw[4]
  local depth   = tonumber(raw[5]) or 0

  local function fmt_list(t)
    if type(t) ~= "table" then return tostring(t or "") end
    local parts = {}
    for _, v in ipairs(t) do table.insert(parts, tostring(v)) end
    return "(" .. table.concat(parts, " ") .. ")"
  end

  return {
    id      = id,
    spec    = spec,
    args    = fmt_list(args_t),
    retvals = fmt_list(rets_t),
    depth   = depth,
  }
end

-- ---------------------------------------------------------------------------
-- Public API — called from client.lua event handlers
-- ---------------------------------------------------------------------------

--- Append new trace entries pushed by :trace-dialog-update
---@param batch table  list of raw entry s-exprs
function M.push_entries(batch)
  if type(batch) ~= "table" then return end
  for _, raw in ipairs(batch) do
    local e = parse_entry(raw)
    if e then table.insert(entries, e) end
  end
  vim.schedule(redraw)
end

--- Update the list of currently traced specs
---@param specs table  list of spec name strings
function M.set_specs(specs)
  traced_specs = {}
  if type(specs) == "table" then
    for _, s in ipairs(specs) do
      table.insert(traced_specs, tostring(s))
    end
  end
  vim.schedule(redraw)
end

--- Clear all local trace entries (does not send RPC)
function M.clear()
  entries = {}
  vim.schedule(redraw)
end

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------

local function setup_keymaps()
  local buf  = state.bufnr
  local opts = { buffer = buf, silent = true, nowait = true }
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
  end

  map("t", function()
    vim.ui.input({ prompt = "Trace function: " }, function(sym)
      if not sym or sym == "" then return end
      client().trace_toggle(sym)
    end)
  end, "Toggle trace on function")

  map("T", function() client().untrace_all() end,     "Untrace all")
  map("c", function() client().clear_traces() end,    "Clear trace entries")
  map("g", function() client().refresh_traces() end,  "Refresh trace entries")
  map("q",     function() M.close() end, "Close trace dialog")
  map("<Esc>", function() M.close() end, "Close trace dialog")
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------

--- Open the trace dialog (or bring to front if already open)
function M.open()
  if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
    vim.api.nvim_set_current_win(state.winnr)
    return
  end

  destroy()
  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[state.bufnr].filetype   = "swank-trace"
  vim.bo[state.bufnr].buftype    = "nofile"
  vim.bo[state.bufnr].modifiable = false

  local lines = build_lines()
  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false

  local cfg    = require("swank").config.ui.floating
  local width  = math.min(math.floor(vim.o.columns * 0.75), 100)
  local height = math.min(math.max(#lines + 2, 10), math.floor(vim.o.lines * 0.6))
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  state.winnr = vim.api.nvim_open_win(state.bufnr, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = cfg.border or "rounded",
    title     = " Trace Dialog ",
    title_pos = "center",
  })

  vim.wo[state.winnr].wrap       = false
  vim.wo[state.winnr].cursorline = true

  setup_keymaps()
  -- Fetch current state from Swank
  client().refresh_traces()
end

--- Close the trace dialog window
function M.close()
  destroy()
end

return M
