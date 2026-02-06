return {
  "stevearc/conform.nvim",
  opts = {
    formatters = {
      dos2unix = { command = "dos2unix", stdin = false, args = { "$FILENAME" } },
    },
    formatters_by_ft = {
      ["*"] = { "dos2unix" },
      html = { "dos2unix", "prettier" },
      htmlangular = { "dos2unix", "prettier" },
      lua = { "stylua" },
      python = { "isort", "black" },
      rust = { "rustfmt", lsp_format = "fallback" },
      javascript = { "prettier", stop_after_first = true },
      typescript = { "prettier" },
      scss = { "prettier" },
      sql = { "pg_format" },
    },
  },
}
