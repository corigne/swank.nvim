-- swank.nvim — blink.cmp completion source
-- Provides symbol completions via swank:completions.
-- Register in blink.cmp opts:
--   providers = { swank = { name = "Swank", module = "swank.blink_source" } }
--   per_filetype = { lisp = { "swank", "buffer" }, commonlisp = { "swank", "buffer" } }

local M = {}
M.__index = M

-- blink.cmp calls this to instantiate the source
function M.new()
  return setmetatable({}, M)
end

function M:enabled()
  local ok, client = pcall(require, "swank.client")
  return ok and client.is_connected()
end

function M:get_trigger_characters()
  return { ":", "-" }
end

-- Extract the Lisp symbol prefix ending at the cursor
local function symbol_prefix(line)
  -- CL symbols: letters, digits, -, +, *, /, <, >, =, !, ?, :, &, %, #, @, $, ^, ~, ., |, \
  return line:match("[%w%-%+%*%/%<%>%=%!%?%:%&%#%@%$%%^~%.]+$") or ""
end

function M:get_completions(ctx, callback)
  local ok, client = pcall(require, "swank.client")
  if not ok or not client.is_connected() then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local prefix = symbol_prefix(ctx.cursor_before_line)
  if prefix == "" then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local pkg = client.get_package()

  client.rex({ "swank:completions", prefix, pkg }, function(result)
    -- swank:completions returns (:ok ((comp1 comp2 ...) "longest-prefix"))
    if type(result) ~= "table" or result[1] ~= ":ok" then
      callback({ items = {}, isIncomplete = false })
      return
    end
    local payload = result[2]
    -- payload[1] = list of completion strings, payload[2] = longest-prefix string
    local list = (type(payload) == "table" and payload[1]) or {}
    if type(list) ~= "table" then
      callback({ items = {}, isIncomplete = false })
      return
    end
    local items = {}
    for _, c in ipairs(list) do
      if type(c) == "string" then
        table.insert(items, {
          label            = c,
          kind             = vim.lsp.protocol.CompletionItemKind.Function,
          insertText       = c,
          filterText       = c,
        })
      end
    end
    callback({ items = items, isIncomplete = false })
  end)
end

return M
