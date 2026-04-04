-- swank.nvim — SLDB debugger floating window
-- TODO: Phase 3

local M = {}

function M.open(msg)
  -- msg = (:debug thread level condition restarts frames conts)
  vim.notify("swank.nvim: SLDB not yet implemented (Phase 3)", vim.log.levels.INFO)
end

function M.close()
end

return M
