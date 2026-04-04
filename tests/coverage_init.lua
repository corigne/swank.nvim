-- Coverage init for swank.nvim tests.
-- Extends package.path with the local luarocks 5.1 tree so Neovim's LuaJIT
-- can find luacov, then starts collection before plenary runs the suite.
-- Based on minimal_init.lua — keep in sync with any changes there.

-- Extend package.path with luarocks Lua 5.1 tree (luacov lives here)
local rocks = vim.fn.expand("~/.luarocks/share/lua/5.1")
package.path = package.path
  .. ";" .. rocks .. "/?.lua"
  .. ";" .. rocks .. "/?/init.lua"

-- Plugin root
vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))

-- Plenary
local plenary_candidates = {
  vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim",
  vim.fn.stdpath("data") .. "/plugged/plenary.nvim",
}

for _, p in ipairs(plenary_candidates) do
  if vim.fn.isdirectory(p) == 1 then
    vim.opt.rtp:append(p)
    break
  end
end

-- Start luacov before any plugin code is loaded.
-- Save stats on exit so qa! triggers the write reliably.
require("luacov")
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    require("luacov.runner").save_stats()
  end,
})
