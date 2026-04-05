-- swank.nvim — blink.cmp completion source
-- Provides symbol completions via swank:completions.
-- Supports resolve() for lazy swank:describe-symbol documentation.
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

  -- blink context: ctx.line is the full line, ctx.cursor is {row, col}
  local line_before = ctx.line and ctx.line:sub(1, ctx.cursor and ctx.cursor[2] or 0) or ""
  local prefix = symbol_prefix(line_before)
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

--- Lazily enrich a completion item with swank:describe-symbol output.
--- blink.cmp calls this when the user dwells on an item in the menu.
function M:resolve(item, callback)
  local ok, client = pcall(require, "swank.client")
  if not ok or not client.is_connected() or not item.label or item.label == "" then
    callback(item)
    return
  end
  client.rex({ "swank:describe-symbol", item.label }, function(result)
    if type(result) == "table" and result[1] == ":ok" and result[2] then
      local text = tostring(result[2]):gsub("\r", ""):gsub("%s+$", "")
      item.documentation = { kind = "markdown", value = "```\n" .. text .. "\n```" }
    end
    callback(item)
  end)
end

return M
