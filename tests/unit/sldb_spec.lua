-- tests/unit/sldb_spec.lua — SLDB buffer content rendering

local sldb = require("swank.ui.sldb")

-- Helper: set module state and call build_content
local function build(state_overrides)
  local s = sldb._state
  s.level     = state_overrides.level     or 1
  s.condition = state_overrides.condition or { "Unknown error", "" }
  s.restarts  = state_overrides.restarts  or {}
  s.frames    = state_overrides.frames    or {}
  s.thread    = state_overrides.thread    or 1
  return sldb._build_content()
end

describe("sldb._build_content", function()
  it("includes the SLDB level in winbar", function()
    local _, _, winbar = build({ level = 3 })
    assert.is_true(winbar:find("3") ~= nil, "expected level 3 to appear in winbar")
  end)

  it("includes condition description", function()
    local lines, _ = build({ condition = { "division by zero", "DIVISION-BY-ZERO" } })
    local text = table.concat(lines, "\n")
    assert.is_true(text:find("division by zero") ~= nil)
  end)

  it("includes condition type when different from description", function()
    local lines, _ = build({ condition = { "some error", "MY-ERROR-TYPE" } })
    local text = table.concat(lines, "\n")
    assert.is_true(text:find("MY-ERROR-TYPE", 1, true) ~= nil)
  end)

  it("omits type line when type equals description", function()
    local lines, _ = build({ condition = { "same", "same" } })
    local occurrences = 0
    for _, l in ipairs(lines) do
      if l:find("same") then occurrences = occurrences + 1 end
    end
    -- should only appear once (description), not twice
    assert.equals(1, occurrences)
  end)

  it("renders restarts with index, name and description", function()
    local lines, meta = build({
      restarts = {
        { "ABORT",           "Abort to REPL" },
        { "CONTINUE",        "Continue execution" },
        { "RETRY-EXPANSION", "Retry macro expansion" },
      }
    })
    local text = table.concat(lines, "\n")
    assert.is_true(text:find("%[0%]") ~= nil)
    assert.is_true(text:find("ABORT") ~= nil)
    assert.is_true(text:find("%[1%]") ~= nil)
    assert.is_true(text:find("CONTINUE") ~= nil)
    assert.is_true(text:find("%[2%]") ~= nil)
    assert.equals(3, #meta.restart_lines)
  end)

  it("restart_lines are 1-indexed line numbers pointing to restart entries", function()
    local lines, meta = build({
      restarts = { { "R1", "desc one" }, { "R2", "desc two" } }
    })
    for _, lnum in ipairs(meta.restart_lines) do
      assert.is_true(lnum >= 1 and lnum <= #lines)
      assert.is_true(lines[lnum]:find("R") ~= nil)
    end
  end)

  it("renders backtrace frames", function()
    local lines, meta = build({
      frames = {
        { 0, "(/ 1 0)" },
        { 1, "SB-KERNEL::INTEGER-DIVIDE" },
      }
    })
    local text = table.concat(lines, "\n")
    assert.is_true(text:find("%(/ 1 0%)") ~= nil)
    assert.is_true(text:find("SB%-KERNEL") ~= nil)
    assert.equals(2, #meta.frame_lines)
  end)

  it("handles empty restarts and frames gracefully", function()
    assert.has_no_error(function()
      local lines, meta = build({ restarts = {}, frames = {} })
      assert.is_true(#lines > 0)
      assert.same({}, meta.restart_lines)
      assert.same({}, meta.frame_lines)
    end)
  end)

  it("includes a footer with keybinding hints in statusline", function()
    local _, _, _, statusline = build({})
    assert.is_true(statusline:find("abort") ~= nil or statusline:find("quit") ~= nil)
  end)
end)
