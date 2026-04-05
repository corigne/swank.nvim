local M = {}

local default_config = {
  -- Key prefix for all swank.nvim keymaps
  leader = "<Leader>",
  -- Swank server connection defaults
  server = {
    host = "127.0.0.1",
    port = 4005,
  },
  -- Automatically start a CL implementation + Swank server on first attach
  autostart = {
    enabled = true,
    implementation = "sbcl",
  },
  -- UI settings
  ui = {
    repl = {
      -- "auto" picks the best layout based on terminal size:
      -- right split if REPL gets >=80 cols, bottom if >=12 rows, else float
      position = "auto",
      -- fraction of editor width/height (0 < size <= 1) or fixed columns/rows
      size = 0.45,
    },
    floating = {
      border = "rounded",
    },
  },
  -- Swank contribs to load on connect (keyword symbol format)
  contribs = {
    ":swank-asdf",
    ":swank-repl",
    ":swank-fuzzy",
    ":swank-arglists",
    ":swank-fancy-inspector",
    ":swank-trace-dialog",
    ":swank-c-p-c",
    ":swank-package-fu",
  },
  -- Debug logging: when true, write debug logs to /tmp/*
  debug = false,
}

M.config = {}

--- Register JSON schema with neoconf.nvim if it is available.
--- Enables schema-based completions and validation in .neoconf.json and similar files.
local function register_neoconf_schema()
  local ok, neoconf = pcall(require, "neoconf.plugins")
  if not ok then return end
  local schema_files = vim.api.nvim_get_runtime_file("schemas/swank.nvim.json", false)
  local schema_file = schema_files[1]
  if not schema_file or schema_file == "" then return end
  neoconf.register({
    name = "swank.nvim",
    schema = vim.fn.fnamemodify(schema_file, ":p"),
    key = "swank",
  })
end

--- Setup swank.nvim with user config
---@param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", default_config, opts or {})
  register_neoconf_schema()
end

--- Called on FileType lisp/cl — attach keymaps and optionally connect
---@param bufnr integer
function M.attach(bufnr)
  if not next(M.config) then
    M.config = default_config
  end
  require("swank.keymaps").attach(bufnr, M.config)

  local client = require("swank.client")
  if M.config.autostart.enabled and not client.is_connected() then
    client.start_and_connect()
  end
end

return M
