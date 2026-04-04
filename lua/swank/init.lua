local M = {}

local default_config = {
  -- Key prefix for all swank.nvim keymaps
  leader = "<LocalLeader>",
  -- Swank server connection defaults
  server = {
    host = "127.0.0.1",
    port = 4005,
  },
  -- Automatically start SBCL + Swank server on attach
  autostart = {
    enabled = true,
    implementation = "sbcl",
  },
  -- UI settings
  ui = {
    repl = {
      position = "right", -- "right" | "left" | "top" | "bottom"
      size = 80,
    },
    floating = {
      border = "rounded",
    },
  },
  -- Swank contribs to load on connect
  contribs = {
    "SWANK-ASDF",
    "SWANK-REPL",
    "SWANK-FUZZY",
    "SWANK-ARGLISTS",
    "SWANK-FANCY-INSPECTOR",
    "SWANK-TRACE-DIALOG",
    "SWANK-C-P-C",
    "SWANK-PACKAGE-FU",
  },
}

M.config = {}

--- Setup swank.nvim with user config
---@param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", default_config, opts or {})
end

--- Called on FileType lisp/cl — attach keymaps and optionally connect
---@param bufnr integer
function M.attach(bufnr)
  if not next(M.config) then
    -- setup() was not called; use defaults
    M.config = default_config
  end
  require("swank.keymaps").attach(bufnr, M.config)
end

return M
