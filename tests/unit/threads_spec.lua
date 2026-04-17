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

  it("list_threads() builds entries and calls vim.ui.select", function()
    local select_called = false
    local select_entries
    local orig_select   = vim.ui.select
    local orig_schedule = vim.schedule
    vim.schedule = function(fn) fn() end  -- execute synchronously
    vim.ui.select = function(entries, _opts, cb)
      select_called  = true
      select_entries = entries
      cb(nil)  -- no selection
    end

    local orig_rex = client.rex
    client.rex = function(_form, cb)
      cb({ ":ok", { "labels", { "1", "main" }, { "2", "worker" } } })
    end

    client.list_threads()

    client.rex      = orig_rex
    vim.ui.select   = orig_select
    vim.schedule    = orig_schedule

    assert.is_true(select_called)
    assert.equals(2, #select_entries)
    assert.equals("1  main",   select_entries[1].label)
    assert.equals("2  worker", select_entries[2].label)
  end)

  it("list_threads() kills selected thread when choice is made", function()
    local killed_idx
    local orig_kill     = client.kill_thread
    local orig_rex      = client.rex
    local orig_select   = vim.ui.select
    local orig_schedule = vim.schedule

    vim.schedule = function(fn) fn() end
    vim.ui.select = function(entries, _opts, cb)
      cb(entries[1])  -- select first thread
    end
    client.rex = function(_form, cb)
      cb({ ":ok", { "labels", { "3", "main" } } })
    end
    client.kill_thread = function(n) killed_idx = n end

    client.list_threads()

    client.kill_thread = orig_kill
    client.rex         = orig_rex
    vim.ui.select      = orig_select
    vim.schedule       = orig_schedule

    assert.equals(3, killed_idx)
  end)

  it("list_threads() notifies info when thread list has no table rows", function()
    local notified_level
    local orig_notify = vim.notify
    vim.notify = function(_m, l) notified_level = l end
    local orig_rex = client.rex
    -- data[2] is a non-table value → entries stays empty → INFO notify
    client.rex = function(_form, cb)
      cb({ ":ok", { "labels", "not-a-table-row" } })
    end
    client.list_threads()
    assert.equals(vim.log.levels.INFO, notified_level)
    client.rex = orig_rex
    vim.notify = orig_notify
  end)
end)
