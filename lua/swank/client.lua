-- swank.nvim — high-level Swank client
-- Manages connection lifecycle, emacs-rex call/response, and event routing.

local M = {}

local transport_mod = require("swank.transport")
local protocol = require("swank.protocol")

---@type SwankTransport|nil
local transport = nil

---@type "disconnected"|"connecting"|"connected"
local connection_state = "disconnected"

---@type integer|nil  jobstart job id for the sbcl process
local sbcl_job_id = nil

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
  if connection_state ~= "disconnected" then
    vim.notify("swank.nvim: already connected or connecting", vim.log.levels.WARN)
    return
  end
  local cfg = require("swank").config
  host = host or cfg.server.host
  port = port or cfg.server.port
  connection_state = "connecting"

  transport = transport_mod.Transport.new(
    function(raw)  -- on_message
      local msg = protocol.parse(raw)
      if msg then protocol.dispatch(msg) end
    end,
    function()     -- on_disconnect
      transport = nil
      connection_state = "disconnected"
      vim.notify("swank.nvim: disconnected", vim.log.levels.WARN)
    end
  )

  transport:connect(host, port, function(err)
    if err then
      vim.notify("swank.nvim: connection failed — " .. err, vim.log.levels.ERROR)
      transport = nil
      connection_state = "disconnected"
      return
    end
    connection_state = "connected"
    vim.notify("swank.nvim: connected to " .. host .. ":" .. port, vim.log.levels.INFO)
    M._on_connect()
  end)
end

