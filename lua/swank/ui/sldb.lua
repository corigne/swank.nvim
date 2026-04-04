-- swank.nvim — SLDB debugger UI
-- Opens a floating window when Swank sends a :debug event.
-- Keymaps in the SLDB buffer allow restart invocation, frame navigation,
-- and eval-in-frame without leaving Neovim.

local M = {}

-- ---------------------------------------------------------------------------
-- State (one active debugger level at a time; nested levels replace the view)
-- ---------------------------------------------------------------------------

---@class SldbState
---@field bufnr   integer|nil
---@field winnr   integer|nil
---@field thread  any
---@field level   integer
---@field restarts table  list of {name, desc}
---@field frames  table   list of {number, desc}

---@type SldbState
local state = {
  bufnr    = nil,
  winnr    = nil,
  thread   = nil,
  level    = 0,
  restarts = {},
  frames   = {},
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function client() return require("swank.client") end

--- Close the SLDB window and wipe the buffer
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

--- Write lines into the (modifiable) SLDB buffer
---@param lines string[]
local function set_lines(lines)
  local buf = state.bufnr
  -- nvim_buf_set_lines rejects strings containing '\n'; flatten before writing
  local flat = {}
  for _, l in ipairs(lines) do
    for _, part in ipairs(vim.split(l, "\n", { plain = true })) do
      table.insert(flat, part)
    end
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, flat)
  vim.bo[buf].modifiable = false
end

--- Highlight a range of lines with a given hl group
local function hl(group, first_line, last_line)
  vim.api.nvim_buf_add_highlight(state.bufnr, -1, group, first_line, 0, -1)
  if last_line and last_line > first_line then
    for i = first_line + 1, last_line do
      vim.api.nvim_buf_add_highlight(state.bufnr, -1, group, i, 0, -1)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Build buffer content
-- ---------------------------------------------------------------------------

