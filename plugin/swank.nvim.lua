-- swank.nvim entry point (lazy-loadable)
-- This file is intentionally minimal; real setup happens in lua/swank/init.lua
if vim.g.loaded_swank_nvim then
  return
end
vim.g.loaded_swank_nvim = true

local augroup = vim.api.nvim_create_augroup("SwankNvim", { clear = true })

-- Attach keymaps and optionally autostart on Lisp buffers
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "lisp", "cl" },
  callback = function(ev)
    require("swank").attach(ev.buf)
  end,
  group = augroup,
})

-- Autodoc: show arglist for innermost operator while typing
vim.api.nvim_create_autocmd({ "CursorMovedI", "CursorHoldI" }, {
  pattern = { "*.lisp", "*.cl" },
  callback = function()
    require("swank.client").autodoc()
  end,
  group = augroup,
})
