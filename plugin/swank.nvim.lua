-- swank.nvim entry point (lazy-loadable)
-- This file is intentionally minimal; real setup happens in lua/swank/init.lua
if vim.g.loaded_swank_nvim then
  return
end
vim.g.loaded_swank_nvim = true

-- Register filetype autocommand to attach keymaps when editing Lisp files
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "lisp", "cl" },
  callback = function(ev)
    require("swank").attach(ev.buf)
  end,
  group = vim.api.nvim_create_augroup("SwankNvim", { clear = true }),
})
