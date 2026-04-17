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

-- ── _lsp_fallback_keys ──────────────────────────────────────────────────────

describe("keymaps._lsp_fallback_keys", function()
  it("exports the five LSP-mimic key strings", function()
    local keys = keymaps._lsp_fallback_keys
    assert.is_table(keys)
    local set = {}
    for _, k in ipairs(keys) do set[k] = true end
    assert.is_true(set["gd"])
    assert.is_true(set["K"])
    assert.is_true(set["gr"])
    assert.is_true(set["gR"])
    assert.is_true(set["<C-k>"])
    assert.equals(5, #keys)
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
    orig_get_clients    = vim.lsp.get_clients
    orig_keymap_set     = vim.keymap.set
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
    vim.lsp.get_clients         = orig_get_clients
    vim.keymap.set              = orig_keymap_set
    vim.api.nvim_create_autocmd = orig_create_autocmd
  end)

  local function has_keymap(lhs)
    for _, km in ipairs(registered_keymaps) do
      if km.lhs == lhs then return true end
    end
    return false
  end

  local function has_autocmd(event)
    for _, ac in ipairs(autocmds_created) do
      if ac.event == event then return true end
    end
    return false
  end

  it("registers gd/K/gr/gR/<C-k> when no LSP is attached", function()
    vim.lsp.get_clients = function() return {} end
    keymaps.attach(1, make_config())
    assert.is_true(has_keymap("gd"))
    assert.is_true(has_keymap("K"))
    assert.is_true(has_keymap("gr"))
    assert.is_true(has_keymap("gR"))
    assert.is_true(has_keymap("<C-k>"))
  end)

  it("does NOT register gd/K/gr/gR/<C-k> when an LSP is already attached", function()
    vim.lsp.get_clients = function() return { { id = 1, name = "sextant" } } end
    keymaps.attach(1, make_config())
    assert.is_false(has_keymap("gd"))
    assert.is_false(has_keymap("K"))
    assert.is_false(has_keymap("gr"))
    assert.is_false(has_keymap("gR"))
    assert.is_false(has_keymap("<C-k>"))
  end)

  it("registers a LspDetach autocmd on the buffer", function()
    vim.lsp.get_clients = function() return {} end
    keymaps.attach(1, make_config())
    assert.is_true(has_autocmd("LspDetach"))
  end)

  it("registers a LspAttach autocmd on the buffer", function()
    vim.lsp.get_clients = function() return {} end
    keymaps.attach(1, make_config())
    assert.is_true(has_autocmd("LspAttach"))
  end)

  it("LspAttach autocmd is registered on the correct buffer", function()
    vim.lsp.get_clients = function() return {} end
    keymaps.attach(99, make_config())
    local found = false
    for _, ac in ipairs(autocmds_created) do
      if ac.event == "LspAttach" and ac.buffer == 99 then
        found = true; break
      end
    end
    assert.is_true(found)
  end)
end)

-- ── LspAttach callback deletes fallbacks ────────────────────────────────────

describe("keymaps LspAttach callback", function()
  local orig_get_clients, orig_keymap_set, orig_keymap_del, orig_create_autocmd
  local deleted_keymaps, lsp_attach_cb

  local function make_config()
    return { leader = "<Leader>" }
  end

  before_each(function()
    orig_get_clients    = vim.lsp.get_clients
    orig_keymap_set     = vim.keymap.set
    orig_keymap_del     = vim.keymap.del
    orig_create_autocmd = vim.api.nvim_create_autocmd

    deleted_keymaps = {}
    lsp_attach_cb   = nil

    vim.keymap.set = function() end
    vim.keymap.del = function(_mode, lhs, _opts)
      table.insert(deleted_keymaps, lhs)
    end

    vim.api.nvim_create_autocmd = function(event, opts)
      if event == "LspAttach" then
        lsp_attach_cb = opts.callback
      end
    end
  end)

  after_each(function()
    vim.lsp.get_clients         = orig_get_clients
    vim.keymap.set              = orig_keymap_set
    vim.keymap.del              = orig_keymap_del
    vim.api.nvim_create_autocmd = orig_create_autocmd
  end)

  it("deletes all five fallback keys when LspAttach fires", function()
    vim.lsp.get_clients = function() return {} end
    keymaps.attach(1, make_config())
    assert.is_not_nil(lsp_attach_cb)
    lsp_attach_cb()
    local deleted_set = {}
    for _, k in ipairs(deleted_keymaps) do deleted_set[k] = true end
    for _, lhs in ipairs(keymaps._lsp_fallback_keys) do
      assert.is_true(deleted_set[lhs],
        "expected " .. lhs .. " to be deleted on LspAttach")
    end
  end)

  it("uses pcall so missing keymaps do not error", function()
    vim.lsp.get_clients = function() return {} end
    vim.keymap.del = function(_mode, _lhs, _opts)
      error("no such keymap")
    end
    keymaps.attach(1, make_config())
    assert.is_not_nil(lsp_attach_cb)
    -- must not raise
    assert.has_no.errors(function() lsp_attach_cb() end)
  end)
end)
