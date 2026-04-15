-- swank.nvim — nvim-cmp completion source
-- Provides symbol completions via swank:completions with lazy
-- swank:describe-symbol documentation via resolve().
--
-- Register in your nvim-cmp config:
--   require("swank.sources.nvim_cmp")   -- auto-registers on load
--
-- Then add to your sources:
--   sources = cmp.config.sources({ { name = "swank" }, { name = "buffer" } })
--
-- Or per-filetype:
--   cmp.setup.filetype({ "lisp", "commonlisp" }, {
--     sources = cmp.config.sources({ { name = "swank" }, { name = "buffer" } }),
--   })

local has_cmp, cmp = pcall(require, "cmp")
if not has_cmp then return end

local Source = {}

function Source.new()
  return setmetatable({}, { __index = Source })
end

function Source:is_available()
  local ok, client = pcall(require, "swank.client")
  if not (ok and client.is_connected()) then return false end
  -- Yield to the LSP when one is attached; it provides completions natively.
  local bufnr = vim.api.nvim_get_current_buf()
  return #vim.lsp.get_clients({ bufnr = bufnr }) == 0
end

function Source:get_keyword_pattern()
  -- CL symbols: alphanumeric plus common special characters and package prefix
  return [[\%([a-zA-Z0-9\-+*/<=>\!?:%@$^&~#|.]\+\)]]
end

function Source:get_trigger_characters()
  return { ":" }
end

function Source:complete(params, callback)
  local ok, client = pcall(require, "swank.client")
  if not ok or not client.is_connected() then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local line_before = params.context.cursor_before_line or ""
  local prefix = line_before:match("[%w%-%+%*%/%<%>%=%!%?%:%&%#%@%$%%^~%.]+$") or ""
  if prefix == "" then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local pkg = client.get_package and client.get_package() or "COMMON-LISP-USER"
  client.rex({ "swank:completions", prefix, pkg }, function(result)
    if type(result) ~= "table" or result[1] ~= ":ok" then
      callback({ items = {}, isIncomplete = false })
      return
    end
    local payload = result[2]
    local list = (type(payload) == "table" and payload[1]) or {}
    local items = {}
    for _, c in ipairs(list) do
      if type(c) == "string" then
        table.insert(items, {
          label      = c,
          kind       = cmp.lsp.CompletionItemKind.Function,
          insertText = c,
          filterText = c,
        })
      end
    end
    callback({ items = items, isIncomplete = false })
  end)
end

--- Lazily enrich a completion item with swank:describe-symbol output.
--- nvim-cmp calls this when the user dwells on an item in the menu.
function Source:resolve(completion_item, callback)
  local ok, client = pcall(require, "swank.client")
  local label = completion_item.label
  if not ok or not client.is_connected() or not label or label == "" then
    callback(completion_item)
    return
  end
  local raw = label
  local s = raw and tostring(raw) or ""
  s = s:gsub("^#'", ""):gsub("^['`%,]+", ""):match("^%s*(.-)%s*$") or s
  if client._is_symbol_like(s) then
    client.silent_rex({ "swank:describe-symbol", s }, function(result)
      if type(result) == "table" and result[1] == ":ok" and result[2] then
        local text = tostring(result[2]):gsub("\r", ""):gsub("%s+$", "")
        completion_item.documentation = {
          kind  = cmp.lsp.MarkupKind.Markdown,
          value = "```\n" .. text .. "\n```",
        }
      end
      callback(completion_item)
    end)
  else
    callback(completion_item)
  end
end

cmp.register_source("swank", Source.new())

return Source
