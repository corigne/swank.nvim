-- swank.nvim — REPL output buffer UI
-- Manages a persistent output buffer for Swank REPL interaction.
--
-- Config (ui.repl):
--   position  "auto"|"right"|"left"|"top"|"bottom"|"float"  default: "auto"
--   size      0 < n <= 1 → fraction of editor dim; n > 1 → fixed cols/rows
--
-- "auto" layout priority (always tries to give the REPL ≥80 columns):
--   1. right vertical split   — if floor(columns * size) >= 80
--   2. bottom horizontal split — fallback when the terminal is too narrow
--   3. floating window         — last resort when the terminal is very small

local M = {}

---@type integer|nil
local bufnr = nil
---@type integer|nil
local winnr = nil

local function cfg()
  local c = require("swank").config
  return (c and c.ui and c.ui.repl) or { position = "auto", size = 0.45 }
end

local function ensure_buf()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then return bufnr end
  bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = "swank-repl"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].modifiable = false
  vim.api.nvim_buf_set_name(bufnr, "swank://repl")
  return bufnr
end

local function resolve_size(size, total)
  if size > 0 and size <= 1 then
    return math.max(1, math.floor(total * size))
  end
  return math.max(1, math.floor(size))
end

--- Resolve "auto" to a concrete position.
-- Vertical split is preferred; we fall back only when the REPL panel would
-- be narrower than 80 columns.  Horizontal split is the next option; float
-- is the last resort for very small terminals.
local function effective_pos(pos, size)
  if pos ~= "auto" then return pos end
  if resolve_size(size, vim.o.columns) >= 80 then return "right" end
  if resolve_size(size, vim.o.lines)   >= 12 then return "bottom" end
  return "float"
end

local function open_win()
  local c    = cfg()
  local size = c.size or 0.45
  local pos  = effective_pos(c.position or "auto", size)
  local buf  = ensure_buf()

  if pos == "float" then
    local sc = require("swank").config
    local fcfg  = (sc and sc.ui and sc.ui.floating) or {}
    local width  = resolve_size(size <= 1 and size or 0.5, vim.o.columns)
    local height = math.floor(vim.o.lines * 0.55)
    local row    = math.floor((vim.o.lines   - height) / 2)
    local col    = math.floor((vim.o.columns - width)  / 2)
    winnr = vim.api.nvim_open_win(buf, false, {
      relative  = "editor",
      width     = width,
      height    = height,
      row       = row,
      col       = col,
      style     = "minimal",
      border    = fcfg.border or "rounded",
      title     = " swank REPL ",
      title_pos = "center",
    })
    return
  end

  local is_vert = pos == "right" or pos == "left"
  local sz      = resolve_size(size, is_vert and vim.o.columns or vim.o.lines)
  local cmd     = pos == "right" and ("botright " .. sz .. "vsplit")
               or pos == "left"  and ("topleft "  .. sz .. "vsplit")
               or pos == "top"   and ("topleft "  .. sz .. "split")
               or                    ("botright " .. sz .. "split")

  vim.cmd(cmd)
  winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, buf)
  vim.cmd("wincmd p")  -- return focus to previous window
end

--- Toggle the REPL window open/closed
function M.toggle()
  if winnr and vim.api.nvim_win_is_valid(winnr) then
    vim.api.nvim_win_close(winnr, true)
    winnr = nil
  else
    open_win()
  end
end

--- Append raw text to the REPL output buffer, opening the window if needed
---@param text string
function M.append(text)
  local buf = ensure_buf()
  if not winnr or not vim.api.nvim_win_is_valid(winnr) then
    open_win()
  end
  vim.bo[buf].modifiable = true
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  vim.bo[buf].modifiable = false
  if winnr and vim.api.nvim_win_is_valid(winnr) then
    vim.api.nvim_win_set_cursor(winnr, { vim.api.nvim_buf_line_count(buf), 0 })
  end
end

--- Show the expression that was sent (visual prompt line)
---@param text string
function M.show_input(text)
  M.append("; " .. text:gsub("\n", "\n; ") .. "\n")
end

--- Show a Swank :return result in the REPL buffer
---@param result any  parsed :return payload
function M.show_result(result)
  if type(result) ~= "table" then return end
  local tag = tostring(result[1] or ""):lower()
  if tag == ":ok" then
    local val = result[2]
    if type(val) == "table" then
      local output = tostring(val[1] or "")
      local value  = tostring(val[2] or "")
      if output ~= "" then M.append(output) end
      M.append("=> " .. value .. "\n")
    else
      M.append("=> " .. tostring(val or "") .. "\n")
    end
  elseif tag == ":abort" then
    M.append("; Aborted" .. (result[2] and (": " .. tostring(result[2])) or "") .. "\n")
  end
  M.append("\n")
end

return M
