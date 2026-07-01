-- ~/.config/nvim/lua/plugins/todo-comments.lua

return {
  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      keywords = {
        FUTURE = {
          icon = "🧭",
          color = "warning",        -- changed to named color
          alt = { "FUTURE", "LATER", "ROADMAP", "PLAN" },
        },
        IMPORTANT = {
          icon = "‼️",
          color = "warning",        -- changed to named color
          alt = { "IMPORTANT" },
        },
        SAFETY = {
          icon = "🩺",
          color = "warning",        -- already good
          alt = { "SAFETY" },
        },
      },

      -- Extra safety
      colors = {
        error = { "DiagnosticError", "ErrorMsg", "#DC2626" },
        warning = { "DiagnosticWarn", "WarningMsg", "#FBBF24" },
        info = { "DiagnosticInfo", "#2563EB" },
        hint = { "DiagnosticHint", "#10B981" },
        default = { "Identifier", "#7C3AED" },
      },
    },
  },
}
