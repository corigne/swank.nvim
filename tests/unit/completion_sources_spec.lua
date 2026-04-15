-- tests/unit/completion_sources_spec.lua
-- Tests for get_completions, resolve, and edge cases in all three completion sources.
-- Stubs client.rex so no live Swank server is needed.

local client = require("swank.client")

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function inject_connected()
  local mock_transport = {
    send       = function() end,
    disconnect = function(self) self._closed = true end,
    _closed    = false,
  }
  client._test_inject(mock_transport)
end

local function with_lsp(clients, fn)
  local orig = vim.lsp.get_clients
  vim.lsp.get_clients = function(_opts) return clients end
  local ok, err = pcall(fn)
  vim.lsp.get_clients = orig
  if not ok then error(err, 2) end
end

-- ── blink_source ─────────────────────────────────────────────────────────────

describe("blink_source get_completions", function()
  local source
  local orig_rex, orig_silent_rex

  before_each(function()
    client._test_reset()
    inject_connected()
    source = require("swank.blink_source")
    orig_rex = client.rex
    orig_silent_rex = client.silent_rex
    vim.api.nvim_get_current_buf = function() return 1 end
    vim.lsp.get_clients = function() return {} end
  end)

  after_each(function()
    client.rex = orig_rex
    client.silent_rex = orig_silent_rex
    vim.lsp.get_clients = function() return {} end
    client._test_reset()
  end)

  it("calls callback with empty items when prefix is empty", function()
    local result
    local ctx = { line = "   ", cursor = { 1, 3 } }
    source:get_completions(ctx, function(r) result = r end)
    assert.same({}, result.items)
    assert.is_false(result.isIncomplete)
  end)

  it("calls client.rex with swank:completions for a non-empty prefix", function()
    local form_sent
    client.rex = function(form, _cb) form_sent = form end
    local ctx = { line = "mapcar", cursor = { 1, 6 } }
    source:get_completions(ctx, function() end)
    assert.equals("swank:completions", form_sent[1])
    assert.equals("mapcar", form_sent[2])
  end)

  it("maps completion strings to CompletionItems", function()
    client.rex = function(_form, cb)
      cb({ ":ok", { { "mapcar", "mapc", "mapcan" }, "map" } })
    end
    local result
    local ctx = { line = "map", cursor = { 1, 3 } }
    source:get_completions(ctx, function(r) result = r end)
    assert.equals(3, #result.items)
    assert.equals("mapcar", result.items[1].label)
    assert.equals("mapc",   result.items[2].label)
  end)

  it("returns empty items for non-:ok result", function()
    client.rex = function(_form, cb) cb({ ":error", "fail" }) end
    local result
    local ctx = { line = "map", cursor = { 1, 3 } }
    source:get_completions(ctx, function(r) result = r end)
    assert.same({}, result.items)
  end)

  it("returns empty items when not connected", function()
    client._test_reset()  -- disconnect
    local result
    local ctx = { line = "map", cursor = { 1, 3 } }
    source:get_completions(ctx, function(r) result = r end)
    assert.same({}, result.items)
  end)

  it("returns empty when ctx fields are nil", function()
    local result
    source:get_completions({}, function(r) result = r end)
    assert.same({}, result.items)
  end)
end)

describe("blink_source resolve", function()
  local source
  local orig_silent_rex

  before_each(function()
    client._test_reset()
    inject_connected()
    source = require("swank.blink_source")
    orig_silent_rex = client.silent_rex
    vim.lsp.get_clients = function() return {} end
  end)

  after_each(function()
    client.silent_rex = orig_silent_rex
    vim.lsp.get_clients = function() return {} end
    client._test_reset()
  end)

  it("adds documentation when describe-symbol returns :ok", function()
    client.silent_rex = function(_form, cb)
      cb({ ":ok", "MAPCAR is a function." })
    end
    local item = { label = "mapcar" }
    local resolved
    source:resolve(item, function(r) resolved = r end)
    assert.truthy(resolved.documentation)
    assert.truthy(resolved.documentation.value:find("MAPCAR is a function"))
  end)

  it("passes item unchanged for non-symbol-like label", function()
    -- A string with spaces is not a valid CL symbol
    local item = { label = "not a symbol" }
    local resolved
    source:resolve(item, function(r) resolved = r end)
    assert.equals(item, resolved)
    assert.is_nil(resolved.documentation)
  end)

  it("passes item unchanged when not connected", function()
    client._test_reset()
    local item = { label = "mapcar" }
    local resolved
    source:resolve(item, function(r) resolved = r end)
    assert.equals(item, resolved)
  end)

  it("passes item unchanged for empty label", function()
    local item = { label = "" }
    local resolved
    source:resolve(item, function(r) resolved = r end)
    assert.equals(item, resolved)
  end)

  it("passes item unchanged when describe returns non-:ok", function()
    client.silent_rex = function(_form, cb) cb({ ":error", "nope" }) end
    local item = { label = "mapcar" }
    local resolved
    source:resolve(item, function(r) resolved = r end)
    assert.is_nil(resolved.documentation)
  end)
end)

-- ── sources/blink (fuzzy) ───────────────────────────────────────────────────

describe("sources/blink get_completions", function()
  local source
  local orig_rex

  before_each(function()
    client._test_reset()
    inject_connected()
    package.loaded["swank.sources.blink"] = nil
    package.loaded["blink.cmp.types"] = { CompletionItemKind = { Function = 3 } }
    source = require("swank.sources.blink")
    orig_rex = client.rex
    vim.api.nvim_get_current_buf = function() return 1 end
    vim.lsp.get_clients = function() return {} end
  end)

  after_each(function()
    client.rex = orig_rex
    vim.lsp.get_clients = function() return {} end
    client._test_reset()
    package.loaded["swank.sources.blink"] = nil
    package.loaded["blink.cmp.types"] = nil
  end)

  it("calls client.rex with swank:fuzzy-completions", function()
    local form_sent
    client.rex = function(form, _cb) form_sent = form end
    local ctx = { line = "map", cursor = { 1, 3 } }
    source:get_completions(ctx, function() end)
    assert.equals("swank:fuzzy-completions", form_sent[1])
  end)

  it("maps fuzzy completion entries to CompletionItems", function()
    client.rex = function(_form, cb)
      -- fuzzy-completions returns (completion score flags docstring)
      cb({ ":ok", { { { "mapcar", 1.0, nil, nil }, { "mapc", 0.9, nil, nil } }, "map" } })
    end
    local result
    local ctx = { line = "map", cursor = { 1, 3 } }
    source:get_completions(ctx, function(r) result = r end)
    assert.equals(2, #result.items)
    assert.equals("mapcar", result.items[1].label)
  end)

  it("returns empty items for non-:ok result", function()
    client.rex = function(_form, cb) cb({ ":error", "fail" }) end
    local result
    local ctx = { line = "map", cursor = { 1, 3 } }
    source:get_completions(ctx, function(r) result = r end)
    assert.same({}, result.items)
  end)

  it("returns empty when not connected", function()
    client._test_reset()
    local result
    local ctx = { line = "map", cursor = { 1, 3 } }
    source:get_completions(ctx, function(r) result = r end)
    assert.same({}, result.items)
  end)
end)

describe("sources/blink resolve", function()
  local source
  local orig_silent_rex

  before_each(function()
    client._test_reset()
    inject_connected()
    package.loaded["swank.sources.blink"] = nil
    package.loaded["blink.cmp.types"] = { CompletionItemKind = { Function = 3 } }
    source = require("swank.sources.blink")
    orig_silent_rex = client.silent_rex
    vim.lsp.get_clients = function() return {} end
  end)

  after_each(function()
    client.silent_rex = orig_silent_rex
    vim.lsp.get_clients = function() return {} end
    client._test_reset()
    package.loaded["swank.sources.blink"] = nil
    package.loaded["blink.cmp.types"] = nil
  end)

  it("adds documentation when describe-symbol returns :ok", function()
    client.silent_rex = function(_form, cb)
      cb({ ":ok", "MAPCAR is a function." })
    end
    local item = { label = "mapcar" }
    local resolved
    source:resolve(item, function(r) resolved = r end)
    assert.truthy(resolved.documentation)
    assert.truthy(resolved.documentation.value:find("MAPCAR is a function"))
  end)

  it("passes item unchanged when not connected", function()
    client._test_reset()
    local item = { label = "mapcar" }
    local resolved
    source:resolve(item, function(r) resolved = r end)
    assert.equals(item, resolved)
  end)

  it("passes item unchanged for empty label", function()
    local item = { label = "" }
    local resolved
    source:resolve(item, function(r) resolved = r end)
    assert.equals(item, resolved)
  end)
end)

-- ── sources/nvim_cmp ────────────────────────────────────────────────────────

describe("sources/nvim_cmp complete and resolve", function()
  local Source

  before_each(function()
    client._test_reset()
    inject_connected()
    package.loaded["swank.sources.nvim_cmp"] = nil
    package.loaded["cmp"] = {
      register_source = function() end,
      lsp = { CompletionItemKind = { Function = 3 }, MarkupKind = { Markdown = "markdown" } },
    }
    local SourceClass = require("swank.sources.nvim_cmp")
    Source = SourceClass.new()
    vim.api.nvim_get_current_buf = function() return 1 end
    vim.lsp.get_clients = function() return {} end
  end)

  after_each(function()
    client._test_reset()
    package.loaded["swank.sources.nvim_cmp"] = nil
    package.loaded["cmp"] = nil
    vim.lsp.get_clients = function() return {} end
  end)

  it("complete: calls client.rex with swank:completions for a non-empty prefix", function()
    local form_sent
    client.rex = function(form, _cb) form_sent = form end
    local params = { context = { cursor_before_line = "mapcar" } }
    Source:complete(params, function() end)
    assert.equals("swank:completions", form_sent[1])
    assert.equals("mapcar", form_sent[2])
  end)

  it("complete: returns empty items for empty prefix", function()
    local result
    local params = { context = { cursor_before_line = "   " } }
    Source:complete(params, function(r) result = r end)
    assert.same({}, result.items)
  end)

  it("complete: maps results to CompletionItems", function()
    client.rex = function(_form, cb)
      cb({ ":ok", { { "mapcar", "mapc" }, "map" } })
    end
    local result
    local params = { context = { cursor_before_line = "map" } }
    Source:complete(params, function(r) result = r end)
    assert.equals(2, #result.items)
    assert.equals("mapcar", result.items[1].label)
  end)

  it("complete: returns empty items when not connected", function()
    client._test_reset()
    local result
    local params = { context = { cursor_before_line = "map" } }
    Source:complete(params, function(r) result = r end)
    assert.same({}, result.items)
  end)

  it("resolve: adds documentation when describe-symbol returns :ok", function()
    client.silent_rex = function(_form, cb)
      cb({ ":ok", "MAPCAR is a function." })
    end
    local item = { label = "mapcar" }
    local resolved
    Source:resolve(item, function(r) resolved = r end)
    assert.truthy(resolved.documentation)
    assert.truthy(resolved.documentation.value:find("MAPCAR is a function"))
  end)

  it("resolve: passes item unchanged when not connected", function()
    client._test_reset()
    local item = { label = "mapcar" }
    local resolved
    Source:resolve(item, function(r) resolved = r end)
    assert.equals(item, resolved)
  end)

  it("resolve: passes item unchanged for empty label", function()
    local item = { label = "" }
    local resolved
    Source:resolve(item, function(r) resolved = r end)
    assert.equals(item, resolved)
  end)
end)
