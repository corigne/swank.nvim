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

  -- ── _render_entry ─────────────────────────────────────────────────────────

  describe("_render_entry", function()
    local render = trace._render_entry

    it("returns exactly 4 lines", function()
      local lines = render({ id = 1, spec = "MY-FUNC", args = "(42)", retvals = "(T)", depth = 0 })
      assert.equals(4, #lines)
    end)

    it("includes function id and spec in the header line", function()
      local lines = render({ id = 7, spec = "FOO:BAR", args = "()", retvals = "(NIL)", depth = 0 })
      assert.is_true(lines[1]:find("[7]", 1, true) ~= nil)
      assert.is_true(lines[1]:find("FOO:BAR", 1, true) ~= nil)
    end)

    it("includes args in the second line", function()
      local lines = render({ id = 1, spec = "F", args = "(1 2 3)", retvals = "(NIL)", depth = 0 })
      assert.is_true(lines[2]:find("args", 1, true) ~= nil)
      assert.is_true(lines[2]:find("(1 2 3)", 1, true) ~= nil)
    end)

    it("includes retvals in the third line", function()
      local lines = render({ id = 1, spec = "F", args = "()", retvals = "(42 T)", depth = 0 })
      assert.is_true(lines[3]:find("returns", 1, true) ~= nil)
      assert.is_true(lines[3]:find("(42 T)", 1, true) ~= nil)
    end)

    it("indents header and body lines by depth * 2 spaces", function()
      local d0 = render({ id = 1, spec = "F", args = "()", retvals = "()", depth = 0 })
      local d2 = render({ id = 2, spec = "G", args = "()", retvals = "()", depth = 2 })
      -- depth 0 → no indent
      assert.is_false(d0[1]:sub(1, 1) == " ")
      -- depth 2 → 4-space indent
      assert.equals("    ", d2[1]:sub(1, 4))
    end)

    it("emits a blank fourth line as a separator", function()
      local lines = render({ id = 1, spec = "F", args = "()", retvals = "()", depth = 0 })
      assert.equals("", lines[4])
    end)
  end)

  -- ── _build_lines ──────────────────────────────────────────────────────────

  describe("_build_lines", function()
    local build = trace._build_lines

    it("shows '(none)' when no specs are traced", function()
      local lines = build()
      local header = lines[1]
      assert.is_true(header:find("(none)", 1, true) ~= nil)
    end)

    it("lists traced specs in the header line", function()
      trace.set_specs({ "MY-FUNC", "OTHER:FOO" })
      -- vim.schedule defers redraw; call _build_lines directly to read state
      local lines = build()
      assert.is_true(lines[1]:find("MY-FUNC", 1, true) ~= nil)
      assert.is_true(lines[1]:find("OTHER:FOO", 1, true) ~= nil)
    end)

    it("shows placeholder when there are no entries", function()
      local lines = build()
      local found = false
      for _, l in ipairs(lines) do
        if l:find("no trace entries", 1, true) then found = true; break end
      end
      assert.is_true(found)
    end)

    it("renders pushed entries in the output", function()
      trace.push_entries({ { 1, "MY-FUNC", { 42 }, { "T" }, 0 } })
      local lines = build()
      local found_func = false
      for _, l in ipairs(lines) do
        if l:find("MY-FUNC", 1, true) then found_func = true; break end
      end
      assert.is_true(found_func, "expected to find MY-FUNC in build_lines output")
    end)

    it("includes separator lines and footer hint", function()
      local lines = build()
      local last = lines[#lines]
      assert.is_true(last:find("trace", 1, true) ~= nil, "footer hint should mention 'trace'")
    end)
  end)

end)
