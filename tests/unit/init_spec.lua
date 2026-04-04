-- tests/unit/init_spec.lua — swank init module (setup + attach)

local swank = require("swank")
local client = require("swank.client")

describe("swank.setup()", function()
  local orig_config

  before_each(function()
    orig_config = swank.config
  end)

  after_each(function()
    swank.config = orig_config
  end)

  it("merges user options into the default config", function()
    swank.setup({ server = { port = 9999 } })
    assert.equals(9999, swank.config.server.port)
  end)

  it("accepts no arguments and uses defaults", function()
    swank.setup()
    assert.is_not_nil(swank.config.server)
    assert.is_not_nil(swank.config.contribs)
  end)
end)

describe("swank.attach()", function()
  local orig_config
  local orig_keymaps_attach
  local orig_client_is_connected
  local orig_client_start

  before_each(function()
    orig_config          = swank.config
    orig_keymaps_attach  = require("swank.keymaps").attach
    orig_client_is_connected = client.is_connected
    orig_client_start    = client.start_and_connect

    -- Prevent real keymap setup and autostart
    require("swank.keymaps").attach  = function(_, _) end
    client.is_connected              = function() return true end  -- already connected
    client.start_and_connect         = function() end
  end)

  after_each(function()
    swank.config                     = orig_config
    require("swank.keymaps").attach  = orig_keymaps_attach
    client.is_connected              = orig_client_is_connected
    client.start_and_connect         = orig_client_start
  end)

  it("populates config from defaults when M.config is empty", function()
    swank.config = {}
    local bufnr = vim.api.nvim_create_buf(false, true)
    swank.attach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    -- config should be populated with defaults
    assert.is_not_nil(swank.config.server)
  end)

  it("calls keymaps.attach with the buffer and config", function()
    swank.setup({ server = { port = 4005 } })
    local called_with_buf = nil
    require("swank.keymaps").attach = function(b, _) called_with_buf = b end
    local bufnr = vim.api.nvim_create_buf(false, true)
    swank.attach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(bufnr, called_with_buf)
  end)

  it("does not call start_and_connect when already connected", function()
    local started = false
    client.start_and_connect = function() started = true end
    client.is_connected      = function() return true end
    swank.setup({ autostart = { enabled = true } })
    local bufnr = vim.api.nvim_create_buf(false, true)
    swank.attach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.is_false(started)
  end)
end)
