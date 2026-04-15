-- tests/unit/keymaps_lsp_spec.lua
-- Tests for the LSP-first routing helper in keymaps.lua.

local keymaps = require("swank.keymaps")

describe("keymaps._has_lsp", function()
  local orig_get_clients

  before_each(function()
    orig_get_clients = vim.lsp.get_clients
  end)

  after_each(function()
    vim.lsp.get_clients = orig_get_clients
  end)

  it("returns false when no LSP clients are attached", function()
    vim.lsp.get_clients = function(_opts) return {} end
    assert.is_false(keymaps._has_lsp(1))
  end)

  it("returns true when at least one LSP client is attached", function()
    vim.lsp.get_clients = function(_opts) return { { id = 1, name = "sextant" } } end
    assert.is_true(keymaps._has_lsp(1))
  end)

  it("passes bufnr through to vim.lsp.get_clients", function()
    local received_bufnr
    vim.lsp.get_clients = function(opts)
      received_bufnr = opts and opts.bufnr
      return {}
    end
    keymaps._has_lsp(42)
    assert.equals(42, received_bufnr)
  end)

  it("returns true with multiple clients attached", function()
    vim.lsp.get_clients = function(_opts)
      return { { id = 1, name = "sextant" }, { id = 2, name = "other" } }
    end
    assert.is_true(keymaps._has_lsp(5))
  end)
end)
