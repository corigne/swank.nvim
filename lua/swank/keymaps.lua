-- swank.nvim — keymap registration
-- Keymaps are buffer-local and registered on FileType attach.
-- which-key groups are registered if which-key is available.

local M = {}

---@param bufnr integer
---@param config table
function M.attach(bufnr, config)
  local leader = config.leader
  local opts = { buffer = bufnr, silent = true }

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", leader .. lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
  end

  -- Connection
  map("cc", function() require("swank.client").connect() end, "Connect to Swank server")
  map("rr", function() require("swank.client").start_and_connect() end, "Start server and connect")
  map("cd", function() require("swank.client").disconnect() end, "Disconnect")

  -- Eval
  map("ee", function() require("swank.client").eval_toplevel() end, "Eval top-level form")
  map("er", function() require("swank.client").eval_region() end, "Eval region")
  map("ei", function() require("swank.client").eval_interactive() end, "Eval (interactive input)")

  -- REPL
  map("rw", function() require("swank.ui.repl").toggle() end, "Toggle REPL window")

  -- Introspection
  map("id", function() require("swank.client").describe_symbol() end, "Describe symbol at point")
  map("ia", function() require("swank.client").apropos() end, "Apropos")
  map("ii", function() require("swank.client").inspect_value() end, "Inspect value")

  -- XRef
  map("xc", function() require("swank.client").xref_calls() end, "Who calls")
  map("xr", function() require("swank.client").xref_references() end, "Who references")
  map("xd", function() require("swank.client").find_definition() end, "Find definition")

  -- Compilation
  map("fl", function() require("swank.client").load_file() end, "Load file")
  map("fc", function() require("swank.client").compile_file() end, "Compile file")
  map("fs", function() require("swank.client").compile_form() end, "Compile form at point")

  -- Register which-key groups if available
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add({
      { leader, buffer = bufnr, group = "swank" },
      { leader .. "e", buffer = bufnr, group = "eval" },
      { leader .. "r", buffer = bufnr, group = "repl/server" },
      { leader .. "i", buffer = bufnr, group = "inspect" },
      { leader .. "x", buffer = bufnr, group = "xref" },
      { leader .. "f", buffer = bufnr, group = "file/compile" },
    })
  end
end

return M
