-- tests/unit/client_spec.lua
-- Unit tests for pure helper functions in swank.client.
-- No connection or Swank server required.

local client = require("swank.client")

-- ---------------------------------------------------------------------------
-- _is_symbol_like
-- ---------------------------------------------------------------------------

describe("client._is_symbol_like", function()
  -- Valid CL symbols
  it("accepts plain symbol names", function()
    assert.is_true(client._is_symbol_like("mapcar"))
    assert.is_true(client._is_symbol_like("MAPCAR"))
    assert.is_true(client._is_symbol_like("my-function"))
    assert.is_true(client._is_symbol_like("*special-var*"))
    assert.is_true(client._is_symbol_like("+constant+"))
    assert.is_true(client._is_symbol_like("predicate?"))
  end)

  it("accepts package-qualified symbols", function()
    assert.is_true(client._is_symbol_like("cl:mapcar"))
    assert.is_true(client._is_symbol_like("swank:eval-and-grab-output"))
    assert.is_true(client._is_symbol_like("sb-ext:quit"))
  end)

  it("accepts keyword symbols", function()
    assert.is_true(client._is_symbol_like(":ok"))
    assert.is_true(client._is_symbol_like(":swank-repl"))
    assert.is_true(client._is_symbol_like(":abort"))
  end)

  -- Invalid inputs
  it("rejects nil and empty string", function()
    assert.is_false(client._is_symbol_like(nil))
    assert.is_false(client._is_symbol_like(""))
    assert.is_false(client._is_symbol_like("   "))
  end)

  it("rejects strings with whitespace", function()
    assert.is_false(client._is_symbol_like("two words"))
    assert.is_false(client._is_symbol_like("(+ 1 2)"))
    assert.is_false(client._is_symbol_like("a b"))
  end)

  it("rejects bare numbers", function()
    -- A bare integer is not a symbol (though CL allows | | escaping, we don't)
    assert.is_false(client._is_symbol_like("42"))
    assert.is_false(client._is_symbol_like("3.14"))
  end)

  it("rejects parenthesised expressions", function()
    assert.is_false(client._is_symbol_like("(defun foo () nil)"))
    assert.is_false(client._is_symbol_like("(+ 1 2)"))
  end)
end)

-- ---------------------------------------------------------------------------
-- _plist
-- ---------------------------------------------------------------------------

describe("client._plist", function()
  it("converts alternating key/value list to table", function()
    local t = client._plist({ ":name", "SBCL", ":version", "2.3.0" })
    assert.equals("SBCL",  t[":name"])
    assert.equals("2.3.0", t[":version"])
  end)

  it("lowercases the keys", function()
    local t = client._plist({ ":NAME", "foo", ":VERSION", "bar" })
    assert.equals("foo", t[":name"])
    assert.equals("bar", t[":version"])
  end)

  it("returns empty table for empty input", function()
    local t = client._plist({})
    assert.equals(0, #t)
  end)

  it("returns empty table for non-table input", function()
    local t = client._plist(nil)
    assert.equals(0, #t)
    t = client._plist("not a table")
    assert.equals(0, #t)
  end)

  it("handles nested values without mangling them", function()
    local inner = { ":file", "/tmp/foo.lisp" }
    local t = client._plist({ ":location", inner })
    assert.same(inner, t[":location"])
  end)
end)

-- ---------------------------------------------------------------------------
-- _form_at_cursor_paren  (requires a real buffer)
-- ---------------------------------------------------------------------------

describe("client._form_at_cursor_paren", function()
  local function with_buf(lines, cursor_row, fn)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", width = 80, height = 20, row = 0, col = 0,
      style = "minimal",
    })
    vim.api.nvim_win_set_cursor(win, { cursor_row, 0 })
    local result = fn()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    return result
  end

  it("returns a single-line top-level form", function()
    local form = with_buf({ "(defun foo () nil)" }, 1, function()
      return client._form_at_cursor_paren()
    end)
    assert.equals("(defun foo () nil)", form)
  end)

  it("collects a multi-line form", function()
    local lines = {
      "(defun bar (x)",
      "  (* x 2))",
    }
    local form = with_buf(lines, 1, function()
      return client._form_at_cursor_paren()
    end)
    assert.equals("(defun bar (x)\n  (* x 2))", form)
  end)

  it("finds the form when cursor is on a nested line", function()
    local lines = {
      "(defun baz (x)",
      "  (+ x 1))",
    }
    local form = with_buf(lines, 2, function()
      return client._form_at_cursor_paren()
    end)
    assert.equals("(defun baz (x)\n  (+ x 1))", form)
  end)

  it("handles string literals containing parens", function()
    local form = with_buf({ '(defvar *msg* "(not a (close)")' }, 1, function()
      return client._form_at_cursor_paren()
    end)
    assert.equals('(defvar *msg* "(not a (close)")', form)
  end)

  it("ignores semicolon-commented parens", function()
    local lines = {
      "(defun qux () ; this ) is a comment",
      "  :done)",
    }
    local form = with_buf(lines, 1, function()
      return client._form_at_cursor_paren()
    end)
    assert.equals("(defun qux () ; this ) is a comment\n  :done)", form)
  end)
end)

-- ---------------------------------------------------------------------------
-- _innermost_operator
-- ---------------------------------------------------------------------------

describe("client._innermost_operator", function()
  local function with_line(line, col_1idx, fn)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", width = 80, height = 5, row = 0, col = 0,
      style = "minimal",
    })
    vim.api.nvim_win_set_cursor(win, { 1, col_1idx - 1 })  -- 0-indexed col
    local result = fn()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    return result
  end

  it("finds operator of simple call", function()
    -- cursor inside the call, after the operator
    local op = with_line("(mapcar #'foo list)", 10, function()
      return client._innermost_operator()
    end)
    assert.equals("mapcar", op)
  end)

  it("finds innermost operator in nested calls", function()
    -- "(foo (bar |))" — cursor at position of | (inside bar's args)
    local op = with_line("(foo (bar x))", 10, function()
      return client._innermost_operator()
    end)
    assert.equals("bar", op)
  end)

  it("returns nil when cursor is not inside a call", function()
    local op = with_line("foo bar baz", 5, function()
      return client._innermost_operator()
    end)
    assert.is_nil(op)
  end)
end)
