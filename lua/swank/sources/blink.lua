-- swank.nvim — blink.cmp completion source
-- Calls swank:fuzzy-completions for symbol completion in Lisp buffers.
-- Supports resolve() for lazy swank:describe-symbol documentation.

---@type blink.cmp.Source
local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:get_trigger_characters()
  return { ":" }
end

function source:enabled()
  local ok, client = pcall(require, "swank.client")
  if not (ok and client.is_connected()) then return false end
  -- Yield to the LSP when one is attached; it provides completions natively.
  local bufnr = vim.api.nvim_get_current_buf()
  return #vim.lsp.get_clients({ bufnr = bufnr }) == 0
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
            kind  = require("blink.cmp.types").CompletionItemKind.Function,
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

--- Lazily enrich a completion item with swank:describe-symbol output.
--- blink.cmp calls this when the user dwells on an item in the menu.
function source:resolve(item, callback)
  local client = require("swank.client")
  if not client.is_connected() or not item.label or item.label == "" then
    callback(item)
    return
  end
  local raw = item.label
  local s = raw and tostring(raw) or ""
  s = s:gsub("^#'", ""):gsub("^['`%,]+", ""):match("^%s*(.-)%s*$") or s
  if client._is_symbol_like(s) then
    client.silent_rex({ "swank:describe-symbol", s }, function(result)
      if type(result) == "table" and result[1] == ":ok" and result[2] then
        local text = tostring(result[2]):gsub("\r", ""):gsub("%s+$", "")
        item.documentation = { kind = "markdown", value = "```\n" .. text .. "\n```" }
      end
      callback(item)
    end)
  else
    callback(item)
  end
end

return source
