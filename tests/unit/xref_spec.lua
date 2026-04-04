-- tests/unit/xref_spec.lua — cross-reference location parsing + quickfix building

local xref = require("swank.ui.xref")

local function make_loc(file, line)
  return { ":location", { ":file", file }, { ":line", line, 0 }, nil }
end

describe("xref", function()
  -- ── _extract_location ───────────────────────────────────────────────────
  describe("_extract_location", function()
    it("extracts file and line from a valid :location", function()
      local file, line = xref._extract_location(make_loc("/a/b.lisp", 5))
      assert.equals("/a/b.lisp", file)
      assert.equals(5, line)
    end)

    it("returns nil, nil for :error tag", function()
      local f, l = xref._extract_location({ ":error", "no source" })
      assert.is_nil(f)
      assert.is_nil(l)
    end)

    it("returns nil, nil for non-table", function()
      local f, l = xref._extract_location(nil)
      assert.is_nil(f)
      assert.is_nil(l)
      f, l = xref._extract_location("string")
      assert.is_nil(f)
      assert.is_nil(l)
    end)

    it("is case-insensitive on part tags", function()
      local loc = { ":LOCATION", { ":FILE", "/upper.lisp" }, { ":LINE", 3, 0 }, nil }
      local file, line = xref._extract_location(loc)
      assert.equals("/upper.lisp", file)
      assert.equals(3, line)
    end)
  end)

  -- ── _refs_to_qflist ─────────────────────────────────────────────────────
  describe("_refs_to_qflist", function()
    it("converts a list of (name loc) pairs to quickfix entries", function()
      local refs = {
        { "MY-FUNC",    make_loc("/src/a.lisp", 10) },
        { "OTHER-FUNC", make_loc("/src/b.lisp", 42) },
      }
      local qf = xref._refs_to_qflist(refs, "definition")
      assert.equals(2, #qf)
      assert.equals("/src/a.lisp",        qf[1].filename)
      assert.equals(10,                   qf[1].lnum)
      assert.equals("definition: MY-FUNC", qf[1].text)
      assert.equals("/src/b.lisp",        qf[2].filename)
      assert.equals(42,                   qf[2].lnum)
      assert.equals("definition: OTHER-FUNC", qf[2].text)
    end)

    it("skips entries with invalid locations", function()
      local refs = {
        { "GOOD", make_loc("/ok.lisp", 1) },
        { "BAD",  { ":error", "no source" } },
      }
      local qf = xref._refs_to_qflist(refs, "calls")
      assert.equals(1, #qf)
      assert.equals("calls: GOOD", qf[1].text)
    end)

    it("returns empty list for empty refs", function()
      assert.same({}, xref._refs_to_qflist({}, "calls"))
    end)

    it("skips non-table entries without erroring", function()
      local refs = { "not-a-table", 42, true }
      assert.has_no_error(function()
        local qf = xref._refs_to_qflist(refs, "definition")
        assert.equals(0, #qf)
      end)
    end)

    it("uses lnum=1 when :line is absent", function()
      local loc = { ":location", { ":file", "/no-line.lisp" }, nil }
      local refs = { { "FOO", loc } }
      local qf = xref._refs_to_qflist(refs, "references")
      assert.equals(1, #qf)
      assert.equals(1, qf[1].lnum)
    end)

    it("prefixes text with the kind argument", function()
      local refs = { { "BAR", make_loc("/x.lisp", 7) } }
      assert.equals("calls: BAR",      xref._refs_to_qflist(refs, "calls")[1].text)
      assert.equals("references: BAR", xref._refs_to_qflist(refs, "references")[1].text)
    end)
  end)
end)
