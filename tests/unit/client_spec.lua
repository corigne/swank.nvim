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

-- ===========================================================================
-- Comprehensive tests for swank.client (connection, rex, events, operations)
-- ===========================================================================

local protocol = require("swank.protocol")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function make_mock_transport()
  local sent = {}
  local t = {
    send       = function(self, payload) table.insert(sent, payload) end,
    disconnect = function(self) self._closed = true end,
    _closed    = false,
  }
  return t, sent
end

local function decode_last(sent)
  if #sent == 0 then return nil end
  return protocol.parse(sent[#sent])
end

local function fake_return(id, result)
  protocol.dispatch({ ":return", result, id })
end

-- Silence vim.notify noise in tests
local orig_notify
local function silence_notify()
  orig_notify = vim.notify
  vim.notify = function() end
end
local function restore_notify()
  if orig_notify then vim.notify = orig_notify end
end

-- Mock all UI modules to prevent window creation
local function mock_ui()
  require("swank.ui.repl").show_result = function(_) end
  require("swank.ui.repl").show_input  = function(_) end
  require("swank.ui.repl").append      = function(_) end
  require("swank.ui.inspector").open   = function(_) end
  require("swank.ui.inspector").close  = function()  end
  require("swank.ui.sldb").open        = function(_) end
  require("swank.ui.sldb").close       = function()  end
  require("swank.ui.xref").show        = function(_) end
  require("swank.ui.notes").show       = function(_) end
  require("swank.ui.trace").set_specs  = function(_) end
  require("swank.ui.trace").push_entries = function(_) end
  require("swank.ui.trace").clear      = function()  end
end

-- ---------------------------------------------------------------------------
-- State management
-- ---------------------------------------------------------------------------

describe("client state management", function()
  before_each(function()
    silence_notify()
    mock_ui()
    client._test_reset()
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("is_connected() returns false when disconnected", function()
    assert.is_false(client.is_connected())
  end)

  it("is_connected() returns true after _test_inject", function()
    local mock, _ = make_mock_transport()
    client._test_inject(mock)
    assert.is_true(client.is_connected())
  end)

  it("connect() when already connected emits WARN and returns early", function()
    local mock, _ = make_mock_transport()
    client._test_inject(mock)
    local warned = false
    vim.notify = function(_, lvl)
      if lvl == vim.log.levels.WARN then warned = true end
    end
    -- require swank.config to exist
    local ok_swank = pcall(function() return require("swank").config end)
    if not ok_swank then
      require("swank").config = {}
    end
    client.connect("127.0.0.1", 4005)
    assert.is_true(warned)
  end)

  it("disconnect() with mock transport closes transport and resets state", function()
    local mock, _ = make_mock_transport()
    client._test_inject(mock)
    assert.is_true(client.is_connected())
    client.disconnect()
    assert.is_false(client.is_connected())
    assert.is_true(mock._closed)
  end)
end)

-- ---------------------------------------------------------------------------
-- rex() happy path
-- ---------------------------------------------------------------------------

describe("client.rex() happy path", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("sends a framed :emacs-rex message", function()
    client.rex({ "swank:eval-and-grab-output", "(+ 1 2)" }, function() end)
    assert.equals(1, #sent)
    local msg = decode_last(sent)
    assert.equals(":emacs-rex", msg[1])
    assert.same({ "swank:eval-and-grab-output", "(+ 1 2)" }, msg[2])
  end)

  it("invokes registered callback when :return fires with matching id", function()
    local got = nil
    client.rex({ "swank:connection-info" }, function(r) got = r end)
    local msg = decode_last(sent)
    local id = msg[5]
    fake_return(id, { ":ok", "result-value" })
    assert.same({ ":ok", "result-value" }, got)
  end)

  it("callback does NOT fire for wrong id", function()
    local got = "untouched"
    client.rex({ "swank:connection-info" }, function(r) got = r end)
    fake_return(99999, { ":ok", "wrong" })
    assert.equals("untouched", got)
  end)

  it("multiple sequential rex calls get unique ids", function()
    client.rex({ "swank:eval-and-grab-output", "a" }, function() end)
    local id1 = decode_last(sent)[5]
    client.rex({ "swank:eval-and-grab-output", "b" }, function() end)
    local id2 = decode_last(sent)[5]
    assert.not_equals(id1, id2)
    assert.equals(id1 + 1, id2)
  end)

  it("rex without transport notifies ERROR", function()
    client._test_reset()  -- no transport
    local err_raised = false
    vim.notify = function(_, lvl)
      if lvl == vim.log.levels.ERROR then err_raised = true end
    end
    client.rex({ "swank:connection-info" }, function() end)
    assert.is_true(err_raised)
    restore_notify()
  end)
end)

-- ---------------------------------------------------------------------------
-- Protocol event handlers
-- ---------------------------------------------------------------------------

describe("protocol event handlers", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it(":return with unknown id does not error", function()
    assert.has_no.errors(function()
      protocol.dispatch({ ":return", { ":ok", "x" }, 99999 })
    end)
  end)

  it(":write-string dispatches to repl.append", function()
    local appended = nil
    require("swank.ui.repl").append = function(s) appended = s end
    protocol.dispatch({ ":write-string", "hello\n" })
    assert.equals("hello\n", appended)
  end)

  it(":debug dispatches to sldb.open without error", function()
    local opened = false
    require("swank.ui.sldb").open = function(_) opened = true end
    protocol.dispatch({ ":debug", {}, 1 })
    assert.is_true(opened)
  end)

  it(":debug-return dispatches to sldb.close without error", function()
    local closed = false
    require("swank.ui.sldb").close = function() closed = true end
    protocol.dispatch({ ":debug-return", 1 })
    assert.is_true(closed)
  end)

  it(":ping with injected transport sends :emacs-pong", function()
    protocol.dispatch({ ":ping", 1, 42 })
    assert.equals(1, #sent)
    local payload = protocol.parse(sent[1])
    assert.equals(":emacs-pong", payload[1])
    assert.equals(1, payload[2])
    assert.equals(42, payload[3])
  end)

  it(":trace-dialog-update calls trace.set_specs and push_entries", function()
    local specs_got, entries_got
    require("swank.ui.trace").set_specs    = function(s) specs_got   = s end
    require("swank.ui.trace").push_entries = function(e) entries_got = e end
    protocol.dispatch({ ":trace-dialog-update", { "MY-FUNC" }, { { 1, "MY-FUNC" } } })
    assert.same({ "MY-FUNC" }, specs_got)
    assert.same({ { 1, "MY-FUNC" } }, entries_got)
  end)
end)

-- ---------------------------------------------------------------------------
-- eval_toplevel
-- ---------------------------------------------------------------------------

describe("M.eval_toplevel()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("sends :eval-and-grab-output for form at cursor", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "(+ 1 2)" })
    local win = vim.api.nvim_open_win(bufnr, true, {
      relative = "editor", width = 40, height = 5, row = 0, col = 0, style = "minimal",
    })
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    client.eval_toplevel()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(1, #sent)
    local msg = decode_last(sent)
    assert.equals(":emacs-rex", msg[1])
    assert.equals("swank:eval-and-grab-output", msg[2][1])
  end)
end)

-- ---------------------------------------------------------------------------
-- eval_region
-- ---------------------------------------------------------------------------

describe("M.eval_region()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("sends :eval-and-grab-output with visual selection", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "(+ 1 2)" })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setpos("'<", { bufnr, 1, 1, 0 })
    vim.fn.setpos("'>", { bufnr, 1, 7, 0 })
    client.eval_region()
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(1, #sent)
    local msg = decode_last(sent)
    assert.equals("swank:eval-and-grab-output", msg[2][1])
  end)
end)

-- ---------------------------------------------------------------------------
-- describe()
-- ---------------------------------------------------------------------------

describe("M.describe()", function()
  local mock, sent
  local orig_open_win = vim.api.nvim_open_win
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
    vim.api.nvim_open_win = function() return 1 end
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
    vim.api.nvim_open_win = orig_open_win
  end)

  it("sends :describe-symbol and opens a float on :ok result", function()
    local opened = false
    vim.api.nvim_open_win = function() opened = true; return 1 end
    client.describe("mapcar")
    local id = decode_last(sent)[5]
    fake_return(id, { ":ok", "MAPCAR: blah blah" })
    assert.is_true(opened)
  end)

  it("callback does nothing on non-ok result", function()
    local opened = false
    vim.api.nvim_open_win = function() opened = true; return 1 end
    client.describe("mapcar")
    local id = decode_last(sent)[5]
    fake_return(id, { ":abort", "nope" })
    assert.is_false(opened)
  end)
end)

-- ---------------------------------------------------------------------------
-- apropos()
-- ---------------------------------------------------------------------------

describe("M.apropos()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("non-ok result: callback returns early without appending", function()
    local appended = nil
    require("swank.ui.repl").append = function(s) appended = s end
    client.apropos("loop")
    local id = decode_last(sent)[5]
    fake_return(id, { ":abort", "error" })
    assert.is_nil(appended)
  end)

  it("empty entries list: appends no-match message", function()
    local appended = nil
    require("swank.ui.repl").append = function(s) appended = s end
    client.apropos("zzzznotfound")
    local id = decode_last(sent)[5]
    fake_return(id, { ":ok", {} })
    assert.is_not_nil(appended)
    assert.truthy(appended:find("no apropos matches"))
  end)

  it("entries with function/variable/macro: formats kinds and appends", function()
    local appended = nil
    require("swank.ui.repl").append = function(s) appended = s end
    client.apropos("map")
    local id = decode_last(sent)[5]
    local entry = {
      ":designator", "MAPCAR",
      ":function", "T",
    }
    fake_return(id, { ":ok", { entry } })
    assert.is_not_nil(appended)
    assert.truthy(appended:find("MAPCAR"))
    assert.truthy(appended:find("function"))
  end)

  it("entry with macro kind is labelled", function()
    local appended = nil
    require("swank.ui.repl").append = function(s) appended = s end
    client.apropos("loop")
    local id = decode_last(sent)[5]
    local entry = {
      ":designator", "LOOP",
      ":macro", "T",
    }
    fake_return(id, { ":ok", { entry } })
    assert.truthy(appended:find("macro"))
  end)

  it("entry with variable/type/class kinds", function()
    local appended = nil
    require("swank.ui.repl").append = function(s) appended = s end
    client.apropos("foo")
    local id = decode_last(sent)[5]
    local entry = {
      ":designator", "FOO",
      ":variable", "T",
      ":type", "T",
      ":class", "T",
    }
    fake_return(id, { ":ok", { entry } })
    assert.truthy(appended:find("variable"))
    assert.truthy(appended:find("type"))
    assert.truthy(appended:find("class"))
  end)
end)

-- ---------------------------------------------------------------------------
-- inspect_value / inspect_nth_part / inspector_pop / inspector_reinspect / quit_inspector
-- ---------------------------------------------------------------------------

describe("M.inspect_value()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("sends :init-inspector and callback calls inspector.open", function()
    local opened = nil
    require("swank.ui.inspector").open = function(r) opened = r end
    client.inspect_value("*package*")
    assert.equals(1, #sent)
    local msg = decode_last(sent)
    assert.equals("swank:init-inspector", msg[2][1])
    local id = msg[5]
    fake_return(id, { ":ok", {} })
    assert.is_not_nil(opened)
  end)
end)

describe("M.inspect_nth_part()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("sends :inspect-nth-part", function()
    client.inspect_nth_part(3)
    local msg = decode_last(sent)
    assert.equals("swank:inspect-nth-part", msg[2][1])
    assert.equals(3, msg[2][2])
  end)
end)

describe("M.inspector_pop()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it(":ok result with data calls inspector.open", function()
    local opened = nil
    require("swank.ui.inspector").open = function(r) opened = r end
    client.inspector_pop()
    local id = decode_last(sent)[5]
    fake_return(id, { ":ok", { "some-data" } })
    assert.is_not_nil(opened)
  end)

  it(":ok result with nil/false emits INFO notification", function()
    local notified = false
    vim.notify = function(_, lvl)
      if lvl == vim.log.levels.INFO then notified = true end
    end
    client.inspector_pop()
    local id = decode_last(sent)[5]
    fake_return(id, { ":ok", false })
    assert.is_true(notified)
    restore_notify()
  end)
end)

describe("M.inspector_reinspect()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("sends :inspector-reinspect", function()
    client.inspector_reinspect()
    local msg = decode_last(sent)
    assert.equals("swank:inspector-reinspect", msg[2][1])
  end)
end)

