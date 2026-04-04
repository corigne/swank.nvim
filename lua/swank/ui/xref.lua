-- swank.nvim — cross-reference UI
-- Displays xref results in quickfix or jumps directly for single hits.

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
      if tag == ":file" then file = tostring(part[2] or "")
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
      if file then
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
    -- xref format: wrapped in a kind-keyed list
    pairs_list = refs[1][2] or {}
  end

  local qf = refs_to_qflist(pairs_list, kind)

  if #qf == 0 then
    vim.notify("swank.nvim: no source locations for " .. kind, vim.log.levels.INFO)
    return
  end

  -- Single definition → jump directly; multiple → open quickfix
  if kind == "definition" and #qf == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(qf[1].filename))
    vim.api.nvim_win_set_cursor(0, { qf[1].lnum, 0 })
  else
    vim.fn.setqflist({}, "r", { title = "swank:" .. kind, items = qf })
    vim.cmd("copen")
  end
end

return M
