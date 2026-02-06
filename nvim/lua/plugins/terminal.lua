-- ~/.config/nvim/lua/plugins/terminal.lua
return {
  {
    "LazyVim/LazyVim",
    enable = false,
    opts = function(_, opts)
      -- Terminal mode keymap: jk -> Normal mode
      vim.keymap.set("t", "jk", [[<C-\><C-n>]], {
        desc = "Exit terminal mode (jk)",
        silent = true,
        noremap = true,
      })

      -- Make terminal open ~99% height + clean UI
      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*",
        callback = function()
          -- Move terminal to bottom
          vim.cmd("wincmd J")

          -- Lock the height so splits don't fight it
          vim.opt_local.winfixheight = true

          -- Start in insert mode
          vim.cmd("startinsert")

          -- Sane defaults
          vim.opt_local.number = false
          vim.opt_local.relativenumber = false
          vim.opt_local.signcolumn = "no"
          vim.opt_local.cursorline = false
          vim.opt_local.wrap = false
        end,
      })

      -- Truecolor
      vim.opt.termguicolors = true

      -- Optional float styling
      vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
      vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#7aa2f7", bg = "none" })

      return opts
    end,
  },
}
