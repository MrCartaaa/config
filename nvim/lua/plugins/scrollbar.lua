return {
  "petertriho/nvim-scrollbar",
  dependencies = {
    "lewis6991/gitsigns.nvim",
  },
  config = function()
    require("scrollbar").setup({
      show = true,
      handle = {
        color = "#1e1e1e",
      },
      marks = {
        GitAdd = { text = "+" },
        GitChange = { text = "~" },
        GitDelete = { text = "_" },
      },
    })

    require("scrollbar.handlers.gitsigns").setup()
  end,
}