---@return string[], table  (lines, {restart_lines=[], frame_lines=[]})
local function build_content()
  local lines = {}
  local restart_lines = {}  -- 1-indexed line numbers where restarts appear
  local frame_lines   = {}  -- 1-indexed line numbers where frames appear

  -- Header
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, string.format("  SLDB  level %d", state.level))
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, "")

  -- Condition
  local cond = state.condition
  if type(cond) == "table" then
    table.insert(lines, "  " .. tostring(cond[1] or "Unknown error"))
    if cond[2] and cond[2] ~= cond[1] then
      table.insert(lines, "  Type: " .. tostring(cond[2]))
    end
  else
    table.insert(lines, "  " .. tostring(cond or "Unknown error"))
  end
  table.insert(lines, "")

  -- Restarts
  table.insert(lines, "  Restarts:")
  for i, r in ipairs(state.restarts) do
    local rline = string.format("   [%d] %-18s %s", i - 1,
      tostring(r[1] or ""), tostring(r[2] or ""))
    table.insert(lines, rline)
    table.insert(restart_lines, #lines)
  end
  table.insert(lines, "")

  -- Backtrace
  table.insert(lines, "  Backtrace:")
  for _, f in ipairs(state.frames) do
    local fnum  = tostring(f[1] or "")
    local fdesc = tostring(f[2] or "")
    table.insert(lines, string.format("  %3s: %s", fnum, fdesc))
    table.insert(frame_lines, #lines)
  end
  table.insert(lines, "")

  -- Footer
  table.insert(lines, "  [0-9] restart  [a] abort  [c] continue  [q] quit  [e] eval in frame")

  return lines, { restart_lines = restart_lines, frame_lines = frame_lines }
end

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------

local function frame_at_cursor()
  local row = vim.api.nvim_win_get_cursor(state.winnr)[1]
  -- Walk up from cursor to find the nearest frame line ("  N: desc")
  while row >= 1 do
    local line = vim.api.nvim_buf_get_lines(state.bufnr, row - 1, row, false)[1] or ""
    local num = line:match("^%s+(%d+):")
    if num then return tonumber(num) end
    row = row - 1
  end
  return 0
end

local function setup_keymaps()
  local buf = state.bufnr
  local opts = { buffer = buf, silent = true, nowait = true }

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
  end

  -- Digit keys 0–9 invoke that restart number
  for i = 0, 9 do
    local n = i
    map(tostring(n), function()
      M.invoke_restart(n)
    end, "Invoke restart " .. n)
  end

  -- <CR> on a restart line invokes it
  map("<CR>", function()
    local row = vim.api.nvim_win_get_cursor(state.winnr)[1]
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local num = line:match("^%s*%[(%d+)%]")
    if num then M.invoke_restart(tonumber(num)) end
  end, "Invoke restart under cursor")

  map("a", function() M.abort() end,    "Abort (throw to toplevel)")
  map("c", function() M.continue() end, "Continue")
  map("q", function() M.abort() end,    "Quit / abort")

  map("e", function()
    local frame = frame_at_cursor()
    vim.ui.input({ prompt = "Eval in frame " .. frame .. ": " }, function(input)
      if not input or input == "" then return end
      client().rex(
        { "swank:eval-string-in-frame", input, frame, state.thread, state.level },
        function(result)
          if type(result) == "table" and result[1] == ":ok" then
            require("swank.ui.repl").append(tostring(result[2] or "") .. "\n")
          end
        end
      )
    end)
  end, "Eval expression in frame")

  map("v", function()
    local frame = frame_at_cursor()
    client().rex(
      { "swank:frame-source-location", frame },
      function(result)
        -- result = (:ok (:location (:file "...") (:line N col) nil))
        --       or (:ok (:error "..."))
        if type(result) ~= "table" or result[1] ~= ":ok" then return end
        local loc = result[2]
        if type(loc) ~= "table" then return end
        -- Use xref's extract_location by wrapping as a single-entry refs list
        require("swank.ui.xref").show({ ":ok", { { "frame " .. frame, loc } } }, "frame source")
      end
    )
  end, "View frame source")

  map("l", function()
    local frame = frame_at_cursor()
    client().rex(
      { "swank:frame-locals-and-catch-tags", frame },
      function(result)
        if type(result) == "table" and result[1] == ":ok" then
          local locals = result[2] or {}
          local lines = { string.format("Frame %d locals:", frame) }
          for _, loc in ipairs(locals) do
            if type(loc) == "table" then
              local lp = client()._plist(loc)
              table.insert(lines, string.format("  %s = %s",
                tostring(lp[":name"] or "?"),
                tostring(lp[":value"] or "?")))
            end
          end
          require("swank.ui.repl").append(table.concat(lines, "\n") .. "\n\n")
        end
      end
    )
  end, "Show frame locals")
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Open or refresh the SLDB window for a :debug event
---@param msg table  parsed :debug s-expression
function M.open(msg)
  -- msg = (:debug thread level condition restarts frames conts)
  state.thread   = msg[2]
  state.level    = tonumber(msg[3]) or 1
  state.condition = msg[4]  -- (description type extra)
  state.restarts = type(msg[5]) == "table" and msg[5] or {}
  state.frames   = type(msg[6]) == "table" and msg[6] or {}

  -- In headless mode (no UI attached) there is no window to open.
  -- Auto-abort to dismiss the SLDB session so the server doesn't linger
  -- in a debug state and block subsequent RPC responses.
  if #vim.api.nvim_list_uis() == 0 then
    vim.notify("swank.nvim: SLDB level " .. state.level .. " (headless — auto-aborting)",
      vim.log.levels.DEBUG)
    M.abort()
    return
  end

  -- Reuse buffer if already open, otherwise create fresh
  destroy()

  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[state.bufnr].filetype  = "swank-sldb"
  vim.bo[state.bufnr].buftype   = "nofile"
  vim.bo[state.bufnr].modifiable = false

  local lines, meta = build_content()
  set_lines(lines)

  -- Highlights
  hl("DiagnosticError", 1, 2)         -- header
  hl("DiagnosticWarn",  4, 5)         -- condition
  for _, l in ipairs(meta.restart_lines) do
    hl("DiagnosticInfo", l - 1, l - 1)
  end

  -- Floating window centred in editor
  local swank_cfg = require("swank").config
  local cfg = (swank_cfg and swank_cfg.ui and swank_cfg.ui.floating) or {}
  local width  = math.min(math.floor(vim.o.columns * 0.7), 90)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  state.winnr = vim.api.nvim_open_win(state.bufnr, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = cfg.border or "rounded",
    title    = " SLDB ",
    title_pos = "center",
  })

  vim.wo[state.winnr].wrap      = false
  vim.wo[state.winnr].cursorline = true

  setup_keymaps()

  -- Position cursor on first restart
  if #meta.restart_lines > 0 then
    vim.api.nvim_win_set_cursor(state.winnr, { meta.restart_lines[1], 4 })
  end
end

--- Close the SLDB window (called on :debug-return)
function M.close()
  destroy()
end

--- Invoke restart N in the current debugger level
---@param n integer  0-indexed restart number
function M.invoke_restart(n)
  client().rex(
    { "swank:invoke-nth-restart-for-emacs", state.level, n },
    function(_) end,
    nil,
    state.thread
  )
  -- SLDB closes when Swank sends :debug-return
end

--- Abort — throw to toplevel; must run on the SLDB thread
function M.abort()
  client().rex({ "swank:throw-to-toplevel" }, function(_) end, nil, state.thread)
end

--- Continue from the current restart point
function M.continue()
  client().rex({ "swank:sldb-continue" }, function(_) end, nil, state.thread)
end

return M
