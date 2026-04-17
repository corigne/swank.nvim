-- swank.nvim — high-level Swank client
-- Manages connection lifecycle, emacs-rex call/response, and event routing.

local M = {}

local transport_mod = require("swank.transport")
local protocol = require("swank.protocol")

---@type SwankTransport|nil
local transport = nil

---@type "disconnected"|"connecting"|"connected"
local connection_state = "disconnected"

---@type integer|nil  jobstart job id for the CL implementation process
local impl_job_id = nil

---@type string[]  stderr lines collected during implementation startup; shown only on error exit
local stderr_log = {}
---@type integer  monotonically increasing message ID
local msg_id = 0

---@type table<integer, fun(result: any)>  pending RPC callbacks
local callbacks = {}

---@type integer  count of in-flight "silent" rex calls; suppresses :write-string while > 0
local silent_count = 0

---@type string  current package context
local current_package = "COMMON-LISP-USER"

-- ---------------------------------------------------------------------------
-- REPL input history (ring buffer)
-- ---------------------------------------------------------------------------

local HISTORY_MAX = 100
---@type string[]  ordered oldest-first; newest at [#history]
local history = {}
---@type integer  0 = not browsing; positive = index from end being browsed
local history_pos = 0

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

--- CLI flags for each supported CL implementation.
--- The flags suppress banners/interactivity and load a file.
--- Unknown implementations fall back to SBCL-style flags.
---@type table<string, string[]>
local impl_cli_flags = {
  sbcl  = { "--noinform", "--non-interactive", "--load" },
  ccl   = { "--quiet", "--batch", "--load" },
  ecl   = { "--norc", "--load" },
  abcl  = { "--batch", "--load" },
}

--- Spawn the configured CL implementation with Swank, detect port from file, then connect
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
  -- Build argv: binary + quiet/batch flags + "--load" + script
  local impl_name = vim.fn.fnamemodify(impl, ":t"):lower()
  local flags = impl_cli_flags[impl_name] or impl_cli_flags.sbcl
  -- flags ends with "--load"; append the script path
  local argv = { impl }
  for _, flag in ipairs(flags) do table.insert(argv, flag) end
  table.insert(argv, script_file)

  connection_state = "connecting"
  vim.notify("swank.nvim: starting " .. impl .. "…", vim.log.levels.INFO)

  impl_job_id = vim.fn.jobstart(
    argv,
    {
      on_stderr = function(_, data)
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_log, line)
          end
        end
      end,
      on_exit = function(_, code)
        impl_job_id = nil
        if connection_state ~= "connected" then
          connection_state = "disconnected"
          local tail = table.concat(stderr_log, "\n")
          vim.notify(
            "swank.nvim: " .. impl .. " exited (code " .. code .. ")\n" .. tail,
            vim.log.levels.ERROR
          )
        end
        stderr_log = {}
      end,
    }
  )

  if impl_job_id <= 0 then
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

--- Disconnect and optionally stop the CL implementation process
function M.disconnect()
  if transport then
    transport:disconnect()
    transport = nil
  end
  connection_state = "disconnected"
  if impl_job_id then
    vim.fn.jobstop(impl_job_id)
    impl_job_id = nil
  end
  vim.notify("swank.nvim: disconnected", vim.log.levels.INFO)
end

---@return boolean
function M.is_connected()
  return connection_state == "connected"
end

function M.get_package()
  return current_package
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

--- Like rex, but suppresses any :write-string output produced as a side effect.
--- Use for background queries (describe-symbol, operator-arglist) that should
--- not pollute the REPL or the message area.
---@param form table
---@param cb fun(result: any)
---@param pkg string|nil
---@param thread any|nil
function M.silent_rex(form, cb, pkg, thread)
  silent_count = silent_count + 1
  M.rex(form, function(result)
    silent_count = math.max(0, silent_count - 1)
    cb(result)
  end, pkg, thread)
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
  if silent_count > 0 then return end
  require("swank.ui.repl").append(msg[2] or "")
end)

protocol.on(":debug", function(msg)
  -- Suppress debugger activation caused by background 'silent' rex calls
  if silent_count > 0 then
    local ok_swank, swank_mod = pcall(require, "swank")
    if ok_swank and swank_mod.config and swank_mod.config.debug then
      pcall(function()
        local fp = io.open("/tmp/swank_silent_debug_events.log", "a")
        if fp then
          fp:write(os.date("%FT%T") .. " suppressed :debug — payload=" .. tostring(msg[2]) .. "\n")
          fp:close()
        end
      end)
    end
    return
  end
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
    M.history_push(input)
    require("swank.ui.repl").show_input(input)
    M.rex({ "swank:eval-and-grab-output", input }, function(result)
      require("swank.ui.repl").show_result(result)
    end)
  end)
