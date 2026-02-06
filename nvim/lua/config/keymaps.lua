-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--

---------
-- GIT --
---------

local gs = require("gitsigns")

-- Stage current hunk (normal mode)
vim.keymap.set("n", "<leader>ga", gs.stage_hunk, {
  desc = "Stage hunk",
})

-- Stage selection
vim.keymap.set("v", "<leader>gs", function()
  require("gitsigns").stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
end, { desc = "Stage selection" })

-- Undo staged hunk
vim.keymap.set("n", "<leader>gr", gs.reset_hunk, {
  desc = "Undo stage hunk",
})

-- Stage entire buffer
vim.keymap.set("n", "<leader>gA", gs.stage_buffer, {
  desc = "Stage buffer",
})

-- Unstage / reset hunk (modern replacement)
vim.keymap.set("n", "<leader>gu", gs.reset_hunk, {
  desc = "Unstage / reset hunk",
})

-- Unstage / reset selection
vim.keymap.set("v", "<leader>gu", function()
  gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
end, { desc = "Unstage / reset selection" })

vim.keymap.set("n", "<leader>gp", gs.preview_hunk, {
  desc = "Preview hunk",
})

-------------
-- HARPOON --
-------------

local harpoon = require("harpoon")

vim.keymap.set("n", "<leader>hr", function()
  harpoon:list():remove()
end, { desc = "Harpoon remove file" })

vim.keymap.set("n", "<leader>hR", function()
  harpoon:list():clear()
end, { desc = "Harpoon remove ALL files" })

-- Toggle Harpoon quick menu
vim.keymap.set("n", "<leader>hh", function()
  harpoon.ui:toggle_quick_menu(harpoon:list())
end, { desc = "Harpoon menu" })

--------------
-- HARDTIME --
--------------

-- 🔒 ABSOLUTE ARROW KEY DEATH
for _, key in ipairs({ "<Up>", "<Down>", "<Left>", "<Right>" }) do
  vim.keymap.set({ "n", "i", "v" }, key, "<Nop>", { silent = true })
end

-- ❌ Disable mouse entirely
vim.opt.mouse = ""

-- ⚔️ Force better vertical movement
vim.keymap.set("n", "j", "gj")
vim.keymap.set("n", "k", "gk")

-- 🚀 Encourage real motions
vim.keymap.set("n", "H", "^") -- line start
vim.keymap.set("n", "L", "$") -- line end

-- 🧠 Make search unavoidable
vim.keymap.set("n", "<leader>/", "/")
vim.keymap.set("n", "<leader>?", "?")

-- 🛑 Optional: disable holding keys in insert mode
vim.keymap.set("i", "<C-h>", "<Nop>")
vim.keymap.set("i", "<C-j>", "<Nop>")
vim.keymap.set("i", "<C-k>", "<Nop>")
vim.keymap.set("i", "<C-l>", "<Nop>")

------------
-- CLIPPY --
------------

-- Show full diagnostic (Clippy, rust-analyzer, etc.) in a floating window
vim.keymap.set("n", "<leader>cd", function()
  vim.diagnostic.open_float(nil, {
    focus = true,
    border = "rounded",
    source = "always",
  })
end, { desc = "Show diagnostic details" })

--------------
-- TERMINAL --
--------------

-- Toggle terminal with Ctrl+/ (sends as Ctrl+_ in most terminals)
vim.keymap.set({ "n", "t" }, "<C-/>", function()
  Snacks.terminal()
end, { desc = "Toggle terminal" })

vim.keymap.set({ "n", "t" }, "<C-_>", function()
  Snacks.terminal()
end, { desc = "Toggle terminal" })
