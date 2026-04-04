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
  map("n", "cc", function() client.connect() end,            "Connect to Swank")
  map("n", "rr", function() client.start_and_connect() end,  "Start server and connect")
  map("n", "cd", function() client.disconnect() end,         "Disconnect")
  map("n", "cp", function() client.set_package_interactive() end, "Set package")

  -- ── Eval ─────────────────────────────────────────────────────────────────
  map("n", "ee", function() client.eval_toplevel() end,      "Eval top-level form")
  map("n", "ei", function() client.eval_interactive() end,   "Eval (prompt)")
  map("v", "ee", function() client.eval_region() end,        "Eval region")

  -- ── REPL ─────────────────────────────────────────────────────────────────
  map("n", "rw", function() require("swank.ui.repl").toggle() end, "Toggle REPL window")

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

  map("n", "xd", function()
    local sym = cword()
    if sym then client.find_definition(sym) end
  end, "Find definition of symbol at cursor")

  -- ── Compilation ──────────────────────────────────────────────────────────
  map("n", "fl", function() client.load_file() end,     "Load file")
  map("n", "fc", function() client.compile_file() end,  "Compile file")
  map("n", "fs", function() client.compile_form() end,  "Compile form at cursor")

  -- ── which-key groups ─────────────────────────────────────────────────────
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add({
      { leader,        buffer = bufnr, group = "swank" },
      { leader .. "e", buffer = bufnr, group = "eval" },
      { leader .. "r", buffer = bufnr, group = "repl/server" },
      { leader .. "i", buffer = bufnr, group = "inspect" },
      { leader .. "x", buffer = bufnr, group = "xref" },
      { leader .. "f", buffer = bufnr, group = "file/compile" },
      { leader .. "c", buffer = bufnr, group = "connection" },
    })
  end
end

return M
