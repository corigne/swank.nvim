-- tests/unit/repl_spec.lua — REPL output formatting

local repl = require("swank.ui.repl")

-- Cache the real append before any describe block mocks it
local real_append = repl.append

describe("repl", function()
  local captured = {}

  -- Intercept M.append so tests don't need a real buffer
  before_each(function()
    captured = {}
    repl.append = function(text) table.insert(captured, text) end
  end)

  local function all_output()
    return table.concat(captured, "")
  end

  -- ── show_input ──────────────────────────────────────────────────────────
  describe("show_input", function()
    it("prefixes single-line text with '; '", function()
      repl.show_input("(+ 1 2)")
      assert.is_true(all_output():find("; (+ 1 2)", 1, true) ~= nil)
    end)

    it("prefixes each line of multi-line text", function()
      repl.show_input("(defun foo ()\n  42)")
      local out = all_output()
      assert.is_true(out:find("; %(defun foo %(%)") ~= nil)
      assert.is_true(out:find(";   42") ~= nil)
    end)
  end)

  -- ── show_result ─────────────────────────────────────────────────────────
  describe("show_result", function()
    it("does nothing for non-table input", function()
      repl.show_result(nil)
      repl.show_result("bad")
      repl.show_result(42)
      assert.equals("", all_output())
    end)

    it("formats a plain :ok result", function()
      repl.show_result({ ":ok", "3" })
      local out = all_output()
      assert.is_true(out:find("=> 3") ~= nil)
    end)

    it("formats an :ok with nil value", function()
      repl.show_result({ ":ok", nil })
      local out = all_output()
      assert.is_true(out:find("=>") ~= nil)
    end)

    it("formats eval-and-grab-output with output and value", function()
      repl.show_result({ ":ok", { "Hello\n", "42" } })
      local out = all_output()
      assert.is_true(out:find("Hello") ~= nil)
      assert.is_true(out:find("=> 42") ~= nil)
    end)

    it("formats eval-and-grab-output with empty output", function()
      repl.show_result({ ":ok", { "", "NIL" } })
      local out = all_output()
      -- empty output should not appear as a separate line
      assert.is_true(out:find("=> NIL") ~= nil)
    end)

    it("formats :abort with no condition", function()
      repl.show_result({ ":abort" })
      local out = all_output()
      assert.is_true(out:find("Aborted") ~= nil)
    end)

    it("formats :abort with a condition message", function()
      repl.show_result({ ":abort", "Division by zero" })
      local out = all_output()
      assert.is_true(out:find("Aborted") ~= nil)
      assert.is_true(out:find("Division by zero") ~= nil)
    end)

    it("appends a trailing newline after every result", function()
      repl.show_result({ ":ok", "x" })
      local out = all_output()
      assert.equals("\n", out:sub(-1))
    end)
  end)
end)

-- ── repl.append real buffer ──────────────────────────────────────────────────
-- These tests exercise the actual M.append / ensure_buf code paths (not mocked).

describe("repl.append (direct buffer)", function()
  local saved_append
  local saved_cmd

  before_each(function()
    saved_append = repl.append
    repl.append = real_append
    -- stub vim.cmd so open_win's split command doesn't fail in headless
    saved_cmd = vim.cmd
    vim.cmd = function(c)
      if type(c) == "string" and c:match("split") then return end
      saved_cmd(c)
    end
  end)

  after_each(function()
    repl.append = saved_append
    vim.cmd = saved_cmd
  end)

  local function buf_lines()
    local buf = vim.fn.bufnr("swank://repl")
    if buf == -1 then return {} end
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  local function lines_contain(text)
    for _, l in ipairs(buf_lines()) do
      if l:find(text, 1, true) then return true end
    end
    return false
  end

  it("creates the swank://repl buffer on first call", function()
    repl.append("test-create-buffer\n")
    assert.is_true(vim.fn.bufnr("swank://repl") ~= -1)
  end)

  it("appended text appears in the buffer", function()
    repl.append("sentinel-abc-123\n")
    assert.is_true(lines_contain("sentinel-abc-123"))
  end)

  it("multi-line text is split into separate buffer lines", function()
    repl.append("line-alpha\nline-beta\nline-gamma\n")
    assert.is_true(lines_contain("line-alpha"))
    assert.is_true(lines_contain("line-beta"))
    assert.is_true(lines_contain("line-gamma"))
  end)

  it("successive calls accumulate in the same buffer", function()
    repl.append("first-call\n")
    repl.append("second-call\n")
    assert.is_true(lines_contain("first-call"))
    assert.is_true(lines_contain("second-call"))
  end)

  it("buffer is non-modifiable after append", function()
    repl.append("modifiable-check\n")
    local buf = vim.fn.bufnr("swank://repl")
    assert.is_false(vim.bo[buf].modifiable)
  end)
end)
