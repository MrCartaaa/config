-- return {
--   {
--     "folke/tokyonight.nvim",
--     priority = 1000,   -- load before other plugins
--     opts = {
--       style = "storm", -- "night" (blackest), "storm" (slightly softer)
--       transparent = false,
--       terminal_colors = true,
--       styles = {
--         comments = { italic = true },
--         keywords = { italic = false },
--       },
--     },
--   },
--   {
--     "LazyVim/LazyVim",
--     opts = {
--       colorscheme = "tokyonight-storm",
--     },
--   },
-- }
return {
  -- Kanagawa theme
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,

    opts = {
      compile = false,
      undercurl = true,
      commentStyle = { italic = true },
      functionStyle = {},
      keywordStyle = { italic = false },
      statementStyle = { bold = true },
      typeStyle = {},
      transparent = true,
      dimInactive = false,
      terminalColors = true,

      theme = "dragon",

      background = {
        dark = "dragon",
        light = "lotus",
      },

      overrides = function(colors)
        local theme = colors.theme

        return {
          -- Transparent LazyVim-friendly UI
          Normal = { bg = "NONE" },
          NormalFloat = { bg = "NONE" },
          FloatBorder = { bg = "NONE", fg = theme.ui.float.fg_border },
          FloatTitle = { bg = "NONE" },

          -- Telescope
          TelescopeNormal = { bg = "NONE" },
          TelescopeBorder = { bg = "NONE", fg = theme.ui.float.fg_border },
          TelescopePromptNormal = { bg = "NONE" },
          TelescopeResultsNormal = { bg = "NONE" },
          TelescopePreviewNormal = { bg = "NONE" },

          -- Lazy.nvim
          LazyNormal = { bg = "NONE" },

          -- Which-key
          WhichKeyFloat = { bg = "NONE" },

          -- Diagnostics
          DiagnosticVirtualTextError = { bg = "NONE" },
          DiagnosticVirtualTextWarn = { bg = "NONE" },
          DiagnosticVirtualTextInfo = { bg = "NONE" },
          DiagnosticVirtualTextHint = { bg = "NONE" },
        }
      end,
    },
  },

  -- Tell LazyVim to use Kanagawa
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "kanagawa-dragon",
    },
  },
}

-- return {
--   -- { "nyoom-engineering/oxocarbon.nvim" },
--   -- {
--   --   "LazyVim/LazyVim",
--   --   opts = {
--   --     colorscheme = "oxocarbon",
--   --   },
--   -- },
-- }
