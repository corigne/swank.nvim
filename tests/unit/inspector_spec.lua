-- tests/unit/inspector_spec.lua — inspector content rendering

local inspector = require("swank.ui.inspector")

describe("inspector._render_content", function()
  local render = inspector._render_content

  it("returns empty lists for non-table input", function()
    local lines, parts = render(nil)
    assert.same({}, lines)
    assert.same({}, parts)
    lines, parts = render("string")
    assert.same({}, lines)
    assert.same({}, parts)
  end)

  it("returns empty lists for empty content", function()
    local lines, parts = render({})
    assert.same({}, lines)
    assert.same({}, parts)
  end)

  it("renders plain string content", function()
    local lines, parts = render({ "hello world" })
    assert.is_true(#lines >= 1)
    assert.is_true(lines[1]:find("hello world") ~= nil)
    assert.same({}, parts)
  end)

  it("splits embedded newlines into separate lines", function()
    local lines, _ = render({ "line one\nline two\nline three" })
    assert.is_true(#lines >= 3)
    assert.equals("line one", lines[1])
    assert.equals("line two", lines[2])
    assert.equals("line three", lines[3])
  end)

  it("renders a :value part on its own line with indent", function()
    local content = { { ":value", "42", 0 } }
    local lines, parts = render(content)
    -- The part should occupy its own line
    local found_line = nil
    for i, l in ipairs(lines) do
      if l:find("42") then found_line = i; break end
    end
    assert.is_not_nil(found_line, "expected to find '42' in a line")
    assert.is_not_nil(parts[found_line], "expected a part entry for that line")
    assert.equals("value", parts[found_line].kind)
    assert.equals("42",    parts[found_line].text)
    assert.equals(0,       parts[found_line].index)
  end)

  it("renders an :action part with kind='action'", function()
    local content = { { ":action", "inspect-next", 1 } }
    local lines, parts = render(content)
    local found_line = nil
    for i, l in ipairs(lines) do
      if l:find("inspect-next", 1, true) then found_line = i; break end
    end
    assert.is_not_nil(found_line)
    assert.equals("action", parts[found_line].kind)
    assert.equals(1,        parts[found_line].index)
  end)

  it("handles mixed strings and parts", function()
    local content = {
      "Description: ",
      { ":value", "some-object", 0 },
      "More text\nand more",
      { ":action", "do-something", 1 },
    }
    local lines, parts = render(content)
    -- At minimum should have lines for each part plus the text
    assert.is_true(#lines >= 2)
    local value_lines  = {}
    local action_lines = {}
    for i, p in pairs(parts) do
      if p.kind == "value"  then table.insert(value_lines,  i) end
      if p.kind == "action" then table.insert(action_lines, i) end
    end
    assert.equals(1, #value_lines)
    assert.equals(1, #action_lines)
  end)

  it("ignores unknown tagged items", function()
    local content = { { ":unknown-tag", "data", 99 }, "plain text" }
    assert.has_no_error(function()
      local lines, parts = render(content)
      assert.same({}, parts)
      -- plain text should still be rendered
      local has_text = false
      for _, l in ipairs(lines) do
        if l:find("plain text") then has_text = true; break end
      end
      assert.is_true(has_text)
    end)
  end)

  it("assigns correct 0-based part indices", function()
    local content = {
      { ":value", "first",  0 },
      { ":value", "second", 1 },
      { ":value", "third",  2 },
    }
    local _, parts = render(content)
    local indices = {}
    for _, p in pairs(parts) do table.insert(indices, p.index) end
    table.sort(indices)
    assert.same({ 0, 1, 2 }, indices)
  end)
end)
