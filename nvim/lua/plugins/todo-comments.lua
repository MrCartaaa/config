return {
  {
    "folke/todo-comments.nvim",
    opts = {
      keywords = {
        FUTURE = {
          icon = "🧭", -- Choose any icon you like (or "S " for something simple)
          color = "#FF0",
          alt = { "FUTURE", "LATER", "ROADMAP", "PLAN" }, -- Optional: additional aliases that map to SAFETY
          -- sign = false,  -- Optional: disable sign if you don't want it
        },
        IMPORTANT = {
          icon = "‼️", -- Choose any icon you like (or "S " for something simple)
          color = "#B388FF",
          alt = { "FUTURE", "LATER", "ROADMAP", "PLAN" }, -- Optional: additional aliases that map to SAFETY
          -- sign = false,  -- Optional: disable sign if you don't want it
        },
        SAFETY = {
          icon = "🩺", -- Choose any icon you like (or "S " for something simple)
          color = "warning", -- Uses a named color: "error", "warning", "info", "hint" (or a hex like "#FF0000")
          alt = { "SAFETY" }, -- Optional: additional aliases that map to SAFETY
          -- sign = false,  -- Optional: disable sign if you don't want it
        },
      },
    },
  },
}
