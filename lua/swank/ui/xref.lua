-- swank.nvim — cross-reference UI
-- Uses native Telescope picker when Telescope is available; vim.ui.select for
-- other pickers (Snacks, Dressing, etc.); quickfix list as final fallback.

local M = {}

--- Extract (file, line) from a Swank location s-expr
--- (:location (:file "path") (:line N col) nil)
local function extract_location(loc)
  if type(loc) ~= "table" then return nil, nil end
  if tostring(loc[1] or ""):lower() ~= ":location" then return nil, nil end
  local file, line
  for _, part in ipairs(loc) do
    if type(part) == "table" then
      local tag = tostring(part[1] or ""):lower()
      if tag == ":file" then file = part[2] ~= nil and tostring(part[2]) or nil
      elseif tag == ":line" then line = tonumber(part[2]) end
    end
  end
  return file, line
end

--- Build quickfix entries from a list of (name location) pairs
local function refs_to_qflist(refs, kind)
  local qf = {}
  for _, ref in ipairs(refs) do
    if type(ref) == "table" then
      local name = tostring(ref[1] or "")
      local loc  = ref[2]
      local file, line = extract_location(loc)
      if file and file ~= "" then
        table.insert(qf, {
          filename = file,
          lnum     = line or 1,
          text     = kind .. ": " .. name,
        })
      end
    end
  end
  return qf
end

local function jump_to(entry)
  vim.cmd("edit " .. vim.fn.fnameescape(entry.filename))
  vim.schedule(function()
    local line_count = vim.api.nvim_buf_line_count(0)
    local lnum = math.max(1, math.min(entry.lnum, line_count))
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  end)
end

--- Returns true if something (telescope-ui-select, snacks, dressing, etc.)
--- has replaced the default vim.ui.select implementation.
local function ui_select_is_hooked()
  local ok, info = pcall(debug.getinfo, vim.ui.select, "S")
  if not ok or type(info) ~= "table" or type(info.source) ~= "string" then
    return false
  end
  local source = info.source
  if source:sub(1, 1) == "@" then source = source:sub(2) end
  source = source:gsub("\\", "/"):lower()
  return source:find("vim/ui.lua", 1, true) == nil
end

--- Open a native Telescope picker for xref results.
--- This bypasses vim.ui.select / telescope-ui-select entirely. That wrapper
--- has a bug where it tries to set cursor to self.max_results in the results
--- buffer (which has fewer lines than max_results for small result sets) after
--- scheduling our callback — causing "Invalid cursor line: out of range".
--- Using the native picker API with attach_mappings + actions.close is the
--- correct pattern: close() completes before we touch any buffers.
local function show_with_telescope(entries, kind)
  local pickers      = require("telescope.pickers")
  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title = "swank: " .. kind,
    finder = finders.new_table({
      results = entries,
      entry_maker = function(e)
        return {
          value   = e,
          display = e.text .. "  " .. e.filename .. ":" .. e.lnum,
          ordinal = e.text .. " " .. e.filename,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then jump_to(entry.value) end
      end)
      return true
    end,
  }):find()
end

--- Show cross-reference results
---@param result any  (:ok refs) from swank:xref or swank:find-definitions-for-emacs
---@param kind string  "calls" | "references" | "definition"
function M.show(result, kind)
  if type(result) ~= "table" then return end
  local tag = tostring(result[1] or ""):lower()
  if tag ~= ":ok" then
    vim.notify("swank.nvim: xref failed", vim.log.levels.WARN)
    return
  end

  local refs = result[2]
  if type(refs) ~= "table" or #refs == 0 then
    vim.notify("swank.nvim: no " .. kind .. " found", vim.log.levels.INFO)
    return
  end

  -- find-definitions returns a flat list of (name location) pairs
  -- xref returns ((:calls ((name loc) ...))) — one level deeper
  local pairs_list = refs
  if type(refs[1]) == "table" and type(refs[1][1]) == "table" then
    pairs_list = refs[1][2] or {}
  end

  local entries = refs_to_qflist(pairs_list, kind)
  if #entries == 0 then
    vim.notify("swank.nvim: no source locations for " .. kind, vim.log.levels.INFO)
    return
  end

  -- Single result → jump directly, no picker needed
  if #entries == 1 then
    jump_to(entries[1])
    return
  end

  -- Multiple results — prefer native Telescope picker (bypasses the
  -- telescope-ui-select bug), then vim.ui.select for other pickers
  -- (Snacks etc. close before calling our callback so defer_fn is safe),
  -- then quickfix as the final fallback.
  local has_telescope = pcall(require, "telescope")
  if has_telescope then
    show_with_telescope(entries, kind)
  elseif ui_select_is_hooked() then
    vim.ui.select(entries, {
      prompt      = "swank: " .. kind,
      format_item = function(e) return e.text .. "  " .. e.filename .. ":" .. e.lnum end,
    }, function(choice)
      if choice then
        vim.defer_fn(function() jump_to(choice) end, 50)
      end
    end)
  else
    vim.fn.setqflist({}, "r", { title = "swank: " .. kind, items = entries })
    vim.cmd("copen")
  end
end

-- Exported for testing
M._extract_location     = extract_location
M._refs_to_qflist       = refs_to_qflist
M._ui_select_is_hooked  = ui_select_is_hooked

return M
