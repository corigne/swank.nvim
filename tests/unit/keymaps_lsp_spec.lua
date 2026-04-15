-- tests/unit/keymaps_lsp_spec.lua
-- Tests for the LSP detection helper and conditional LSP-fallback keymap registration.

local keymaps = require("swank.keymaps")

-- ── _has_lsp ────────────────────────────────────────────────────────────────

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

-- ── Conditional fallback keymap registration ────────────────────────────────

describe("keymaps.attach LSP-fallback registration", function()
  local orig_get_clients, orig_keymap_set, orig_create_autocmd
  local registered_keymaps, autocmds_created

  local function make_config()
    return { leader = "<Leader>" }
  end

  before_each(function()
    orig_get_clients   = vim.lsp.get_clients
    orig_keymap_set    = vim.keymap.set
    orig_create_autocmd = vim.api.nvim_create_autocmd

    registered_keymaps = {}
    autocmds_created   = {}

    vim.keymap.set = function(mode, lhs, _rhs, _opts)
      table.insert(registered_keymaps, { mode = mode, lhs = lhs })
    end

    vim.api.nvim_create_autocmd = function(event, opts)
      table.insert(autocmds_created, { event = event, buffer = opts.buffer })
    end
  end)

  after_each(function()
    vim.lsp.get_clients        = orig_get_clients
    vim.keymap.set             = orig_keymap_set
    vim.api.nvim_create_autocmd = orig_create_autocmd
  end)

  local function has_keymap(lhs)
    for _, km in ipairs(registered_keymaps) do
      if km.lhs == lhs then return true end
    end
    return false
  end

  it("registers gd/K/gr/<C-k> when no LSP is attached", function()
    vim.lsp.get_clients = function() return {} end
    keymaps.attach(1, make_config())
    assert.is_true(has_keymap("gd"))
    assert.is_true(has_keymap("K"))
    assert.is_true(has_keymap("gr"))
    assert.is_true(has_keymap("<C-k>"))
  end)

  it("does NOT register gd/K/gr/<C-k> when an LSP is already attached", function()
    vim.lsp.get_clients = function() return { { id = 1, name = "sextant" } } end
    keymaps.attach(1, make_config())
    assert.is_false(has_keymap("gd"))
    assert.is_false(has_keymap("K"))
    assert.is_false(has_keymap("gr"))
    assert.is_false(has_keymap("<C-k>"))
  end)

  it("always registers gR regardless of LSP presence", function()
    vim.lsp.get_clients = function() return { { id = 1, name = "sextant" } } end
    keymaps.attach(1, make_config())
    assert.is_true(has_keymap("gR"))
  end)

  it("registers a LspDetach autocmd on the buffer", function()
    vim.lsp.get_clients = function() return {} end
    keymaps.attach(1, make_config())
    local found = false
    for _, ac in ipairs(autocmds_created) do
      if ac.event == "LspDetach" and ac.buffer == 1 then
        found = true
        break
      end
    end
    assert.is_true(found)
  end)
end)
