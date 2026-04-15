-- tests/unit/repl_history_spec.lua — REPL input history ring buffer

local client = require("swank.client")

describe("REPL history", function()
  before_each(function()
    client._test_reset()
  end)

  after_each(function()
    client._test_reset()
  end)

  -- ── history_push ──────────────────────────────────────────────────────────

  it("push stores an expression", function()
    client.history_push("(+ 1 2)")
    assert.same({ "(+ 1 2)" }, client.get_history())
  end)

  it("push ignores empty string", function()
    client.history_push("")
    assert.same({}, client.get_history())
  end)

  it("push ignores nil", function()
    client.history_push(nil)
    assert.same({}, client.get_history())
  end)

  it("push deduplicates consecutive identical entries", function()
    client.history_push("(foo)")
    client.history_push("(foo)")
    assert.equals(1, #client.get_history())
  end)

  it("push allows the same entry non-consecutively", function()
    client.history_push("(foo)")
    client.history_push("(bar)")
    client.history_push("(foo)")
    assert.equals(3, #client.get_history())
  end)

  -- ── history_prev / history_next ───────────────────────────────────────────

  it("history_prev returns nil when history is empty", function()
    assert.is_nil(client.history_prev())
  end)

  it("history_prev returns the most recent entry first", function()
    client.history_push("(a)")
    client.history_push("(b)")
    client.history_push("(c)")
    assert.equals("(c)", client.history_prev())
  end)

  it("history_prev walks backward through entries", function()
    client.history_push("(a)")
    client.history_push("(b)")
    client.history_push("(c)")
    assert.equals("(c)", client.history_prev())
    assert.equals("(b)", client.history_prev())
    assert.equals("(a)", client.history_prev())
  end)

  it("history_prev does not go past the oldest entry", function()
    client.history_push("(only)")
    client.history_prev()  -- "(only)"
    local again = client.history_prev()
    assert.equals("(only)", again)
  end)

  it("history_next returns nil when not browsing", function()
    client.history_push("(a)")
    assert.is_nil(client.history_next())
  end)

  it("history_next walks forward after history_prev", function()
    client.history_push("(a)")
    client.history_push("(b)")
    client.history_push("(c)")
    client.history_prev()  -- "(c)"
    client.history_prev()  -- "(b)"
    assert.equals("(c)", client.history_next())
  end)

  it("history_next returns nil when back at the front", function()
    client.history_push("(a)")
    client.history_push("(b)")
    client.history_prev()  -- "(b)"
    client.history_next()  -- nil (back to front)
    assert.is_nil(client.history_next())
  end)

  -- ── cap at HISTORY_MAX ────────────────────────────────────────────────────

  it("trims oldest entry when exceeding HISTORY_MAX (100)", function()
    for i = 1, 101 do
      client.history_push("entry-" .. i)
    end
    local h = client.get_history()
    assert.equals(100, #h)
    assert.equals("entry-2",   h[1])   -- oldest is entry-2 (entry-1 dropped)
    assert.equals("entry-101", h[100]) -- newest still present
  end)
end)