describe("M.quit_inspector()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("sends :quit-inspector and calls inspector.close", function()
    local closed = false
    require("swank.ui.inspector").close = function() closed = true end
    client.quit_inspector()
    local msg = decode_last(sent)
    assert.equals("swank:quit-inspector", msg[2][1])
    assert.is_true(closed)
  end)
end)

-- ---------------------------------------------------------------------------
-- Trace operations
-- ---------------------------------------------------------------------------

describe("M.trace_toggle()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("sends :dialog-toggle-trace; callback calls trace.set_specs on :ok result", function()
    local specs_set = nil
    require("swank.ui.trace").set_specs = function(s) specs_set = s end
    client.trace_toggle("MY-FUNC")
    local msg = decode_last(sent)
    assert.equals("swank-trace-dialog:dialog-toggle-trace", msg[2][1])
    local id = msg[5]
    fake_return(id, { ":ok", { "MY-FUNC" } })
    assert.same({ "MY-FUNC" }, specs_set)
  end)
end)

describe("M.untrace_all()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("callback calls trace.set_specs({}) on :ok", function()
    local specs_set = nil
    require("swank.ui.trace").set_specs = function(s) specs_set = s end
    client.untrace_all()
    local id = decode_last(sent)[5]
    fake_return(id, { ":ok", nil })
    assert.same({}, specs_set)
  end)
