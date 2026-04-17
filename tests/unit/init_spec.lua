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

  it("calls start_and_connect when autostart enabled and not connected", function()
    local started = false
    client.start_and_connect = function() started = true end
    client.is_connected      = function() return false end
    swank.setup({ autostart = { enabled = true } })
    local bufnr = vim.api.nvim_create_buf(false, true)
    swank.attach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.is_true(started)
  end)
end)

describe("swank.setup() neoconf schema registration", function()
  local orig_setup

  before_each(function()
    orig_setup = swank.setup
  end)

  after_each(function()
    package.loaded["neoconf.plugins"] = nil
    swank.setup = orig_setup
  end)

  it("registers schema when neoconf.plugins is available", function()
    local registered = false
    local fake_neoconf = {
      register = function(opts)
        if opts.name == "swank.nvim" then registered = true end
      end,
    }
    package.loaded["neoconf.plugins"] = fake_neoconf
    -- Also stub nvim_get_runtime_file to return a fake schema path
    local orig_get_runtime = vim.api.nvim_get_runtime_file
    vim.api.nvim_get_runtime_file = function(pat, _)
      if pat:find("swank") then return { "/fake/schema/swank.nvim.json" } end
      return orig_get_runtime(pat, _)
    end
    swank.setup({})
    vim.api.nvim_get_runtime_file = orig_get_runtime
    assert.is_true(registered)
  end)
end)
