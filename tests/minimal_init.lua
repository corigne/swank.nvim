-- Minimal Neovim init for running swank.nvim tests via plenary.nvim.
-- Adds the plugin itself and plenary to the runtime path.
-- plenary is expected at one of the standard lazy/packpath locations.

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))

-- Find plenary — check common plugin manager paths in order
local plenary_candidates = {
  vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim",
  vim.fn.stdpath("data") .. "/plugged/plenary.nvim",
}

local found = false
for _, p in ipairs(plenary_candidates) do
  if vim.fn.isdirectory(p) == 1 then
    vim.opt.rtp:append(p)
    found = true
    break
  end
end

if not found then
  error("plenary.nvim not found — install it or add it to one of: "
    .. table.concat(plenary_candidates, ", "))
end
