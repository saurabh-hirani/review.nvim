local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0
if is_not_a_directory then
  vim.fn.system({ "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir })
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

-- Isolate review.nvim storage from the user's real data during tests. A fresh
-- temp dir per test run keeps specs from polluting each other or ~/.local.
vim.env.REVIEW_NVIM_DATA_DIR = vim.fn.tempname() .. "-review-test"

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
