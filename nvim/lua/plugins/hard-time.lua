return {
  "m4xshen/hardtime.nvim",
  lazy = false,
  dependencies = {
    "MunifTanjim/nui.nvim",
  },
  opts = {
    -- 😈 Brutal timing
    max_time = 1000, -- ms window
    max_count = 4, -- allowed repeats
    allow_different_key = false,
    hint = true,
    notification = true,
    disable_mouse = true,

    -- ❌ Completely forbidden keys
    disabled_keys = {
      ["<Up>"] = { "n", "i", "v", "x" },
      ["<Down>"] = { "n", "i", "v", "x" },
      ["<Left>"] = { "n", "i", "v", "x" },
      ["<Right>"] = { "n", "i", "v", "x" },
      ["<PageUp>"] = { "n", "v" },
      ["<PageDown>"] = { "n", "v" },
    },

    -- ⚠️ Heavily restricted (spam punished)
    restricted_keys = {
      -- movement mashing
      ["h"] = { "n", "x" },
      ["j"] = { "n", "x" },
      ["k"] = { "n", "x" },
      ["l"] = { "n", "x" },

      -- vertical line jumps
      ["+"] = { "n" },
      ["-"] = { "n" },

      -- 🚫 gg / G abuse
      ["g"] = { "n" }, -- catches gg spam
      ["G"] = { "n" }, -- bottom-of-file jumps
    },
  },
}
