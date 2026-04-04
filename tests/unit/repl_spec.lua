-- tests/unit/repl_spec.lua — REPL output formatting

local repl = require("swank.ui.repl")

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
