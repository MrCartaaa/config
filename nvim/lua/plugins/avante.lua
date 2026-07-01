-- ~/.config/nvim/lua/plugins/avante.lua

return {
  {
    "yetone/avante.nvim",
    build = "make",
    event = "VeryLazy",
    version = false,

    opts = {
      provider = "custom",

      providers = {
        custom = {
          __inherited_from = "openai",
          api_key_name = "",   -- not needed for local
          endpoint = "http://192.168.2.15:8080/v1",
          model = "unsloth_Qwen3-Coder-Next-GGUF_Qwen3-Coder-Next-UD-Q4_K_S",
        },
      },
    },

    keys = {
      { "<C-.>", "<cmd>AvanteToggle<cr>", desc = "Avante Toggle", mode = { "n", "t" } },
    },

    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
    },
  },
}
