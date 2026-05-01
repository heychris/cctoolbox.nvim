-- Headless Neovim bootstrap for plenary test runner
local data_path = vim.fn.stdpath("data")

-- Add plenary to rtp (installed via lazy.nvim)
vim.opt.rtp:append(data_path .. "/lazy/plenary.nvim")

-- Add nvim config root so require("cctoolbox.*") resolves
vim.opt.rtp:append(vim.fn.expand("~/.config/nvim"))
