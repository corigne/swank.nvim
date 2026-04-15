-- swank.nvim — keymap registration
-- All editor-context input (cword, visual selection, vim.ui.input prompts)
-- is resolved here. client.lua receives only plain data.

local M = {}

---@param bufnr integer
---@param config table
function M.attach(bufnr, config)
  local client = require("swank.client")
  local leader = config.leader
  local bopts  = { buffer = bufnr, silent = true }

  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, leader .. lhs, rhs,
      vim.tbl_extend("force", bopts, { desc = desc }))
  end

  -- Grab cword and validate it looks like a CL symbol
  local function cword()
    local w = vim.fn.expand("<cword>")
    return client._is_symbol_like(w) and w or nil
  end

  -- Grab visual selection and validate it looks like a CL symbol
  local function vword()
    local lines = vim.api.nvim_buf_get_lines(0,
      vim.fn.line("'<") - 1, vim.fn.line("'>"), false)
    if #lines == 0 then return nil end
    local text = table.concat(lines, "\n"):match("^%s*(.-)%s*$")
    return client._is_symbol_like(text) and text or nil
  end

  -- ── Connection ───────────────────────────────────────────────────────────
  map("n", "lc", function() client.connect() end,            "Connect to Swank")
  map("n", "rr", function() client.start_and_connect() end,  "Start server and connect")
  map("n", "ld", function() client.disconnect() end,         "Disconnect")
  map("n", "lp", function() client.set_package_interactive() end, "Set package")

  -- ── Eval ─────────────────────────────────────────────────────────────────
  map("n", "ee", function() client.eval_toplevel() end,      "Eval top-level form")
  map("n", "ei", function() client.eval_interactive() end,   "Eval (prompt)")
  map("v", "ee", function() client.eval_region() end,        "Eval region")
  map("n", "em", function() client.macroexpand_1() end,      "Macroexpand-1 form at cursor")
  map("n", "eM", function() client.macroexpand() end,        "Macroexpand-all form at cursor")

  -- ── REPL ─────────────────────────────────────────────────────────────────
  map("n", "rw", function() require("swank.ui.repl").toggle() end, "Toggle REPL window")

  -- REPL history: re-open eval prompt pre-filled with a history entry
  map("n", "e<Up>", function()
    local expr = client.history_prev()
    if not expr then
      vim.notify("swank.nvim: no more history", vim.log.levels.INFO)
      return
    end
    vim.ui.input({ prompt = "Eval: ", default = expr }, function(input)
      if not input or input == "" then return end
      client.history_push(input)
      require("swank.ui.repl").show_input(input)
      client.rex({ "swank:eval-and-grab-output", input }, function(result)
        require("swank.ui.repl").show_result(result)
      end)
    end)
  end, "Re-eval from history (older)")

  map("n", "e<Down>", function()
    local expr = client.history_next()
    if not expr then
      vim.notify("swank.nvim: at end of history", vim.log.levels.INFO)
      return
    end
    vim.ui.input({ prompt = "Eval: ", default = expr }, function(input)
      if not input or input == "" then return end
      client.history_push(input)
      require("swank.ui.repl").show_input(input)
      client.rex({ "swank:eval-and-grab-output", input }, function(result)
        require("swank.ui.repl").show_result(result)
      end)
    end)
  end, "Re-eval from history (newer)")

  -- ── Introspection ─────────────────────────────────────────────────────────
  -- describe: cursor word (n) or selection (v)
  map("n", "id", function()
    local sym = cword()
    if sym then client.describe(sym) end
  end, "Describe symbol at cursor")

  map("v", "id", function()
    local sym = vword()
    if sym then client.describe(sym) end
  end, "Describe selected symbol")

  -- apropos: prompted (n ia), cursor word (n iA), selection (v ia)
  map("n", "ia", function()
    vim.ui.input({ prompt = "Apropos: " }, function(q)
      if q and q ~= "" then client.apropos(q) end
    end)
  end, "Apropos (prompt)")

  map("n", "iA", function()
    local sym = cword()
    if sym then client.apropos(sym) end
  end, "Apropos symbol at cursor")

  map("v", "ia", function()
    local sym = vword()
    if sym then client.apropos(sym) end
  end, "Apropos selected symbol")

  -- inspect
  map("n", "ii", function()
    local sym = cword()
    if sym then client.inspect_value(sym) end
  end, "Inspect value at cursor")

  -- ── XRef ─────────────────────────────────────────────────────────────────
  map("n", "xc", function()
    local sym = cword()
    if sym then client.xref_calls(sym) end
  end, "Who calls symbol at cursor")

  map("n", "xr", function()
    local sym = cword()
    if sym then client.xref_references(sym) end
  end, "Who references symbol at cursor")

  map("n", "xb", function()
    local sym = cword()
    if sym then client.xref_bindings(sym) end
  end, "Who binds symbol at cursor")

  map("n", "xs", function()
    local sym = cword()
    if sym then client.xref_set(sym) end
  end, "Who sets symbol at cursor")

  map("n", "xm", function()
    local sym = cword()
    if sym then client.xref_macroexpands(sym) end
  end, "Who macroexpands symbol at cursor")

  map("n", "xS", function()
    local sym = cword()
    if sym then client.xref_specializes(sym) end
  end, "Who specializes on symbol at cursor")

  map("n", "xd", function()
    local sym = cword()
    if sym then client.find_definition(sym) end
  end, "Find definition of symbol at cursor")

  -- ── Compilation ──────────────────────────────────────────────────────────
  map("n", "fl", function() client.load_file() end,     "Load file")
  map("n", "fc", function() client.compile_file() end,  "Compile file")
  map("n", "fs", function() client.compile_form() end,  "Compile form at cursor")
  map("n", "fd", function() client.disassemble() end,   "Disassemble symbol at cursor")

  -- ── Trace ─────────────────────────────────────────────────────────────────
  map("n", "tt", function()
    require("swank.ui.trace").open()
  end, "Open trace dialog")

  map("n", "td", function()
    local sym = cword()
    if sym then
      client.trace_toggle(sym)
    else
      vim.ui.input({ prompt = "Trace function: " }, function(s)
        if s and s ~= "" then client.trace_toggle(s) end
      end)
    end
  end, "Toggle trace on symbol at cursor")

  map("n", "tD", function() client.untrace_all() end,    "Untrace all")
  map("n", "tc", function() client.clear_traces() end,   "Clear trace entries")
  map("n", "tg", function() client.refresh_traces() end, "Refresh trace entries")

  -- ── Profiling ─────────────────────────────────────────────────────────────
  map("n", "pp", function() client.profile() end,         "Profile symbol at cursor")
  map("n", "pP", function() client.unprofile_all() end,   "Unprofile all functions")
  map("n", "pr", function() client.profile_report() end,  "Show profiling report")
  map("n", "p0", function() client.profile_reset() end,   "Reset profiling counters")

  -- ── LSP-compatible keymaps ────────────────────────────────────────────────
  -- gd / K / gr / gR / <C-k> are registered as Swank fallbacks only when no
  -- LSP is currently attached.  If an LSP attaches later its keymaps naturally
  -- overwrite these (last writer wins for buffer-local keymaps).  When the
  -- last LSP client detaches we re-register the Swank fallbacks so the
  -- familiar bindings keep working without a Language Server.

  local lsp_opts = { buffer = bufnr, silent = true }
  local function lsp(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", lsp_opts, { desc = desc }))
  end

  -- Register gd / K / gr / gR / <C-k> → Swank as the initial fallback.
  -- Only set when no LSP is already attached; if one is, we let its own
  -- keymaps take sole ownership.  The LspDetach autocmd below restores them
  -- whenever the last client leaves.
  local function register_lsp_fallbacks()
    -- gd — go to definition
    lsp("n", "gd", function()
      local sym = cword()
      if sym then client.find_definition(sym) end
    end, "Go to definition (Swank fallback)")

    -- K — hover / describe
    lsp("n", "K", function()
      local sym = cword()
      if sym then client.describe(sym) end
    end, "Describe symbol (Swank fallback)")

    -- gr — references
    lsp("n", "gr", function()
      local sym = cword()
      if sym then client.xref_references(sym) end
    end, "Find references (Swank fallback)")

    -- gR — callers (call hierarchy incoming calls)
    lsp("n", "gR", function()
      local sym = cword()
      if sym then client.xref_calls(sym) end
    end, "Find callers (Swank fallback)")

    -- <C-k> — signature help, normal mode only.
    lsp("n", "<C-k>", function()
      client.autodoc()
    end, "Signature help (Swank fallback)")
  end

  if not M._has_lsp(bufnr) then
    register_lsp_fallbacks()
  end

  -- Re-register Swank fallbacks when the last LSP client detaches from the buffer.
  vim.api.nvim_create_autocmd("LspDetach", {
    buffer = bufnr,
    callback = function()
      -- vim.schedule so get_clients reflects the post-detach state.
      vim.schedule(function()
        if not M._has_lsp(bufnr) then
          register_lsp_fallbacks()
        end
      end)
    end,
  })

  -- ── which-key groups ─────────────────────────────────────────────────────
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add({
      { leader,        buffer = bufnr, group = "swank" },
      { leader .. "e", buffer = bufnr, group = "eval/expand" },
      { leader .. "r", buffer = bufnr, group = "repl/server" },
      { leader .. "i", buffer = bufnr, group = "inspect" },
      { leader .. "x", buffer = bufnr, group = "xref" },
      { leader .. "f", buffer = bufnr, group = "file/compile" },
      { leader .. "l", buffer = bufnr, group = "connection" },
      { leader .. "t", buffer = bufnr, group = "trace" },
      { leader .. "p", buffer = bufnr, group = "profiling" },
    })
  end
end

--- Returns true when at least one LSP client is attached to the given buffer.
---@param bufnr integer
---@return boolean
function M._has_lsp(bufnr)
  return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
end

return M
