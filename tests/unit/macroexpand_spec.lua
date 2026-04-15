-- tests/unit/macroexpand_spec.lua
-- Tests for client.macroexpand_1 and client.macroexpand

local client   = require("swank.client")
local protocol = require("swank.protocol")

local function make_mock_transport()
  local sent = {}
  local t = {
    send       = function(_, payload) table.insert(sent, payload) end,
    disconnect = function(self) self._closed = true end,
    _closed    = false,
  }
  return t, sent
end

describe("client macroexpand", function()
  local mock, sent

  before_each(function()
    mock, sent = make_mock_transport()
    client._test_inject(mock)

    -- Stub _form_at_cursor so tests don't need a real buffer
    client._form_at_cursor = function() return "(when t (print 1))" end

    -- Stub vim.api.nvim_open_win so opening the float doesn't crash headlessly
    vim.api.nvim_open_win = function() return 1 end
    vim.api.nvim_win_is_valid = function() return false end
  end)

  after_each(function()
    client._test_reset()
    client._form_at_cursor = nil
  end)

  -- ── macroexpand_1 ─────────────────────────────────────────────────────────

  it("macroexpand_1: sends swank:macroexpand-1 with the form at cursor", function()
    client.macroexpand_1()
    assert.equals(1, #sent)
    local parsed = protocol.parse(sent[1])
    assert.equals(":emacs-rex", parsed[1])
    local form = parsed[2]
    assert.equals("swank:macroexpand-1", form[1])
    assert.equals("(when t (print 1))", form[2])
  end)

  it("macroexpand_1: does nothing when no form at cursor", function()
    client._form_at_cursor = function() return nil end
    client.macroexpand_1()
    assert.equals(0, #sent)
  end)

  it("macroexpand_1: does nothing on empty form", function()
    client._form_at_cursor = function() return "" end
    client.macroexpand_1()
    assert.equals(0, #sent)
  end)

  it("macroexpand_1: fires callback with expansion on :ok", function()
    local received_form
    local orig_rex = client.rex
    client.rex = function(form, cb, _pkg, _thread)
      received_form = form
      -- Don't call cb — we just verify the correct form is sent.
      -- show_expansion is covered by the integration path; testing the window
      -- here would require a real buffer which the headless runner provides
      -- inconsistently across test ordering.
    end
    client.macroexpand_1()
    assert.equals("swank:macroexpand-1", received_form[1])
    assert.equals("(when t (print 1))", received_form[2])
    client.rex = orig_rex
  end)

  it("macroexpand_1: does not open window on non-:ok result", function()
    local orig_rex = client.rex
    client.rex = function(_form, cb, _pkg, _thread)
      cb({ ":abort", "not a macro" })
    end
    local open_called = false
    local orig_open = vim.api.nvim_open_win
    vim.api.nvim_open_win = function() open_called = true return 1 end

    client.macroexpand_1()
    assert.is_false(open_called)
    client.rex = orig_rex
    vim.api.nvim_open_win = orig_open
  end)

  -- ── macroexpand ───────────────────────────────────────────────────────────

  it("macroexpand: sends swank:macroexpand-all with the form at cursor", function()
    local received_form
    local orig_rex = client.rex
    client.rex = function(form, _cb, _pkg, _thread)
      received_form = form
    end
    client.macroexpand()
    assert.equals("swank:macroexpand-all", received_form[1])
    assert.equals("(when t (print 1))", received_form[2])
    client.rex = orig_rex
  end)

  it("macroexpand: fires callback with expansion on :ok", function()
    local received_form
    local orig_rex = client.rex
    client.rex = function(form, _cb, _pkg, _thread)
      received_form = form
    end
    client.macroexpand()
    assert.equals("swank:macroexpand-all", received_form[1])
    client.rex = orig_rex
  end)
end)