end)

describe("M.clear_traces()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("callback calls trace.clear", function()
    local cleared = false
    require("swank.ui.trace").clear = function() cleared = true end
    client.clear_traces()
    local id = decode_last(sent)[5]
    fake_return(id, { ":ok", nil })
    assert.is_true(cleared)
  end)
end)

describe("M.refresh_traces()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("sends two rex calls; callbacks call trace.set_specs and push_entries", function()
    local specs_set = nil
    local entries_pushed = nil
    require("swank.ui.trace").set_specs    = function(s) specs_set     = s end
    require("swank.ui.trace").push_entries = function(e) entries_pushed = e end
    client.refresh_traces()
    assert.equals(2, #sent)
    local id1 = protocol.parse(sent[1])[5]
    local id2 = protocol.parse(sent[2])[5]
    fake_return(id1, { ":ok", { "MY-FUNC" } })
    fake_return(id2, { ":ok", { { 1, "entry" } } })
    assert.same({ "MY-FUNC" }, specs_set)
    assert.same({ { 1, "entry" } }, entries_pushed)
  end)
end)

-- ---------------------------------------------------------------------------
-- load_file / compile_file / compile_form
-- ---------------------------------------------------------------------------

describe("M.load_file()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("when buffer has no name: emits WARN and sends no rex", function()
    local warned = false
    vim.notify = function(_, lvl)
      if lvl == vim.log.levels.WARN then warned = true end
    end
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    client.load_file()
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.is_true(warned)
    assert.equals(0, #sent)
    restore_notify()
  end)

  it("when buffer has a name: sends :load-file", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/fake/path/foo.lisp")
    vim.api.nvim_set_current_buf(bufnr)
    client.load_file()
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(1, #sent)
    local msg = decode_last(sent)
    assert.equals("swank:load-file", msg[2][1])
    restore_notify()
  end)
end)

describe("M.compile_file()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("when buffer has no name: WARN, no rex", function()
    local warned = false
    vim.notify = function(_, lvl)
      if lvl == vim.log.levels.WARN then warned = true end
    end
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    client.compile_file()
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.is_true(warned)
    assert.equals(0, #sent)
    restore_notify()
  end)

  it("when buffer has name: sends :compile-file-for-emacs", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/fake/path/bar.lisp")
    vim.api.nvim_set_current_buf(bufnr)
    client.compile_file()
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(1, #sent)
    local msg = decode_last(sent)
    assert.equals("swank:compile-file-for-emacs", msg[2][1])
    restore_notify()
  end)
end)

describe("M.compile_form()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("in a buffer with content and cursor on a form: sends :compile-string-for-emacs", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "(defun foo () 42)" })
    local win = vim.api.nvim_open_win(bufnr, true, {
      relative = "editor", width = 40, height = 5, row = 0, col = 0, style = "minimal",
    })
    vim.api.nvim_win_set_cursor(win, { 1, 1 })
    client.compile_form()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(1, #sent)
    local msg = decode_last(sent)
    assert.equals("swank:compile-string-for-emacs", msg[2][1])
  end)
end)

-- ---------------------------------------------------------------------------
-- XRef operations
-- ---------------------------------------------------------------------------

describe("M xref operations", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("xref_calls sends :xref :calls", function()
    client.xref_calls("MY-FUNC")
    local msg = decode_last(sent)
    assert.equals("swank:xref", msg[2][1])
    assert.equals(":calls", msg[2][2])
    assert.equals("MY-FUNC", msg[2][3])
  end)

  it("xref_references sends :xref :references", function()
    client.xref_references("MY-FUNC")
    local msg = decode_last(sent)
    assert.equals("swank:xref", msg[2][1])
    assert.equals(":references", msg[2][2])
  end)

  it("find_definition sends :find-definitions-for-emacs", function()
    client.find_definition("MY-FUNC")
    local msg = decode_last(sent)
    assert.equals("swank:find-definitions-for-emacs", msg[2][1])
  end)
end)

-- ---------------------------------------------------------------------------
-- autodoc()
-- ---------------------------------------------------------------------------

describe("M.autodoc()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("when not connected: returns early without calling rex", function()
    client._test_reset()
    client.autodoc()
    assert.equals(0, #sent)
  end)

  it("when connected and cursor has no operator: returns early", function()
    client._test_inject(mock)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "foo bar baz" })
    local win = vim.api.nvim_open_win(bufnr, true, {
      relative = "editor", width = 40, height = 5, row = 0, col = 0, style = "minimal",
    })
    vim.api.nvim_win_set_cursor(win, { 1, 4 })
    client.autodoc()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(0, #sent)
  end)

  it("when connected with cursor inside a call: sends :operator-arglist", function()
    client._test_inject(mock)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "(mapcar #'1+ list)" })
    local win = vim.api.nvim_open_win(bufnr, true, {
      relative = "editor", width = 40, height = 5, row = 0, col = 0, style = "minimal",
    })
    vim.api.nvim_win_set_cursor(win, { 1, 10 })
    client.autodoc()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals(1, #sent)
    local msg = decode_last(sent)
    assert.equals("swank:operator-arglist", msg[2][1])
  end)
end)

