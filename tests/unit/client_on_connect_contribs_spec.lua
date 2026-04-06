-- tests/unit/client_on_connect_contribs_spec.lua
-- Ensure M._on_connect loads contribs and calls swank:swank-require then set-package

local client = require("swank.client")

describe("client._on_connect with contribs", function()
  local orig_rex, orig_notify, orig_config
  before_each(function()
    client._test_reset()
    orig_rex = client.rex
    orig_notify = vim.notify
    orig_config = require("swank").config
  end)
  after_each(function()
    client.rex = orig_rex
    vim.notify = orig_notify
    require("swank").config = orig_config
    client._test_reset()
  end)

  it("calls swank:swank-require and then set-package when contribs present", function()
    local swank = require("swank")
    swank.config = { contribs = { ":swank-repl" } }

    local calls = {}
    client.rex = function(form, cb)
      table.insert(calls, form[1])
      -- simulate success immediately
      cb({ ":ok", true })
    end

    client._on_connect()

    local saw_require, saw_set = false, false
    for _, c in ipairs(calls) do
      local s = tostring(c)
      if s == "swank:swank-require" then saw_require = true end
      if s == "swank:set-package" then saw_set = true end
    end

    assert.is_true(saw_require)
    assert.is_true(saw_set)
  end)
end)