end

--- Describe a symbol by name
---@param sym string
function M.describe(sym)
  -- Sanitize common reader prefixes and whitespace; validate symbol-like input.
  if not sym then return end
  local raw_token = tostring(sym)
  local s = raw_token
  -- Strip #', leading quotes/backticks/commas produced by some editors/completions
  s = s:gsub("^#'", ""):gsub("^['`%,]+", "")
  s = s:match("^%s*(.-)%s*$") or s

  -- Debug log raw->sanitized (only when config.debug)
  local ok_swank, swank_mod = pcall(require, "swank")
  if ok_swank and swank_mod.config and swank_mod.config.debug then
    local ok, f = pcall(io.open, "/tmp/swank_sanitize_debug.log", "a")
    if ok and f then
      pcall(function()
        f:write(os.date("%FT%T") .. " raw=" .. tostring(raw_token) .. " sanitized=" .. tostring(s) .. "\n")
        f:close()
      end)
    end
  end

  if not M._is_symbol_like(s) then return end

  -- Use silent_rex so any side-effect :write-string output (e.g. "Unknown symbol:") is suppressed
  M.silent_rex({ "swank:describe-symbol", s }, function(result)
    if type(result) ~= "table" or result[1] ~= ":ok" then return end
    local text = tostring(result[2] or ""):gsub("\r", "")
    local lines = vim.split(text, "\n", { plain = true })
    while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
    if #lines == 0 then return end
    local width = 0
    for _, l in ipairs(lines) do width = math.max(width, #l) end
    width = math.min(math.max(width, 40), math.floor(vim.o.columns * 0.7))
    local height = math.min(#lines, math.floor(vim.o.lines * 0.5))
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "swank-describe"
    vim.bo[buf].buftype  = "nofile"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    local c = require("swank").config
    local fcfg = (c and c.ui and c.ui.floating) or {}
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "cursor",
      row = 1, col = 0,
      width = width, height = height,
      style = "minimal",
      border = fcfg.border or "rounded",
      title = " " .. s .. " ",
      title_pos = "center",
    })
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].wrap = true
    end
    -- close on any cursor movement or buffer leave
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
      once = true,
      callback = function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      end,
    })
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
  M.rex({ "swank:compile-file-for-emacs", path, false }, function(result)
    require("swank.ui.notes").show(result, path)
  end)
end

--- Compile form at cursor
function M.compile_form()
  local form = M._form_at_cursor()
  if not form or form == "" then return end
  local bufname = vim.api.nvim_buf_get_name(0)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  -- position must be a quoted list of location specs matching SLIME's format:
  -- '((:line L COL)) -- lists are not self-evaluating in CL, so QUOTE is required.
  local position = { "QUOTE", { { ":line", row, col } } }
  M.rex({ "swank:compile-string-for-emacs", form, bufname, position, false, false }, function(result)
    require("swank.ui.notes").show(result, bufname)
  end)
end

-- ---------------------------------------------------------------------------
-- Macro expansion
-- ---------------------------------------------------------------------------

--- Display a macro expansion in a scratch buffer
---@param expanded string  the expanded form text
---@param title string     window title
local function show_expansion(expanded, title)
  local lines = vim.split(expanded:gsub("\r", ""), "\n", { plain = true })
  while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
  if #lines == 0 then
    vim.notify("swank.nvim: empty expansion", vim.log.levels.INFO)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype   = "lisp"
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].modifiable = false
  -- Wipe any stale buffer with the same name to avoid E95
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= buf and vim.api.nvim_buf_get_name(b) == "swank://macroexpand" then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  vim.api.nvim_buf_set_name(buf, "swank://macroexpand")
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width  = math.min(math.max(80, vim.o.columns - 20), vim.o.columns)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  local c    = require("swank").config
  local fcfg = (c and c.ui and c.ui.floating) or {}
  local win  = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = fcfg.border or "rounded",
    title     = " " .. title .. " ",
    title_pos = "center",
  })
  if vim.api.nvim_win_is_valid(win) then
    vim.wo[win].wrap = true
  end
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end, { buffer = buf, silent = true, desc = "Close macro expansion" })
end

--- Expand the macro form at cursor once (macroexpand-1)
function M.macroexpand_1()
  local form = M._form_at_cursor()
  if not form or form == "" then return end
  M.rex({ "swank:macroexpand-1", form }, function(result)
    if type(result) ~= "table" or result[1] ~= ":ok" then return end
    show_expansion(tostring(result[2] or ""), "macroexpand-1")
  end)
end