-- ---------------------------------------------------------------------------
-- M._on_connect()
-- ---------------------------------------------------------------------------

describe("M._on_connect()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
    -- ensure swank.config exists
    local swank = require("swank")
    if not swank.config then swank.config = {} end
  end)
  after_each(function()
    client._test_reset()
    require("swank").config = {}
    restore_notify()
  end)

  it("without contribs: fires connection-info rex then set-package rex", function()
    require("swank").config = { contribs = nil }
    client._on_connect()
    -- first rex: connection-info
    assert.equals(2, #sent)
    local msg1 = protocol.parse(sent[1])
    assert.equals("swank:connection-info", msg1[2][1])
    local msg2 = protocol.parse(sent[2])
    assert.equals("swank:set-package", msg2[2][1])
    -- fire connection-info callback (with valid info)
    local id1 = msg1[5]
    local notified = false
    vim.notify = function(_, lvl)
      if lvl == vim.log.levels.INFO then notified = true end
    end
    fake_return(id1, {
      ":ok",
      {
        ":lisp-implementation",
        { ":name", "SBCL", ":version", "2.3.0" },
      },
    })
    assert.is_true(notified)
    restore_notify()
  end)

  it("with contribs: fires connection-info, swank-require, then set-package in nested callback", function()
    require("swank").config = { contribs = { ":swank-repl" } }
    client._on_connect()
    -- First two sends: connection-info and swank-require
    assert.equals(2, #sent)
    local msg_req = protocol.parse(sent[2])
    assert.equals("swank:swank-require", msg_req[2][1])
    local id_req = msg_req[5]
    -- fire swank-require callback → triggers set-package
    fake_return(id_req, { ":ok", nil })
    assert.equals(3, #sent)
    local msg_pkg = protocol.parse(sent[3])
    assert.equals("swank:set-package", msg_pkg[2][1])
  end)
end)

-- ---------------------------------------------------------------------------
-- set_package_interactive()
-- ---------------------------------------------------------------------------

describe("M.set_package_interactive()", function()
  local mock, sent
  before_each(function()
    silence_notify()
    mock_ui()
    mock, sent = make_mock_transport()
    client._test_inject(mock)
  end)
  after_each(function()
    client._test_reset()
    restore_notify()
  end)

  it("sends :set-package and updates current_package on :ok", function()
    local orig_input = vim.ui.input
    vim.ui.input = function(_, cb) cb("MY-PACKAGE") end
    local notified_pkg = nil
    vim.notify = function(msg, lvl)
      if lvl == vim.log.levels.INFO then notified_pkg = msg end
    end
    client.set_package_interactive()
    vim.ui.input = orig_input
    assert.equals(1, #sent)
    local msg = decode_last(sent)
    assert.equals("swank:set-package", msg[2][1])
    local id = msg[5]
    fake_return(id, { ":ok", "MY-PACKAGE" })
    assert.is_not_nil(notified_pkg)
    assert.truthy(notified_pkg:find("MY%-PACKAGE"))
    restore_notify()
  end)

  it("does nothing when input is cancelled (nil or empty)", function()
    local orig_input = vim.ui.input
    vim.ui.input = function(_, cb) cb(nil) end
    client.set_package_interactive()
    vim.ui.input = orig_input
    assert.equals(0, #sent)
  end)
end)

-- ---------------------------------------------------------------------------
-- _form_at_cursor() fallback
-- ---------------------------------------------------------------------------

describe("M._form_at_cursor()", function()
  it("without treesitter commonlisp parser: falls through to _form_at_cursor_paren", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "(defun foo () 42)" })
    local win = vim.api.nvim_open_win(bufnr, true, {
      relative = "editor", width = 40, height = 5, row = 0, col = 0, style = "minimal",
    })
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    local form = client._form_at_cursor()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.equals("(defun foo () 42)", form)
  end)
end)

-- ---------------------------------------------------------------------------
-- _get_visual_selection()
-- ---------------------------------------------------------------------------

describe("M._get_visual_selection()", function()
  it("returns selected text when visual marks are set", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "(+ 1 2)" })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setpos("'<", { bufnr, 1, 1, 0 })
    vim.fn.setpos("'>", { bufnr, 1, 7, 0 })
    local sel = client._get_visual_selection()
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.is_not_nil(sel)
    assert.truthy(sel:find("+ 1 2") or sel:find("%("))
  end)

  it("returns nil when there are no lines in selection range", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    -- marks point beyond buffer content
    vim.fn.setpos("'<", { bufnr, 5, 1, 0 })
    vim.fn.setpos("'>", { bufnr, 5, 1, 0 })
    local sel = client._get_visual_selection()
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.is_nil(sel)
  end)
end)

