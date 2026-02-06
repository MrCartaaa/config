-- return {
--   {
--     "folke/tokyonight.nvim",
--     priority = 1000, -- load before other plugins
--     opts = {
--       style = "moon", -- "night" (blackest), "storm" (slightly softer)
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
--       colorscheme = "tokyonight-moon",
--     },
--   },
-- }

return {
  { "nyoom-engineering/oxocarbon.nvim" },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "oxocarbon",
    },
  },
}