--- Fully expand the macro form at cursor (macroexpand-all)
function M.macroexpand()
  local form = M._form_at_cursor()
  if not form or form == "" then return end
  M.rex({ "swank:macroexpand-all", form }, function(result)
    if type(result) ~= "table" or result[1] ~= ":ok" then return end
    show_expansion(tostring(result[2] or ""), "macroexpand-all")
  end)
end

--- Disassemble a symbol or form and display in a floating scratch buffer
---@param sym? string  defaults to word under cursor
function M.disassemble(sym)
  local target = sym or vim.fn.expand("<cword>")
  if not target or target == "" then return end
  M.rex({ "swank:disassemble-form", target }, function(result)
    if type(result) ~= "table" or result[1] ~= ":ok" then
      vim.notify("swank.nvim: disassemble failed", vim.log.levels.WARN)
      return
    end
    local asm = tostring(result[2] or "")
    show_expansion(asm, "disassemble: " .. target)
  end)
end

-- ---------------------------------------------------------------------------
-- Profiling
-- ---------------------------------------------------------------------------

--- Toggle profiling on a named function
---@param sym? string  defaults to word under cursor
function M.profile(sym)
  local target = sym or vim.fn.expand("<cword>")
  if not target or target == "" then return end
  M.rex({ "swank:profile-fdefinition", target }, function(result)
    if type(result) == "table" and result[1] == ":ok" then
      vim.notify("swank.nvim: profiling " .. target, vim.log.levels.INFO)
    else
      vim.notify("swank.nvim: profile failed for " .. target, vim.log.levels.WARN)
    end
  end)
end

--- Remove profiling from all functions
function M.unprofile_all()
  M.rex({ "swank:unprofile-all" }, function(result)
    if type(result) == "table" and result[1] == ":ok" then
      vim.notify("swank.nvim: all functions unprofiled", vim.log.levels.INFO)
    end
  end)
end

--- Show profiling report in a scratch buffer
function M.profile_report()
  M.rex({ "swank:profile-report" }, function(result)
    if type(result) ~= "table" or result[1] ~= ":ok" then
      vim.notify("swank.nvim: profile-report failed", vim.log.levels.WARN)
      return
    end
    show_expansion(tostring(result[2] or ""), "profile-report")
  end)
end

