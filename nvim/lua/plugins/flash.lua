-- ~/.config/nvim/lua/plugins/flash.lua
return {
  "folke/flash.nvim",
  event = "VeryLazy",
  opts = {
    -- Enable flash during regular / and ? search
    modes = {
      search = {
        enabled = true, -- ← this is the key line
      },
      char = {
        enabled = true,
        multi_line = true,
        jump_labels = true,
      },
      treesitter = {
        labels = "abcdefghijklmnopqrstuvwxyz",
      },
    },
    label = {
      rainbow = {
        enabled = true,
      },
    },
    highlight = {
      backdrop = true,
    },
  },
  keys = {
    -- Core flash jumps (keep these)
    {
      "s",
      mode = { "n", "x", "o" },
      function()
        require("flash").jump()
      end,
      desc = "Flash",
    },
    {
      "S",
      mode = { "n", "x", "o" },
      function()
        require("flash").treesitter()
      end,
      desc = "Flash Treesitter",
    },
    {
      "r",
      mode = "o",
      function()
        require("flash").remote()
      end,
      desc = "Remote Flash",
    },
    {
      "R",
      mode = { "o", "x" },
      function()
        require("flash").treesitter_search()
      end,
      desc = "Treesitter Search",
    },

    -- Optional: toggle flash during search (useful if you sometimes want to disable labels)
    {
      "<c-s>",
      mode = { "c" },
      function()
        require("flash").toggle()
      end,
      desc = "Toggle Flash Search",
    },
  },
}
