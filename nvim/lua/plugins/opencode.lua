return {
  "nickjvandyke/opencode.nvim",

  dependencies = {
    { "folke/snacks.nvim", opts = { input = {}, picker = {}, terminal = {} } },
  },

  keys = {
    {
      "<C-.>",
      function()
        local oc = require("opencode")
        oc.toggle()

        -- focus after the window is created
        vim.defer_fn(function()
          -- focus() exists in opencode.nvim; if it fails, we fallback below
          pcall(oc.focus)
        end, 100)
      end,
      mode = { "n", "t" },
      desc = "Opencode Toggle (focus)",
    },
  },

  config = function()
    vim.g.opencode_opts = {
      provider = { enabled = "snacks" },
    }
    vim.o.autoread = true
  end,
}
