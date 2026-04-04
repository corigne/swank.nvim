-- swank.nvim — REPL output buffer UI
-- Manages a persistent output buffer for Swank REPL interaction.

local M = {}

---@type integer|nil
local bufnr = nil
---@type integer|nil
local winnr = nil

local function ensure_buf()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then return bufnr end
  bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = "swank-repl"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].modifiable = false
  vim.api.nvim_buf_set_name(bufnr, "swank://repl")
  return bufnr
end

local function open_win()
  local cfg = require("swank").config.ui.repl
  local pos = cfg.position
  local size = cfg.size

  local cmd = pos == "right" and ("botright " .. size .. "vsplit")
    or pos == "left"  and ("topleft "  .. size .. "vsplit")
    or pos == "top"   and ("topleft "  .. size .. "split")
    or ("botright " .. size .. "split")

  vim.cmd(cmd)
  winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, ensure_buf())
  -- Return focus to previous window
  vim.cmd("wincmd p")
end

--- Toggle the REPL window open/closed
function M.toggle()
  if winnr and vim.api.nvim_win_is_valid(winnr) then
    vim.api.nvim_win_close(winnr, false)
    winnr = nil
  else
    open_win()
  end
end

--- Append raw text to the REPL output buffer
---@param text string
function M.append(text)
  local buf = ensure_buf()
  vim.bo[buf].modifiable = true
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  vim.bo[buf].modifiable = false
  -- Scroll to bottom if REPL window is visible
  if winnr and vim.api.nvim_win_is_valid(winnr) then
    local line_count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(winnr, { line_count, 0 })
  end
end

--- Show a Swank :return result in the REPL buffer
---@param result any  parsed :return payload (:ok value) or (:abort condition)
function M.show_result(result)
  if type(result) ~= "table" then return end
  local tag = tostring(result[1] or ""):lower()
  if tag == ":ok" then
    M.append("=> " .. tostring(result[2] or "") .. "\n")
  elseif tag == ":abort" then
    M.append("; Aborted: " .. tostring(result[2] or "") .. "\n")
  end
end

return M