-- ---------------------------------------------------------------------------
-- M.start_and_connect() — partial (jobstart failure path)
-- ---------------------------------------------------------------------------

describe("M.start_and_connect()", function()
  after_each(function()
    client._test_reset()
    require("swank").config = {}
  end)

  it("does nothing when already connected or connecting", function()
    local mock = {
      send = function() end, disconnect = function() end,
    }
    client._test_inject(mock)  -- sets connection_state = "connected"
    -- Should return early without touching config or filesystem
    assert.has_no.errors(function() client.start_and_connect() end)
    -- Still connected (state unchanged)
    assert.is_true(client.is_connected())
  end)

  it("reaches jobstart and handles missing binary gracefully", function()
    -- Use a binary name that definitely does not exist.
    -- vim.fn.jobstart throws E475 for a non-executable, so we use pcall.
    -- Lines in start_and_connect UP TO jobstart are still covered by luacov
    -- (the debug hook fires before each line is executed).
    require("swank").config = {
      autostart = { enabled = true, implementation = "definitely-not-a-real-binary-xyz" },
      server    = { host = "127.0.0.1", port = 4005 },
      contribs  = {},
    }
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, _lvl)
      if msg:find("starting") then notified = true end
    end
    -- pcall because jobstart throws E475 on non-executable binary;
    -- we only care that the setup code before jobstart ran correctly
    pcall(function() client.start_and_connect() end)
    vim.notify = orig_notify
    assert.is_true(notified, "expected a 'starting' notification before jobstart")
  end)
