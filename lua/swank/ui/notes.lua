-- swank.nvim — compiler notes → vim.diagnostic
-- Receives :compilation-result from swank:compile-file / compile-string-for-emacs
-- and surfaces notes as native Neovim diagnostics.

local M = {}

local NS = vim.api.nvim_create_namespace("swank.nvim")

local severity_map = {
  [":error"]         = vim.diagnostic.severity.ERROR,
  [":read-error"]    = vim.diagnostic.severity.ERROR,
  [":warning"]       = vim.diagnostic.severity.WARN,
  [":style-warning"] = vim.diagnostic.severity.HINT,
  [":note"]          = vim.diagnostic.severity.INFO,
}

--- Convert a flat plist list to a Lua table
local function plist(lst)
  local t = {}
  if type(lst) ~= "table" then return t end
  local i = 1
  while i < #lst do
    t[tostring(lst[i] or ""):lower()] = lst[i + 1]
    i = i + 2
  end
  return t
end

--- Extract (file, line) from a Swank location s-expr
--- Location format: (:location (:file "path") (:line N col) nil)
---                  or (:error "no source location")
local function extract_location(loc)
  if type(loc) ~= "table" then return nil, nil end
  local tag = tostring(loc[1] or ""):lower()
  if tag ~= ":location" then return nil, nil end
  local file, line
  for _, part in ipairs(loc) do
    if type(part) == "table" then
      local ptag = tostring(part[1] or ""):lower()
      if ptag == ":file" then
        file = tostring(part[2] or "")
      elseif ptag == ":line" then
        line = tonumber(part[2])
      end
    end
  end
  return file, line
end

--- Map Swank compilation result notes to vim.diagnostic entries
---@param result any  (:ok (:compilation-result notes success duration load fasls)) or (:abort ...)
---@param source_path string  the file being compiled (used for diagnostics when note has no location)
function M.show(result, source_path)
  if type(result) ~= "table" then return end
  local tag = tostring(result[1] or ""):lower()
  if tag ~= ":ok" then
    vim.notify("swank.nvim: compilation aborted", vim.log.levels.WARN)
    return
  end

  local cr = result[2]
  if type(cr) ~= "table" then return end
  local cr_tag = tostring(cr[1] or ""):lower()
  if cr_tag ~= ":compilation-result" then return end

  -- cr = (:compilation-result notes successp duration loadp fasls-replaced)
  local notes   = cr[2]  -- list of note plists
  local success = cr[3]  -- t/nil

  -- Group diagnostics by file
  ---@type table<string, vim.Diagnostic[]>
  local by_file = {}

  if type(notes) == "table" then
    for _, raw_note in ipairs(notes) do
      if type(raw_note) == "table" then
        local note = plist(raw_note)
        local msg      = tostring(note[":message"] or "unknown")
        local sev_key  = tostring(note[":severity"] or ":note"):lower()
        local severity = severity_map[sev_key] or vim.diagnostic.severity.INFO
        local loc      = note[":location"]
        local file, line = extract_location(loc)
        file = file or source_path or ""
        line = (line or 1) - 1  -- vim.diagnostic uses 0-indexed rows

        if file ~= "" then
          by_file[file] = by_file[file] or {}
          table.insert(by_file[file], {
            lnum     = math.max(line, 0),
            col      = 0,
            severity = severity,
            message  = msg,
            source   = "swank",
          })
        end
      end
    end
  end

  -- Clear old diagnostics in this namespace for all tracked buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    vim.diagnostic.reset(NS, bufnr)
  end

  -- Set new diagnostics per file
  local any = false
  for file, diags in pairs(by_file) do
    local bufnr = vim.fn.bufnr(file)
    if bufnr ~= -1 then
      vim.diagnostic.set(NS, bufnr, diags)
      any = true
    end
  end

  if success then
    local n = 0
    for _, d in pairs(by_file) do n = n + #d end
    local msg = n == 0 and "compiled OK" or ("compiled with " .. n .. " note(s)")
    vim.notify("swank.nvim: " .. msg, n == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
  end
end

-- Exported for testing
M._plist = plist
M._extract_location = extract_location

return M
