-- swank.nvim — blink.cmp completion source
-- Calls swank:fuzzy-completions for symbol completion in Lisp buffers.

---@type blink.cmp.Source
local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:get_trigger_characters()
  return { ":" }
end

function source:get_completions(ctx, callback)
  local client = require("swank.client")
  if not client.is_connected() then
    callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
    return
  end

  local prefix = ctx.line:sub(1, ctx.cursor[2])
  -- Extract the symbol being typed (last word including package prefix)
  local sym = prefix:match("[%a%d%-%_%%%.%+%*%?%!%@%$%^%&%=%<%>%/%|~:]+$") or ""

  client.rex(
    { "swank:fuzzy-completions", sym, "COMMON-LISP-USER", ":limit", 50, ":time-limit-in-msec", 150 },
    function(result)
      if type(result) ~= "table" or result[1] ~= ":ok" then
        callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
        return
      end
      local completions = result[2] and result[2][1] or {}
      local items = {}
      for _, c in ipairs(completions) do
        -- fuzzy-completions returns (completion score flags docstring)
        if type(c) == "table" then
          table.insert(items, {
            label = tostring(c[1] or ""),
            documentation = c[4] and { kind = "markdown", value = tostring(c[4]) } or nil,
            kind = require("blink.cmp.types").CompletionItemKind.Function,
          })
        end
      end
      callback({
        is_incomplete_forward = false,
        is_incomplete_backward = false,
        items = items,
      })
    end
  )
end

return source