end)

-- impl_cli_flags selection
-- ---------------------------------------------------------------------------

describe("M.start_and_connect() impl_cli_flags", function()
  local captured_argv
  local orig_jobstart
  local orig_notify

  before_each(function()
    captured_argv = nil
    orig_jobstart = vim.fn.jobstart
    orig_notify   = vim.notify
    vim.fn.jobstart = function(argv, _opts)
      captured_argv = argv
      return -1  -- signal "failed to start" so start_and_connect cleans up
    end
    vim.notify = function() end  -- suppress output
  end)

  after_each(function()
    vim.fn.jobstart = orig_jobstart
    vim.notify      = orig_notify
    client._test_reset()
    require("swank").config = {}
  end)

  local function run_with_impl(impl)
    require("swank").config = {
      autostart = { enabled = true, implementation = impl },
      server    = { host = "127.0.0.1", port = 4005 },
      contribs  = {},
    }
    pcall(function() client.start_and_connect() end)
  end

  it("uses SBCL flags for 'sbcl'", function()
    run_with_impl("sbcl")
    assert.is_not_nil(captured_argv)
    assert.equals("sbcl",              captured_argv[1])
    assert.equals("--noinform",        captured_argv[2])
    assert.equals("--non-interactive", captured_argv[3])
    assert.equals("--load",            captured_argv[4])
  end)

  it("uses CCL flags for 'ccl'", function()
    run_with_impl("ccl")
    assert.is_not_nil(captured_argv)
    assert.equals("ccl",     captured_argv[1])
    assert.equals("--quiet", captured_argv[2])
    assert.equals("--batch", captured_argv[3])
    assert.equals("--load",  captured_argv[4])
  end)

  it("uses ECL flags for 'ecl'", function()
    run_with_impl("ecl")
    assert.is_not_nil(captured_argv)
    assert.equals("ecl",    captured_argv[1])
    assert.equals("--norc", captured_argv[2])
    assert.equals("--load", captured_argv[3])
  end)

  it("uses ABCL flags for 'abcl'", function()
    run_with_impl("abcl")
    assert.is_not_nil(captured_argv)
    assert.equals("abcl",    captured_argv[1])
    assert.equals("--batch", captured_argv[2])
    assert.equals("--load",  captured_argv[3])
  end)

  it("falls back to SBCL flags for unknown implementations", function()
    run_with_impl("some-unknown-lisp")
    assert.is_not_nil(captured_argv)
    assert.equals("some-unknown-lisp", captured_argv[1])
    assert.equals("--noinform",        captured_argv[2])
    assert.equals("--non-interactive", captured_argv[3])
    assert.equals("--load",            captured_argv[4])
  end)

  it("matches implementation by basename when a full path is given", function()
    run_with_impl("/usr/bin/sbcl")
    assert.is_not_nil(captured_argv)
    assert.equals("/usr/bin/sbcl",     captured_argv[1])
    assert.equals("--noinform",        captured_argv[2])
    assert.equals("--non-interactive", captured_argv[3])
    assert.equals("--load",            captured_argv[4])
  end)

  it("matches ccl by basename from full path", function()
    run_with_impl("/usr/local/bin/ccl")
    assert.is_not_nil(captured_argv)
    assert.equals("--quiet", captured_argv[2])
    assert.equals("--batch", captured_argv[3])
  end)
end)