--- Spawn SBCL with Swank, detect port from file, then connect
function M.start_and_connect()
  if connection_state ~= "disconnected" then return end

  local cache_dir = vim.fn.stdpath("cache") .. "/swank.nvim"
  vim.fn.mkdir(cache_dir, "p")
  local port_file = cache_dir .. "/swank-port"
  local script_file = cache_dir .. "/start-swank.lisp"
  vim.fn.delete(port_file)

  local escaped = port_file:gsub("\\", "\\\\"):gsub('"', '\\"')
  local script = string.format([[
(require :asdf)
#-quicklisp
(let ((qs (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file qs) (load qs)))
(handler-case
    (progn #+quicklisp (ql:quickload :swank :silent t)
           #-quicklisp (require :swank))
  (error (e)
    (format *error-output* "swank.nvim: ~a~%%" e)
    (uiop:quit 1)))
(setf swank::*swank-debug-p* nil)
(let ((port (swank:create-server :port 0 :dont-close t)))
  (with-open-file (s (pathname "%s") :direction :output :if-exists :supersede)
    (format s "~d" port))
  (loop (sleep 60)))
]], escaped)

  local f = io.open(script_file, "w")
  if not f then
    vim.notify("swank.nvim: cannot write startup script", vim.log.levels.ERROR)
    return
  end
  f:write(script)
  f:close()

  local impl = require("swank").config.autostart.implementation
  connection_state = "connecting"
  vim.notify("swank.nvim: starting " .. impl .. "…", vim.log.levels.INFO)

  sbcl_job_id = vim.fn.jobstart(
    { impl, "--noinform", "--non-interactive", "--load", script_file },
    {
      on_stderr = function(_, data)
        for _, line in ipairs(data) do
          if line ~= "" then
            vim.notify("sbcl: " .. line, vim.log.levels.WARN)
          end
        end
      end,
      on_exit = function(_, code)
        sbcl_job_id = nil
        if connection_state ~= "connected" then
          connection_state = "disconnected"
          vim.notify("swank.nvim: sbcl exited (code " .. code .. ")", vim.log.levels.ERROR)
        end
      end,
    }
  )

  if sbcl_job_id <= 0 then
    connection_state = "disconnected"
    vim.notify("swank.nvim: failed to start " .. impl, vim.log.levels.ERROR)
    return
  end

  -- Poll for port file (500ms × 60 = 30s timeout)
  local attempts = 0
  local timer = vim.uv.new_timer()
  timer:start(500, 500, vim.schedule_wrap(function()
    attempts = attempts + 1
    local pf = io.open(port_file, "r")
    if pf then
      local port_str = pf:read("*l")
      pf:close()
      timer:stop()
      timer:close()
      local port = tonumber(port_str)
      if port then
        connection_state = "disconnected"  -- let connect() proceed
        M.connect("127.0.0.1", port)
      else
        connection_state = "disconnected"
        vim.notify("swank.nvim: malformed port file", vim.log.levels.ERROR)
      end
    elseif attempts >= 60 then
      timer:stop()
      timer:close()
      connection_state = "disconnected"
      vim.notify("swank.nvim: timed out waiting for Swank server", vim.log.levels.ERROR)
    end
  end))
end

--- Disconnect and optionally stop the sbcl process
function M.disconnect()
  if transport then
    transport:disconnect()
    transport = nil
  end
  connection_state = "disconnected"
  if sbcl_job_id then
    vim.fn.jobstop(sbcl_job_id)
    sbcl_job_id = nil
  end
  vim.notify("swank.nvim: disconnected", vim.log.levels.INFO)
end

---@return boolean
function M.is_connected()
  return connection_state == "connected"
end

-- ---------------------------------------------------------------------------
-- Low-level RPC
-- ---------------------------------------------------------------------------

--- Send an :emacs-rex call and register a callback for the response
---@param form table      s-expression as a Lua table
---@param cb fun(result: any)
---@param pkg string|nil  package context
---@param thread any|nil  thread id from :debug (nil → true, meaning Swank picks)
function M.rex(form, cb, pkg, thread)
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
    thread ~= nil and thread or true,
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

protocol.on(":debug-activate", function(_) end)

protocol.on(":debug-return", function(_)
  require("swank.ui.sldb").close()
end)

protocol.on(":new-features", function(_) end)

protocol.on(":indentation-update", function(_) end)

protocol.on(":ping", function(msg)
  -- Swank keepalive; respond with :emacs-pong
  if transport then
    local payload = protocol.serialize({ ":emacs-pong", msg[2], msg[3] })
    transport:send(payload)
  end
end)

-- SWANK-TRACE-DIALOG events
protocol.on(":trace-dialog-update", function(msg)
  -- msg = (:trace-dialog-update specs entries)
  -- specs is a list of traced spec names; entries is a list of trace records
  local specs   = type(msg[2]) == "table" and msg[2] or {}
  local batch   = type(msg[3]) == "table" and msg[3] or {}
  local trace   = require("swank.ui.trace")
  trace.set_specs(specs)
  trace.push_entries(batch)
end)

-- ---------------------------------------------------------------------------
-- Eval operations
-- ---------------------------------------------------------------------------

--- Eval the top-level form under the cursor
function M.eval_toplevel()
  local form = M._form_at_cursor()
  if not form or form == "" then return end
  require("swank.ui.repl").show_input(form)
  M.rex({ "swank:eval-and-grab-output", form }, function(result)
    require("swank.ui.repl").show_result(result)
  end)
end

--- Eval visually selected region
function M.eval_region()
  local lines = M._get_visual_selection()
  if not lines then return end
  require("swank.ui.repl").show_input(lines)
  M.rex({ "swank:eval-and-grab-output", lines }, function(result)
    require("swank.ui.repl").show_result(result)
  end)
end

--- Eval with interactive input via vim.ui.input
function M.eval_interactive()
  vim.ui.input({ prompt = "Eval: " }, function(input)
    if not input or input == "" then return end
    require("swank.ui.repl").show_input(input)
    M.rex({ "swank:eval-and-grab-output", input }, function(result)
      require("swank.ui.repl").show_result(result)
    end)
  end)
end

--- Describe a symbol by name
---@param sym string
function M.describe(sym)
  M.rex({ "swank:describe-symbol", sym }, function(result)
    if type(result) == "table" and result[1] == ":ok" then
      require("swank.ui.repl").append(tostring(result[2] or "") .. "\n")
    end
  end)
end

--- Run an apropos query and display formatted results in the REPL
---@param query string
function M.apropos(query)
  M.rex({ "swank:apropos-list-for-emacs", query, false, false, nil }, function(result)
    if type(result) ~= "table" or result[1] ~= ":ok" then return end
    local entries = result[2]
    if type(entries) ~= "table" or #entries == 0 then
      require("swank.ui.repl").append("; no apropos matches for: " .. query .. "\n")
      return
    end
    local lines = { "; Apropos: " .. query }
    for _, entry in ipairs(entries) do
      if type(entry) == "table" then
        local e = M._plist(entry)
        local name = tostring(e[":designator"] or "")
        local kinds = {}
        if e[":function"]  then table.insert(kinds, "function") end
        if e[":macro"]     then table.insert(kinds, "macro") end
        if e[":variable"]  then table.insert(kinds, "variable") end
        if e[":type"]      then table.insert(kinds, "type") end
        if e[":class"]     then table.insert(kinds, "class") end
        local suffix = #kinds > 0 and ("  [" .. table.concat(kinds, ", ") .. "]") or ""
        table.insert(lines, "  " .. name .. suffix)
      end
    end
    require("swank.ui.repl").append(table.concat(lines, "\n") .. "\n\n")
  end)
end

--- Inspect a value by evaluating an expression string
---@param expr string  expression to evaluate and inspect (e.g. "*", "SOME-VAR")
function M.inspect_value(expr)
  M.rex({ "swank:init-inspector", expr }, function(result)
    require("swank.ui.inspector").open(result)
  end)
end

--- Navigate to the Nth part inside the current inspector view
---@param n integer  0-based index of the part to follow
function M.inspect_nth_part(n)
  M.rex({ "swank:inspect-nth-part", n }, function(result)
    require("swank.ui.inspector").open(result)
  end)
end

--- Go back to the previous inspector view
function M.inspector_pop()
  M.rex({ "swank:inspector-pop" }, function(result)
    if type(result) == "table" and result[1] == ":ok" and result[2] then
      require("swank.ui.inspector").open(result)
    else
      vim.notify("swank.nvim: already at the top of the inspector stack", vim.log.levels.INFO)
    end
  end)
end

--- Refresh the current inspector view
function M.inspector_reinspect()
  M.rex({ "swank:inspector-reinspect" }, function(result)
    require("swank.ui.inspector").open(result)
  end)
end

--- Quit the inspector
function M.quit_inspector()
  M.rex({ "swank:quit-inspector" }, function(_) end)
  require("swank.ui.inspector").close()
end

-- ---------------------------------------------------------------------------
-- Trace dialog operations (SWANK-TRACE-DIALOG contrib)
-- ---------------------------------------------------------------------------

--- Toggle tracing of a function by name
---@param sym string  function name, e.g. "MY-FUNC" or "my-package:my-func"
function M.trace_toggle(sym)
  M.rex({ "swank-trace-dialog:dialog-toggle-trace", sym }, function(result)
    local trace = require("swank.ui.trace")
    if type(result) == "table" and result[1] == ":ok" then
      local specs = type(result[2]) == "table" and result[2] or {}
      trace.set_specs(specs)
      local names = {}
      for _, s in ipairs(specs) do table.insert(names, tostring(s)) end
      vim.notify("swank.nvim: tracing " .. table.concat(names, ", "), vim.log.levels.INFO)
    end
  end)
end

--- Untrace all traced functions
function M.untrace_all()
  M.rex({ "swank-trace-dialog:dialog-untrace-all" }, function(result)
    if type(result) == "table" and result[1] == ":ok" then
      require("swank.ui.trace").set_specs({})
      vim.notify("swank.nvim: all functions untraced", vim.log.levels.INFO)
    end
  end)
end

--- Clear accumulated trace entries
function M.clear_traces()
  M.rex({ "swank-trace-dialog:clear-trace-tree" }, function(_)
    require("swank.ui.trace").clear()
  end)
end

--- Pull the latest trace entries from Swank and update the dialog
function M.refresh_traces()
  -- report-specs gives the list of traced names
  M.rex({ "swank-trace-dialog:report-specs" }, function(result)
    if type(result) == "table" and result[1] == ":ok" then
      require("swank.ui.trace").set_specs(
        type(result[2]) == "table" and result[2] or {})
    end
  end)
  -- report-partial-tree gives pending entries (pass 0 to get all since last)
  M.rex({ "swank-trace-dialog:report-partial-tree", 0 }, function(result)
    if type(result) == "table" and result[1] == ":ok" then
      require("swank.ui.trace").push_entries(
        type(result[2]) == "table" and result[2] or {})
    end
  end)
end

--- Load current file
function M.load_file()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("swank.nvim: buffer has no file path", vim.log.levels.WARN)
    return
  end
  M.rex({ "swank:load-file", path }, function(result)
    require("swank.ui.repl").show_result(result)
  end)
end

--- Compile current file
function M.compile_file()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("swank.nvim: buffer has no file path", vim.log.levels.WARN)
    return
  end
  M.rex({ "swank:compile-file", path, false }, function(result)
    require("swank.ui.notes").show(result, path)
  end)
end

--- Compile form at cursor
function M.compile_form()
  local form = M._form_at_cursor()
  if not form or form == "" then return end
  local bufname = vim.api.nvim_buf_get_name(0)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  M.rex({ "swank:compile-string-for-emacs", form, bufname, col, row, nil }, function(result)
    require("swank.ui.notes").show(result, bufname)
  end)
end

--- Switch package interactively
function M.set_package_interactive()
  vim.ui.input({ prompt = "Package: ", default = current_package }, function(pkg)
    if not pkg or pkg == "" then return end
    M.rex({ "swank:set-package", pkg:upper() }, function(result)
      if type(result) == "table" and result[1] == ":ok" then
        current_package = pkg:upper()
        vim.notify("swank.nvim: package → " .. current_package, vim.log.levels.INFO)
      end
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Arglist autodoc
-- ---------------------------------------------------------------------------

--- Show arglist for the innermost operator at cursor in the echo area
function M.autodoc()
  if not M.is_connected() then return end
  local sym = M._innermost_operator()
  if not sym or sym == "" then return end
  M.rex(
    { "swank:operator-arglist", sym, current_package },
    function(result)
      if type(result) == "table" and result[1] == ":ok" and result[2] then
        vim.api.nvim_echo({ { sym .. ": " .. tostring(result[2]), "Comment" } }, false, {})
      end
    end
  )
end

-- XRef
---@param sym string
function M.xref_calls(sym)
  M.rex({ "swank:xref", ":calls", sym }, function(r) require("swank.ui.xref").show(r, "calls") end)
end

---@param sym string
function M.xref_references(sym)
  M.rex({ "swank:xref", ":references", sym }, function(r) require("swank.ui.xref").show(r, "references") end)
end

---@param sym string
function M.find_definition(sym)
  M.rex({ "swank:find-definitions-for-emacs", sym }, function(r) require("swank.ui.xref").show(r, "definition") end)
end

-- ---------------------------------------------------------------------------
-- Post-connect initialisation
-- ---------------------------------------------------------------------------

function M._on_connect()
  local cfg = require("swank").config

  -- 1. Get connection info (implementation name + version)
  M.rex({ "swank:connection-info" }, function(result)
    if type(result) == "table" and result[1] == ":ok" and type(result[2]) == "table" then
      local info = M._plist(result[2])
      local impl = M._plist(info[":lisp-implementation"] or {})
      local name = impl[":name"] or "Unknown Lisp"
      local version = impl[":version"] or ""
      vim.notify("swank.nvim: " .. name .. " " .. version, vim.log.levels.INFO)
    end
  end)

  -- 2. Load contribs (quoted list of keyword symbols, e.g. :swank-repl)
  M.rex({
    "swank:swank-require",
    { "QUOTE", cfg.contribs },
  }, function(_)
    M.rex({ "swank:set-package", current_package }, function(_) end)
  end)
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Get the top-level form containing the cursor (treesitter → paren fallback)
function M._form_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "commonlisp")
  if ok and parser then
    local tree = parser:parse()[1]
    if tree then
      local root = tree:root()
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      row = row - 1
      local node = root:named_descendant_for_range(row, col, row, col)
      while node and node:parent() and node:parent() ~= root do
        node = node:parent()
      end
      if node then
        return vim.treesitter.get_node_text(node, bufnr)
      end
    end
  end
  return M._form_at_cursor_paren()
end

--- Bracket-aware top-level form scanner (used when treesitter unavailable)
function M._form_at_cursor_paren()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local form_start = cursor_row
  for i = cursor_row, 1, -1 do
    if all_lines[i]:match("^%(") then
      form_start = i
      break
    end
  end

  local collected = {}
  local depth, in_str, esc = 0, false, false
  for i = form_start, #all_lines do
    local line = all_lines[i]
    table.insert(collected, line)
    for j = 1, #line do
      local c = line:sub(j, j)
      if esc then
        esc = false
      elseif in_str then
        if c == "\\" then esc = true
        elseif c == '"' then in_str = false end
      else
        if c == '"' then in_str = true
        elseif c == ";" then break
        elseif c == "(" then depth = depth + 1
        elseif c == ")" then
          depth = depth - 1
          if depth == 0 then return table.concat(collected, "\n") end
        end
      end
    end
  end
  return table.concat(collected, "\n")
end

function M._get_visual_selection()
  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(0, s[2] - 1, e[2], false)
  if #lines == 0 then return nil end
  return table.concat(lines, "\n")
end

--- Find the operator (first symbol) of the innermost list at cursor
---@return string|nil
function M._innermost_operator()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local depth = 0
  for i = col, 1, -1 do
    local c = line:sub(i, i)
    if c == ")" then
      depth = depth + 1
    elseif c == "(" then
      if depth == 0 then
        return line:sub(i + 1):match("^%s*([%a%d:%-_%+%*%?%!%@%$%^%&%=%<%>%/%%|~#]+)")
      end
      depth = depth - 1
    end
  end
  return nil
end

--- Returns true if text looks like a single CL symbol (no whitespace, valid chars).
--- Used to guard describe/apropos so they don't fire on garbage selections.
---@param text string|nil
---@return boolean
function M._is_symbol_like(text)
  if not text or text == "" then return false end
  local trimmed = text:match("^%s*(.-)%s*$")
  if trimmed == "" or trimmed:find("%s") then return false end
  -- Reject bare numbers (integers and floats) — not valid symbol names
  if trimmed:match("^%-?%d+%.?%d*$") then return false end
  -- Must contain only valid CL symbol chars: letters, digits, and punctuation
  -- used in CL identifiers. Colon allowed for package-qualified names.
  return trimmed:match("^[%a%d%+%-%*%/%@%$%%%%^%&%_%=%<%>%~%.%!%?%|:#]+$") ~= nil
end

--- Convert a flat plist to a Lua table keyed by lowercased keyword
---@param lst table
---@return table
function M._plist(lst)
  local t = {}
  if type(lst) ~= "table" then return t end
  local i = 1
  while i < #lst do
    t[tostring(lst[i] or ""):lower()] = lst[i + 1]
    i = i + 2
  end
  return t
end

return M