--- Reset all profiling counters
function M.profile_reset()
  M.rex({ "swank:profile-reset" }, function(result)
    if type(result) == "table" and result[1] == ":ok" then
      vim.notify("swank.nvim: profiling counters reset", vim.log.levels.INFO)
    end
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
-- Accept an optional 'force' argument: when true, run even in insert mode.
function M.autodoc(force)
  -- Don't auto-show in insert mode to avoid spamming the echo area.
  if not force and vim.api.nvim_get_mode().mode == "i" then return end

  -- Debug: log invocations and stacktrace so we can find who triggers autodoc.
  local ok_swank, swank_mod = pcall(require, "swank")
  if ok_swank and swank_mod.config and swank_mod.config.debug then
    pcall(function()
      local fp = io.open("/tmp/swank_autodoc_traces.log", "a")
      if not fp then return end
      local ts = os.date("%Y-%m-%dT%H:%M:%S")
      local mode = vim.api.nvim_get_mode().mode
      local buf = vim.api.nvim_get_current_buf()
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      fp:write(string.format("%s mode=%s buf=%d cursor=%d:%d\n", ts, mode, buf, row, col))
      fp:write((debug.traceback(nil, 2) or "") .. "\n\n")
      fp:close()
    end)
  end

  if not M.is_connected() then return end
  local sym = M._innermost_operator()
  if not sym or sym == "" then return end

  -- Strip common reader prefixes and whitespace; ensure it's symbol-like
  local s = tostring(sym):gsub("^#'", ""):gsub("^['`%,]+", ""):match("^%s*(.-)%s*$")
  if not M._is_symbol_like(s) then return end

  -- Use silent_rex to avoid :write-string side effects while fetching arglists.
  M.silent_rex(
    { "swank:operator-arglist", s, current_package },
    function(result)
      if type(result) == "table" and result[1] == ":ok" and result[2] then
        vim.api.nvim_echo({ { s .. ": " .. tostring(result[2]), "Comment" } }, false, {})
      end
    end
  )
end

-- ---------------------------------------------------------------------------
-- Thread management
-- ---------------------------------------------------------------------------

--- List all threads in a vim.ui.select picker; choose one to kill.
function M.list_threads()
  M.rex({ "swank:list-threads" }, function(result)
    if type(result) ~= "table" or result[1] ~= ":ok" then
      vim.notify("swank.nvim: list-threads failed", vim.log.levels.WARN)
      return
    end
    local data = result[2]  -- { labels_row, thread_row, thread_row, ... }
    if type(data) ~= "table" or #data < 2 then
      vim.notify("swank.nvim: no threads to show", vim.log.levels.INFO)
      return
    end
    -- Build display entries: each thread row is a table of fields
    -- Row 0 is the label header, rows 1..N are thread entries.
    local entries = {}
    for i = 2, #data do
      local row = data[i]
      if type(row) == "table" then
        -- First field is thread id/index, second is name, rest are extras
        local idx  = tostring(row[1] or i - 1)
        local name = tostring(row[2] or "?")
        table.insert(entries, { idx = idx, name = name, label = idx .. "  " .. name })
      end
    end
    if #entries == 0 then
      vim.notify("swank.nvim: no threads", vim.log.levels.INFO)
      return
    end
    vim.schedule(function()
      vim.ui.select(entries, {
        prompt = "Kill thread:",
        format_item = function(e) return e.label end,
      }, function(choice)
        if not choice then return end
        M.kill_thread(tonumber(choice.idx))
      end)
    end)
  end)
end

--- Kill the nth thread by index.
---@param n integer
function M.kill_thread(n)
  if not n then return end
  M.rex({ "swank:kill-nth-thread", n }, function(result)
    if type(result) == "table" and result[1] == ":ok" then
      vim.notify("swank.nvim: killed thread " .. tostring(n), vim.log.levels.INFO)
    else
      vim.notify("swank.nvim: kill-thread failed", vim.log.levels.WARN)
    end
  end)
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
function M.xref_bindings(sym)
  M.rex({ "swank:xref", ":bindings", sym }, function(r) require("swank.ui.xref").show(r, "bindings") end)
end

---@param sym string
function M.xref_set(sym)
  M.rex({ "swank:xref", ":sets", sym }, function(r) require("swank.ui.xref").show(r, "sets") end)
end

---@param sym string
function M.xref_macroexpands(sym)
  M.rex({ "swank:xref", ":macroexpands", sym }, function(r) require("swank.ui.xref").show(r, "macroexpands") end)
end

---@param sym string
function M.xref_specializes(sym)
  M.rex({ "swank:xref", ":specializes", sym }, function(r) require("swank.ui.xref").show(r, "specializes") end)
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
  local contribs = type(cfg.contribs) == "table" and #cfg.contribs > 0 and cfg.contribs
  if contribs then
    M.rex({
      "swank:swank-require",
      { "QUOTE", contribs },
    }, function(_)
      M.rex({ "swank:set-package", current_package }, function(_) end)
    end)
  else
    M.rex({ "swank:set-package", current_package }, function(_) end)
  end
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
  -- Reject tokens that end with ':' (package-only like 'cl-user:')
  if trimmed:match(":$") then return false end
  -- Reject bare numbers (integers and floats) — not valid symbol names
  if trimmed:match("^%-?%d+%.?%d*$") then return false end
  -- Must contain only valid CL symbol chars: letters, digits, and punctuation
  -- allow colon for package-qualified names (but not trailing colon)
  if trimmed:match("^[%a%d%+%-%*%/%@%$%%%%^%&%_%=%<%>%~%.%!%?%|:#]+$") == nil then return false end
  return true
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

-- Test-only injection hooks (do not call from production code)
function M._test_inject(fake_transport)
  transport        = fake_transport
  connection_state = "connected"
end

function M._test_reset()
  transport        = nil
  connection_state = "disconnected"
  current_package  = "COMMON-LISP-USER"
  callbacks        = {}
  msg_id           = 0
  stderr_log       = {}
  impl_job_id      = nil
  history          = {}
  history_pos      = 0
end

-- ---------------------------------------------------------------------------
-- REPL history public API
-- ---------------------------------------------------------------------------

--- Push an expression into the history ring buffer.
---@param expr string
function M.history_push(expr)
  if not expr or expr == "" then return end
  -- Deduplicate: if the same string is already the most recent entry, skip.
  if history[#history] == expr then return end
  table.insert(history, expr)
  if #history > HISTORY_MAX then
    table.remove(history, 1)
  end
  history_pos = 0
end

--- Return the previous history entry (older), or nil when exhausted.
---@return string|nil
function M.history_prev()
  if #history == 0 then return nil end
  history_pos = math.min(history_pos + 1, #history)
  return history[#history - history_pos + 1]
end

--- Return the next history entry (newer), or nil when at the front.
---@return string|nil
function M.history_next()
  if history_pos <= 1 then
    history_pos = 0
    return nil
  end
  history_pos = history_pos - 1
  return history[#history - history_pos + 1]
end

--- Return a copy of the history list (oldest first), for inspection/tests.
---@return string[]
function M.get_history()
  local copy = {}
  for i, v in ipairs(history) do copy[i] = v end
  return copy
end

return M
