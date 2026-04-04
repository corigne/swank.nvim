-- swank.nvim — object inspector floating window
-- Renders Swank inspector content with navigable parts.
-- Keymaps: <CR>/<Tab> follow part, b/- go back, r refresh, e eval, q quit.

local M = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

---@class InspectorPart
---@field kind   "value"|"action"
---@field text   string
---@field index  integer  0-based Swank part index

---@class InspectorState
---@field bufnr  integer|nil
---@field winnr  integer|nil
---@field title  string
---@field type   string
---@field line_parts table<integer, InspectorPart>  line (1-based) → part
---@field ns integer  highlight namespace

local state = {
  bufnr      = nil,
  winnr      = nil,
  title      = "",
  type_str   = "",
  line_parts = {},
  ns         = vim.api.nvim_create_namespace("swank_inspector"),
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
  state.line_parts = {}
end

-- ---------------------------------------------------------------------------
-- Content rendering
-- ---------------------------------------------------------------------------

--- Parse the :content list from Swank into lines + part map
---@param content table  raw s-expr list from inspector result
---@return string[], table<integer, InspectorPart>
local function render_content(content)
  if type(content) ~= "table" then return {}, {} end

  local lines = {}
  local line_parts = {}  -- 1-indexed line number → InspectorPart
  local current = ""     -- text accumulated on the current line

  local function flush()
    table.insert(lines, current)
    current = ""
  end

  for _, item in ipairs(content) do
    if type(item) == "string" then
      -- Swank uses "\n" embedded in strings to represent newlines
      local parts = {}
      for seg in (item .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(parts, seg)
      end
      -- first segment appends to current line; remaining each start new lines
      current = current .. (parts[1] or "")
      for i = 2, #parts do
        flush()
        current = parts[i]
      end
      -- undo the trailing flush caused by the sentinel \n we added
      if #parts > 0 then
        -- last segment was already put into `current`; nothing to undo
      end
    elseif type(item) == "table" then
      local kind_str = tostring(item[1] or ""):lower()
      if kind_str == ":value" or kind_str == ":action" then
        local text  = tostring(item[2] or "")
        local index = tonumber(item[3]) or 0
        local kind  = kind_str == ":value" and "value" or "action"
        -- Flush current line so this part gets its own line entry
        flush()
        local part_line = #lines + 1  -- line this part will appear on
        current = "  " .. text
        flush()
        line_parts[part_line] = { kind = kind, text = text, index = index }
      end
      -- ignore unknown tagged items silently
    end
  end
  if current ~= "" then flush() end

  return lines, line_parts
end

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------

local function part_at_cursor()
  if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then return nil end
  local row = vim.api.nvim_win_get_cursor(state.winnr)[1]
  return state.line_parts[row]
end

local function setup_keymaps()
  local buf  = state.bufnr
  local opts = { buffer = buf, silent = true, nowait = true }
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
  end

  -- Follow part under cursor
  local function follow()
    local part = part_at_cursor()
    if not part then return end
    if part.kind == "value" then
      client().inspect_nth_part(part.index)
    elseif part.kind == "action" then
      client().rex({ "swank:inspector-call-nth-action", part.index }, function(result)
        if type(result) == "table" and result[1] == ":ok" and result[2] then
          M.open(result)
        end
      end)
    end
  end

  map("<CR>",  follow, "Follow part under cursor")
  map("<Tab>", follow, "Follow part under cursor")
  map("b",   function() client().inspector_pop()       end, "Go back")
  map("-",   function() client().inspector_pop()       end, "Go back")
  map("r",   function() client().inspector_reinspect() end, "Refresh")
  map("q",   function() client().quit_inspector()      end, "Quit inspector")
  map("<Esc>", function() client().quit_inspector()    end, "Quit inspector")

  map("e", function()
    vim.ui.input({ prompt = "Eval in inspector context: " }, function(input)
      if not input or input == "" then return end
      client().rex({ "swank:inspector-eval", input }, function(result)
        if type(result) == "table" and result[1] == ":ok" then
          vim.notify("swank.nvim ⇒ " .. tostring(result[2] or ""), vim.log.levels.INFO)
        end
      end)
    end)
  end, "Eval in inspector context")
end

-- ---------------------------------------------------------------------------
-- Highlights
-- ---------------------------------------------------------------------------

local function apply_highlights(line_parts)
  local buf = state.bufnr
  vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)
  for lnum, part in pairs(line_parts) do
    local hl = part.kind == "value" and "Special" or "Function"
    vim.api.nvim_buf_add_highlight(buf, state.ns, hl, lnum - 1, 0, -1)
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Open or refresh the inspector window
---@param result any  (:ok CONTENT) from swank:init-inspector or inspect-nth-part
function M.open(result)
  if type(result) ~= "table" or result[1] ~= ":ok" then
    vim.notify("swank.nvim: inspector: unexpected result format", vim.log.levels.WARN)
    return
  end

  local raw = result[2]
  if type(raw) ~= "table" then
    vim.notify("swank.nvim: inspector: empty result", vim.log.levels.WARN)
    return
  end

  -- raw is a flat plist: (:title "..." :id N :content (...) :start N :end N)
  local p = require("swank.client")._plist(raw)
  local title    = tostring(p[":title"] or "Inspector")
  local content  = p[":content"] or {}

  -- Also check for :type (not always present)
  state.title    = title
  state.type_str = tostring(p[":type"] or "")

  local content_lines, line_parts = render_content(content)

  -- Build display: header + content
  local header = {
    string.rep("─", 60),
    "  " .. title,
    (state.type_str ~= "" and ("  Type: " .. state.type_str) or nil),
    string.rep("─", 60),
    "",
  }
  -- compact header: skip nil slots
  local hlines = {}
  for _, l in ipairs(header) do if l then table.insert(hlines, l) end end
  local hlen = #hlines
  -- Offset line_parts by header height
  local adjusted_parts = {}
  for lnum, part in pairs(line_parts) do
    adjusted_parts[lnum + hlen] = part
  end

  local footer = { "", "  <CR> follow  b/- back  r refresh  e eval  q quit" }
  local all_lines = {}
  for _, l in ipairs(hlines) do table.insert(all_lines, l) end
  for _, l in ipairs(content_lines) do table.insert(all_lines, l) end
  for _, l in ipairs(footer) do table.insert(all_lines, l) end

  -- Create / reuse buffer
  destroy()
  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[state.bufnr].filetype   = "swank-inspector"
  vim.bo[state.bufnr].buftype    = "nofile"
  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, all_lines)
  vim.bo[state.bufnr].modifiable = false

  state.line_parts = adjusted_parts
  apply_highlights(adjusted_parts)

  -- Floating window
  local cfg = require("swank").config.ui.floating
  local width  = math.min(math.floor(vim.o.columns * 0.7), 88)
  local height = math.min(#all_lines + 2, math.floor(vim.o.lines * 0.65))
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
    title     = " Inspector ",
    title_pos = "center",
  })

  vim.wo[state.winnr].wrap       = false
  vim.wo[state.winnr].cursorline = true

  setup_keymaps()
  -- Position cursor on first navigable part
  for lnum = 1, #all_lines do
    if adjusted_parts[lnum] then
      vim.api.nvim_win_set_cursor(state.winnr, { lnum, 2 })
      break
    end
  end
end

--- Close the inspector window without sending quit-inspector to Swank
function M.close()
  destroy()
end

return M
