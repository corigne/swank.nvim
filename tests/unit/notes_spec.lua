-- tests/unit/notes_spec.lua — compiler notes / diagnostics helpers

local notes = require("swank.ui.notes")

describe("notes", function()
  -- ── _plist ──────────────────────────────────────────────────────────────
  describe("_plist", function()
    it("converts flat keyword list to table", function()
      local result = notes._plist({ ":message", "undefined variable", ":severity", ":warning" })
      assert.equals("undefined variable", result[":message"])
      assert.equals(":warning", result[":severity"])
    end)

    it("lowercases keys", function()
      local result = notes._plist({ ":SEVERITY", ":error", ":MESSAGE", "oops" })
      assert.equals(":error", result[":severity"])
      assert.equals("oops", result[":message"])
    end)

    it("returns empty table for non-table input", function()
      assert.same({}, notes._plist(nil))
      assert.same({}, notes._plist("string"))
      assert.same({}, notes._plist(42))
    end)

    it("returns empty table for empty list", function()
      assert.same({}, notes._plist({}))
    end)

    it("handles nested values", function()
      local loc = { ":location", { ":file", "/a.lisp" }, { ":line", 10, 0 }, nil }
      local result = notes._plist({ ":location", loc })
      assert.same(loc, result[":location"])
    end)
  end)

  -- ── _extract_location ───────────────────────────────────────────────────
  describe("_extract_location", function()
    it("extracts file and line from a valid :location", function()
      local loc = { ":location", { ":file", "/path/to/file.lisp" }, { ":line", 10, 0 }, nil }
      local file, line = notes._extract_location(loc)
      assert.equals("/path/to/file.lisp", file)
      assert.equals(10, line)
    end)

    it("returns nil, nil for :error locations", function()
      local loc = { ":error", "no source location" }
      local file, line = notes._extract_location(loc)
      assert.is_nil(file)
      assert.is_nil(line)
    end)

    it("returns nil, nil for non-table input", function()
      local f, l = notes._extract_location(nil)
      assert.is_nil(f)
      assert.is_nil(l)
      f, l = notes._extract_location("string")
      assert.is_nil(f)
      assert.is_nil(l)
    end)

    it("returns nil, nil for unrecognised tag", function()
      local loc = { ":other", { ":file", "/foo.lisp" }, { ":line", 5, 0 } }
      local file, line = notes._extract_location(loc)
      assert.is_nil(file)
      assert.is_nil(line)
    end)

    it("is case-insensitive on part tags", function()
      local loc = { ":LOCATION", { ":FILE", "/upper.lisp" }, { ":LINE", 7, 0 }, nil }
      local file, line = notes._extract_location(loc)
      assert.equals("/upper.lisp", file)
      assert.equals(7, line)
    end)
  end)

  -- ── show ────────────────────────────────────────────────────────────────
  describe("show", function()
    it("does not error on well-formed :ok result with no notes", function()
      local result = { ":ok", { ":compilation-result", {}, true, 0.01, nil, nil } }
      assert.has_no_error(function() notes.show(result, "/file.lisp") end)
    end)

    it("does not error on :abort result", function()
      assert.has_no_error(function()
        notes.show({ ":abort", "compile failed" }, "/file.lisp")
      end)
    end)

    it("does not error when result is nil or non-table", function()
      assert.has_no_error(function() notes.show(nil, "/file.lisp") end)
      assert.has_no_error(function() notes.show("bad", "/file.lisp") end)
    end)

    it("does not error with notes that have no source location", function()
      local raw_notes = {
        { ":message", "style warning", ":severity", ":style-warning",
          ":location", { ":error", "no source location" } }
      }
      local result = { ":ok", { ":compilation-result", raw_notes, true, 0.0, nil, nil } }
      assert.has_no_error(function() notes.show(result, "/file.lisp") end)
    end)

    it("does not error with valid notes containing file locations", function()
      local loc = { ":location", { ":file", "/tmp/test.lisp" }, { ":line", 3, 0 }, nil }
      local raw_notes = {
        { ":message", "undefined: FOO", ":severity", ":warning", ":location", loc },
        { ":message", "bad form",       ":severity", ":error",   ":location", loc },
      }
      local result = { ":ok", { ":compilation-result", raw_notes, nil, 0.1, nil, nil } }
      assert.has_no_error(function() notes.show(result, "/tmp/test.lisp") end)
    end)

    it("silent=true: suppresses vim.notify on :abort", function()
      local notified = false
      local orig = vim.notify
      vim.notify = function() notified = true end
      notes.show({ ":abort", "compile failed" }, "/file.lisp", true)
      vim.notify = orig
      assert.is_false(notified)
    end)

    it("silent=false: emits vim.notify on :abort", function()
      local notified = false
      local orig = vim.notify
      vim.notify = function() notified = true end
      notes.show({ ":abort", "compile failed" }, "/file.lisp", false)
      vim.notify = orig
      assert.is_true(notified)
    end)

    it("silent=true: suppresses 'compiled OK' notify on success with no notes", function()
      local notified = false
      local orig = vim.notify
      vim.notify = function() notified = true end
      local result = { ":ok", { ":compilation-result", {}, true, 0.01, nil, nil } }
      notes.show(result, "/file.lisp", true)
      vim.notify = orig
      assert.is_false(notified)
    end)

    it("silent=false: emits 'compiled OK' notify on success with no notes", function()
      local notified = false
      local orig = vim.notify
      vim.notify = function() notified = true end
      local result = { ":ok", { ":compilation-result", {}, true, 0.01, nil, nil } }
      notes.show(result, "/file.lisp", false)
      vim.notify = orig
      assert.is_true(notified)
    end)
  end)
end)
