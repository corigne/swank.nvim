-- tests/unit/client_eval_interactive_spec.lua
-- Test client.eval_interactive prompting and rex flow

local client = require("swank.client")

describe("client.eval_interactive", function()
  local orig_ui_input, orig_rex, orig_show_input, orig_show_result
  before_each(function()
    client._test_reset()
    orig_ui_input = vim.ui.input
    orig_rex = client.rex
    orig_show_input = require("swank.ui.repl").show_input
    orig_show_result = require("swank.ui.repl").show_result
  end)
  after_each(function()
    vim.ui.input = orig_ui_input
    client.rex = orig_rex
    require("swank.ui.repl").show_input = orig_show_input
    require("swank.ui.repl").show_result = orig_show_result
    client._test_reset()
  end)

  it("prompts and sends rex when user inputs text", function()
    local seen_input
    require("swank.ui.repl").show_input = function(s) seen_input = s end
    local seen_result
    require("swank.ui.repl").show_result = function(result) seen_result = result end

    vim.ui.input = function(opts, cb) cb("(+ 1 2)") end

    client.rex = function(form, cb)
      assert.equals("swank:eval-and-grab-output", form[1])
      assert.equals("(+ 1 2)", form[2])
      cb({ ":ok", "42" })
    end

    client.eval_interactive()

    assert.equals("(+ 1 2)", seen_input)
    assert.equals(":ok", seen_result[1])
  end)
end)
