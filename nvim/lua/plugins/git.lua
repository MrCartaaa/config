return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufNewFile" },

  opts = {
    -- Show blame inline
    current_line_blame = true,
    current_line_blame_opts = {
      delay = 0,
      virt_text_pos = "eol",
    },

    -- Git signs in the sign column
    signs = {
      add = {
        text = "+",
        hl = "GitSignsAdd",
        numhl = "GitSignsAddNr",
        linehl = "GitSignsAddLn",
      },
      change = {
        text = "~",
        hl = "GitSignsChange",
        numhl = "GitSignsChangeNr",
        linehl = "GitSignsChangeLn",
      },
      delete = {
        text = "_",
        hl = "GitSignsDelete",
        numhl = "GitSignsDeleteNr",
        linehl = "GitSignsDeleteLn",
      },
      topdelete = {
        text = "‾",
        hl = "GitSignsDelete",
      },
      changedelete = {
        text = "~",
        hl = "GitSignsChange",
      },
    },

    -- Attach keymaps per buffer
    on_attach = function(bufnr)
      local gs = package.loaded.gitsigns

      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
      end

      -- Hunk navigation
      map("n", "]c", function()
        if vim.wo.diff then
          vim.cmd.normal({ "]c", bang = true })
        else
          gs.nav_hunk("next")
        end
      end, "Next Git hunk")

      map("n", "[c", function()
        if vim.wo.diff then
          vim.cmd.normal({ "[c", bang = true })
        else
          gs.nav_hunk("prev")
        end
      end, "Previous Git hunk")

      -- Toggle showing git changes / deletions
      map("n", "<leader>gd", gs.toggle_deleted, "Toggle deleted lines")
    end,
  },

  config = function(_, opts)
    require("gitsigns").setup(opts)

    -- Always show deleted lines (replacement for deprecated show_deleted)
    require("gitsigns").preview_hunk_inline()

    -- Apply highlight colors AFTER colorscheme loads
    local apply_gitsigns_colors = function()
      -- Added (green)
      vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = "#4ade80", bold = true })
      vim.api.nvim_set_hl(0, "GitSignsAddNr", { fg = "#4ade80" })
      vim.api.nvim_set_hl(0, "GitSignsAddLn", { bg = "#0f2a1a" })

      -- Changed (blue)
      vim.api.nvim_set_hl(0, "GitSignsChange", { fg = "#4da6ff", bold = true })
      vim.api.nvim_set_hl(0, "GitSignsChangeNr", { fg = "#4da6ff" })
      vim.api.nvim_set_hl(0, "GitSignsChangeLn", { bg = "#0d1f33" })

      -- Deleted (red)
      vim.api.nvim_set_hl(0, "GitSignsDelete", { fg = "#ff4d4d", bold = true })
      vim.api.nvim_set_hl(0, "GitSignsDeleteNr", { fg = "#ff4d4d" })
      vim.api.nvim_set_hl(0, "GitSignsDeleteLn", { bg = "#2a0f0f" })
    end

    -- Apply immediately
    apply_gitsigns_colors()

    -- Re-apply on colorscheme change (LazyVim-safe)
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = apply_gitsigns_colors,
    })
  end,
}
