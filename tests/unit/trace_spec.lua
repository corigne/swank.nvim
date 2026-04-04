-- tests/unit/trace_spec.lua
-- Unit tests for the trace dialog UI module.
-- Tests the internal parse_entry logic and push_entries/set_specs state management
-- by accessing them through the public API surface.

local trace = require("swank.ui.trace")

describe("trace dialog", function()

  -- Reset trace state between each test by pushing empty data
  before_each(function()
    trace.clear()
    trace.set_specs({})
  end)

  -- ── set_specs / spec tracking ─────────────────────────────────────────────

  describe("set_specs", function()
    it("accepts an empty list without error", function()
      assert.has_no.errors(function() trace.set_specs({}) end)
    end)

    it("accepts a list of spec name strings", function()
      assert.has_no.errors(function()
        trace.set_specs({ "MY-FUNC", "OTHER-PACKAGE:FOO" })
      end)
    end)

    it("ignores non-table input gracefully", function()
      -- Should not error even if Swank sends something unexpected
      assert.has_no.errors(function() trace.set_specs(nil) end)
      assert.has_no.errors(function() trace.set_specs("bad") end)
    end)
  end)

  -- ── push_entries ──────────────────────────────────────────────────────────

  describe("push_entries", function()
    it("accepts an empty batch without error", function()
      assert.has_no.errors(function() trace.push_entries({}) end)
    end)

    it("accepts nil without error", function()
      assert.has_no.errors(function() trace.push_entries(nil) end)
    end)

    it("accepts a well-formed batch without error", function()
      local batch = {
        { 1, "MY-FUNC", { 42, "hello" }, { "result" }, 0 },
        { 2, "INNER",   { "x" },         { true },     1 },
      }
      assert.has_no.errors(function() trace.push_entries(batch) end)
    end)

    it("handles missing fields in an entry gracefully", function()
      -- Incomplete entry: only id and spec
      local batch = { { 3, "PARTIAL" } }
      assert.has_no.errors(function() trace.push_entries(batch) end)
    end)

    it("ignores non-table entries in the batch", function()
      local batch = { "bad", 42, nil, { 4, "GOOD", {}, {}, 0 } }
      assert.has_no.errors(function() trace.push_entries(batch) end)
    end)
  end)

  -- ── clear ─────────────────────────────────────────────────────────────────

  describe("clear", function()
    it("clears entries without error", function()
      trace.push_entries({ { 1, "F", {}, {}, 0 } })
      assert.has_no.errors(function() trace.clear() end)
    end)

    it("is idempotent", function()
      assert.has_no.errors(function()
        trace.clear()
        trace.clear()
      end)
    end)
  end)

  -- ── open / close ─────────────────────────────────────────────────────────

  describe("close", function()
    it("does not error when called with no window open", function()
      assert.has_no.errors(function() trace.close() end)
    end)

    it("is idempotent", function()
      assert.has_no.errors(function()
        trace.close()
        trace.close()
      end)
    end)
  end)

end)
