-- tests/unit/profiling_spec.lua — profiling operations

local client = require("swank.client")
local protocol = require("swank.protocol")

local function make_mock_transport()
  local sent = {}
  local t = {
    send       = function(self, p) table.insert(sent, p) end,
    disconnect = function(self) end,
  }
  return t, sent
end

local function decode_last(sent)
  local raw = sent[#sent]
  return protocol.parse(raw)
end

describe("profiling operations", function()
  local mock, sent

  before_each(function()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)

  after_each(function()
    client._test_reset()
  end)

  -- ── profile() ─────────────────────────────────────────────────────────────

  it("profile() sends swank:profile-fdefinition with the symbol", function()
    client.profile("MY-FUNC")
    local msg = decode_last(sent)
    assert.equals("swank:profile-fdefinition", msg[2][1])
    assert.equals("MY-FUNC", msg[2][2])
  end)

  it("profile() falls back to cword when no sym given", function()
    local orig = vim.fn.expand
    vim.fn.expand = function(_) return "CWORD" end
    client.profile()
    local msg = decode_last(sent)
    assert.equals("CWORD", msg[2][2])
    vim.fn.expand = orig
  end)

  it("profile() notifies on :ok", function()
    local notified_msg
    local orig_notify = vim.notify
    vim.notify = function(m, _l) notified_msg = m end
    local orig_rex = client.rex
    client.rex = function(_form, cb) cb({ ":ok", nil }) end
    client.profile("X")
    assert.is_true(notified_msg ~= nil and notified_msg:find("X") ~= nil)
    client.rex = orig_rex
    vim.notify = orig_notify
  end)

  it("profile() notifies warn on non-:ok", function()
    local notified_level
    local orig_notify = vim.notify
    vim.notify = function(_m, l) notified_level = l end
    local orig_rex = client.rex
    client.rex = function(_form, cb) cb({ ":error", "nope" }) end
    client.profile("X")
    assert.equals(vim.log.levels.WARN, notified_level)
    client.rex = orig_rex
    vim.notify = orig_notify
  end)

  -- ── unprofile_all() ───────────────────────────────────────────────────────

  it("unprofile_all() sends swank:unprofile-all", function()
    client.unprofile_all()
    local msg = decode_last(sent)
    assert.equals("swank:unprofile-all", msg[2][1])
  end)

  it("unprofile_all() notifies on :ok", function()
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function() notified = true end
    local orig_rex = client.rex
    client.rex = function(_form, cb) cb({ ":ok", nil }) end
    client.unprofile_all()
    assert.is_true(notified)
    client.rex = orig_rex
    vim.notify = orig_notify
  end)

  -- ── profile_report() ──────────────────────────────────────────────────────

  it("profile_report() sends swank:profile-report", function()
    client.profile_report()
    local msg = decode_last(sent)
    assert.equals("swank:profile-report", msg[2][1])
  end)

  it("profile_report() notifies warn on non-:ok", function()
    local notified_level
    local orig_notify = vim.notify
    vim.notify = function(_m, l) notified_level = l end
    local orig_rex = client.rex
    client.rex = function(_form, cb) cb({ ":error", "no" }) end
    client.profile_report()
    assert.equals(vim.log.levels.WARN, notified_level)
    client.rex = orig_rex
    vim.notify = orig_notify
  end)

  -- ── profile_reset() ───────────────────────────────────────────────────────

  it("profile_reset() sends swank:profile-reset", function()
    client.profile_reset()
    local msg = decode_last(sent)
    assert.equals("swank:profile-reset", msg[2][1])
  end)

  it("profile_reset() notifies on :ok", function()
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function() notified = true end
    local orig_rex = client.rex
    client.rex = function(_form, cb) cb({ ":ok", nil }) end
    client.profile_reset()
    assert.is_true(notified)
    client.rex = orig_rex
    vim.notify = orig_notify
  end)
end)
