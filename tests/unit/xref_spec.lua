-- tests/unit/xref_spec.lua — cross-reference location parsing, quickfix building, dispatch

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

  -- ── _ui_select_is_hooked ────────────────────────────────────────────────
  describe("_ui_select_is_hooked", function()
    it("returns false when vim.ui.select is the Neovim builtin", function()
      -- In the headless test environment vim.ui.select is the builtin from vim/ui.lua
      assert.is_false(xref._ui_select_is_hooked())
    end)

    it("returns true when vim.ui.select has been replaced", function()
      local orig = vim.ui.select
      vim.ui.select = function() end  -- local function → source is this file
      local result = xref._ui_select_is_hooked()
      vim.ui.select = orig
      assert.is_true(result)
    end)
  end)

  -- ── M.show dispatch ─────────────────────────────────────────────────────
  describe("M.show", function()
    local orig_cmd, orig_setqflist, orig_cursor, orig_select, orig_fnameescape
    local cmd_calls, qflist_calls, copen_called, select_called

    before_each(function()
      cmd_calls    = {}
      qflist_calls = {}
      copen_called = false
      select_called = false

      orig_cmd = vim.cmd
      vim.cmd = function(s)
        if s == "copen" then copen_called = true
        else table.insert(cmd_calls, s) end
      end

      orig_setqflist = vim.fn.setqflist
      vim.fn.setqflist = function(items, action, opts)
        table.insert(qflist_calls, { items = items, action = action, opts = opts })
      end

      orig_cursor = vim.api.nvim_win_set_cursor
      vim.api.nvim_win_set_cursor = function() end

      orig_fnameescape = vim.fn.fnameescape
      vim.fn.fnameescape = function(s) return s end

      orig_select = vim.ui.select
    end)

    after_each(function()
      vim.cmd                    = orig_cmd
      vim.fn.setqflist           = orig_setqflist
      vim.api.nvim_win_set_cursor = orig_cursor
      vim.fn.fnameescape         = orig_fnameescape
      vim.ui.select              = orig_select
    end)

    local function make_ok(refs)
      return { ":ok", refs }
    end

    it("notifies and returns for non-table result", function()
      local notified = false
      local orig_notify = vim.notify
      vim.notify = function() notified = true end
      xref.show("bad", "calls")
      vim.notify = orig_notify
      assert.is_false(notified)  -- non-table hits early return silently
    end)

    it("notifies when result tag is not :ok", function()
      local level
      local orig_notify = vim.notify
      vim.notify = function(_, l) level = l end
      xref.show({ ":error", "oops" }, "calls")
      vim.notify = orig_notify
      assert.equals(vim.log.levels.WARN, level)
    end)

    it("notifies when refs list is empty", function()
      local notified = false
      local orig_notify = vim.notify
      vim.notify = function() notified = true end
      xref.show({ ":ok", {} }, "calls")
      vim.notify = orig_notify
      assert.is_true(notified)
    end)

    it("jumps directly for a single result (no picker)", function()
      local refs = { { "FOO", make_loc("/a.lisp", 3) } }
      xref.show(make_ok(refs), "definition")
      assert.equals(1, #cmd_calls)
      assert.truthy(cmd_calls[1]:find("/a.lisp"))
      assert.is_false(select_called)
      assert.is_false(copen_called)
    end)

    it("uses quickfix when vim.ui.select is not hooked (multiple results)", function()
      -- vim.ui.select remains as the builtin → ui_select_is_hooked() = false
      local refs = {
        { "FOO", make_loc("/a.lisp", 3) },
        { "BAR", make_loc("/b.lisp", 7) },
      }
      xref.show(make_ok(refs), "references")
      assert.equals(1, #qflist_calls)
      assert.equals("references", qflist_calls[1].opts.title:match("references"))
      assert.is_true(copen_called)
    end)

    it("uses vim.ui.select when hooked (multiple results)", function()
      -- Replace vim.ui.select so ui_select_is_hooked() returns true
      local select_items
      vim.ui.select = function(items, _, _cb) select_items = items end
      local refs = {
        { "FOO", make_loc("/a.lisp", 3) },
        { "BAR", make_loc("/b.lisp", 7) },
      }
      xref.show(make_ok(refs), "calls")
      assert.is_not_nil(select_items)
      assert.equals(2, #select_items)
      assert.is_false(copen_called)
      assert.equals(0, #qflist_calls)
    end)
  end)
end)
