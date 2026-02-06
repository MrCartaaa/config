-- ~/.config/nvim/lua/plugins/treesitter.lua
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "lua",
      "vim",
      "vimdoc",
      "query",
      "python",
      "javascript",
      "html",
      "rust",
    },
    sync_install = false,
    auto_install = true,
    ignore_install = {},
    modules = {}, -- can be removed entirely – it’s ignored anyway
    highlight = { enable = true },
    indent = { enable = true },
  },
}
