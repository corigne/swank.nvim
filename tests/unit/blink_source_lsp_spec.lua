-- tests/unit/blink_source_lsp_spec.lua
-- Tests that completion sources disable themselves when an LSP is attached.

local client = require("swank.client")

-- Helpers to stub vim.lsp.get_clients and client.is_connected
local function with_lsp(clients, fn)
  local orig = vim.lsp.get_clients
  vim.lsp.get_clients = function(_opts) return clients end
  local ok, err = pcall(fn)
  vim.lsp.get_clients = orig
  if not ok then error(err, 2) end
end

local function inject_connected()
  local mock_transport = {
    send       = function() end,
    disconnect = function(self) self._closed = true end,
    _closed    = false,
  }
  client._test_inject(mock_transport)
end

-- ── blink_source ────────────────────────────────────────────────────────────

describe("blink_source:enabled()", function()
  local source

  before_each(function()
    client._test_reset()
    source = require("swank.blink_source")
    -- Stub nvim_get_current_buf to return a stable buffer id
    vim.api.nvim_get_current_buf = function() return 1 end
  end)

  after_each(function()
    client._test_reset()
  end)

  it("returns false when client is not connected", function()
    with_lsp({}, function()
      assert.is_false(source:enabled())
    end)
  end)

  it("returns true when connected and no LSP attached", function()
    inject_connected()
    with_lsp({}, function()
      assert.is_true(source:enabled())
    end)
  end)

  it("returns false when connected but an LSP is attached", function()
    inject_connected()
    with_lsp({ { id = 1, name = "sextant" } }, function()
      assert.is_false(source:enabled())
    end)
  end)

  it("returns false when connected but multiple LSP clients are attached", function()
    inject_connected()
    with_lsp({ { id = 1 }, { id = 2 } }, function()
      assert.is_false(source:enabled())
    end)
  end)
end)

-- ── sources/blink (fuzzy) ───────────────────────────────────────────────────

describe("sources/blink:enabled()", function()
  local source

  before_each(function()
    client._test_reset()
    -- Force re-require since it's a different module
    package.loaded["swank.sources.blink"] = nil
    source = require("swank.sources.blink")
    vim.api.nvim_get_current_buf = function() return 1 end
  end)

  after_each(function()
    client._test_reset()
    package.loaded["swank.sources.blink"] = nil
  end)

  it("returns false when client is not connected", function()
    with_lsp({}, function()
      assert.is_false(source:enabled())
    end)
  end)

  it("returns true when connected and no LSP attached", function()
    inject_connected()
    with_lsp({}, function()
      assert.is_true(source:enabled())
    end)
  end)

  it("returns false when connected but an LSP is attached", function()
    inject_connected()
    with_lsp({ { id = 1, name = "sextant" } }, function()
      assert.is_false(source:enabled())
    end)
  end)
end)

-- ── sources/nvim_cmp ────────────────────────────────────────────────────────

describe("sources/nvim_cmp Source:is_available()", function()
  -- nvim-cmp may not be present in the headless test environment.
  -- The module guards itself with `if not has_cmp then return end`, so we
  -- stub cmp before loading to exercise the full path.
  local Source

  before_each(function()
    client._test_reset()
    package.loaded["swank.sources.nvim_cmp"] = nil
    package.loaded["cmp"] = { -- minimal stub so the guard passes and register_source works
      register_source = function() end,
      lsp = { CompletionItemKind = {}, MarkupKind = {} },
    }
    local SourceClass = require("swank.sources.nvim_cmp")
    Source = SourceClass.new()
    vim.api.nvim_get_current_buf = function() return 1 end
  end)

  after_each(function()
    client._test_reset()
    package.loaded["swank.sources.nvim_cmp"] = nil
    package.loaded["cmp"] = nil
  end)

  it("returns false when client is not connected", function()
    with_lsp({}, function()
      assert.is_false(Source:is_available())
    end)
  end)

  it("returns true when connected and no LSP attached", function()
    inject_connected()
    with_lsp({}, function()
      assert.is_true(Source:is_available())
    end)
  end)

  it("returns false when connected but an LSP is attached", function()
    inject_connected()
    with_lsp({ { id = 1, name = "sextant" } }, function()
      assert.is_false(Source:is_available())
    end)
  end)
end)
