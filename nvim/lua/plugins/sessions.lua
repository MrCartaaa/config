return {
  {
    "Shatur/neovim-session-manager",
    lazy = false,
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local config = require("session_manager.config")
      require("session_manager").setup({
        -- Store sessions in nvim data dir
        sessions_dir = vim.fn.stdpath("data") .. "/sessions",

        -- NO auto-loading: plain `nvim` always starts clean dashboard
        autoload_mode = config.AutoloadMode.Disabled,

        -- Auto-save current session on quit/project switch
        autosave_last_session = true,
        autosave_only_loaded_session = false,
        autosave_ignore_not_normal = true, -- skip if only special buffers (help, etc.)

        -- Don't create sessions in home/tmp dirs
        autosave_ignore_dirs = { vim.fn.expand("~"), "/tmp" },
      })
    end,
  },
}
