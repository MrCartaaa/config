return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      default_component_configs = {
        icon = {
          folder_closed = "",
          folder_open = "",
          folder_empty = "",
          -- purple folder icons
          highlight = "NeoTreeFolderIcon",
        },
        name = {
          -- purple filenames
          highlight = "NeoTreeFileName",
        },
      },
    },
    config = function(_, opts)
      require("neo-tree").setup(opts)

      -- 💜 define your purple
      local purple = "#BF93F9" -- change this shade if you like

      -- 💜 folder & file accents
      vim.api.nvim_set_hl(0, "NeoTreeFolderIcon", { fg = purple })
      vim.api.nvim_set_hl(0, "NeoTreeFileName", { fg = purple })

      -- 💜 git symbols
      vim.api.nvim_set_hl(0, "NeoTreeGitAdded", { fg = purple })
      vim.api.nvim_set_hl(0, "NeoTreeGitModified", { fg = purple })

      -- 💜 indent markers
      vim.api.nvim_set_hl(0, "NeoTreeIndentMarker", { fg = purple })

      -- 💜 title / bar color
      vim.api.nvim_set_hl(0, "NeoTreeTitleBar", { fg = "#111111", bg = purple })
    end,
  },
}
