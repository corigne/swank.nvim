-- tests/unit/threads_spec.lua — thread list and kill operations

local client   = require("swank.client")
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
  return protocol.parse(sent[#sent])
end

describe("thread management", function()
  local mock, sent

  before_each(function()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)

  after_each(function()
    client._test_reset()
  end)

  -- ── kill_thread() ─────────────────────────────────────────────────────────

  it("kill_thread() sends swank:kill-nth-thread with the index", function()
    client.kill_thread(3)
    local msg = decode_last(sent)
    assert.equals("swank:kill-nth-thread", msg[2][1])
    assert.equals(3, msg[2][2])
  end)

  it("kill_thread() notifies on :ok", function()
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function() notified = true end
    local orig_rex = client.rex
    client.rex = function(_form, cb) cb({ ":ok", nil }) end
    client.kill_thread(1)
    assert.is_true(notified)
    client.rex = orig_rex
    vim.notify = orig_notify
  end)

  it("kill_thread() notifies warn on non-:ok", function()
    local notified_level
    local orig_notify = vim.notify
    vim.notify = function(_m, l) notified_level = l end
    local orig_rex = client.rex
    client.rex = function(_form, cb) cb({ ":error", "no" }) end
    client.kill_thread(1)
    assert.equals(vim.log.levels.WARN, notified_level)
    client.rex = orig_rex
    vim.notify = orig_notify
  end)

  it("kill_thread() does nothing when n is nil", function()
    local called = false
    local orig_rex = client.rex
    client.rex = function() called = true end
    client.kill_thread(nil)
    assert.is_false(called)
    client.rex = orig_rex
  end)

  -- ── list_threads() ────────────────────────────────────────────────────────

  it("list_threads() sends swank:list-threads", function()
    -- Stub rex so we can just verify the form sent
    local received_form
    local orig_rex = client.rex
    client.rex = function(form, _cb) received_form = form end
    client.list_threads()
    assert.equals("swank:list-threads", received_form[1])
    client.rex = orig_rex
  end)

  it("list_threads() notifies warn on non-:ok result", function()
    local notified_level
    local orig_notify = vim.notify
    vim.notify = function(_m, l) notified_level = l end
    local orig_rex = client.rex
    client.rex = function(_form, cb) cb({ ":error", "no" }) end
    client.list_threads()
    assert.equals(vim.log.levels.WARN, notified_level)
    client.rex = orig_rex
    vim.notify = orig_notify
  end)

  it("list_threads() notifies info when thread list is empty", function()
    local notified_level
    local orig_notify = vim.notify
    vim.notify = function(_m, l) notified_level = l end
    local orig_rex = client.rex
    client.rex = function(_form, cb) cb({ ":ok", { "labels" } }) end
    client.list_threads()
    assert.equals(vim.log.levels.INFO, notified_level)
    client.rex = orig_rex
    vim.notify = orig_notify
  end)
end)
