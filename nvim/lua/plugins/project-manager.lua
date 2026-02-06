return {
  {
    "ahmedkhalf/project.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-telescope/telescope.nvim" },
    opts = {
      manual_mode = false,
      detection_methods = { "pattern" },
      patterns = { ".git", "Cargo.toml", "pyproject.toml", "package.json", "pubspec.yaml", "Makefile" },
      exclude_dirs = {
        "**/node_modules",
        "**/target",
        "**/__pycache__",
        "**/.pytest_cache",
        "**/.venv",
        "**/venv",
        "**/env",
        "**/.tox",
        "**/.next",
        "**/build",
        "**/dist",
        "**/.cache",
        "**/coverage",
        "**/.dart_tool",
        "**/.flutter-plugins",
        "**/.packages",
        "**/vendor",
        "**/logs",
        "**/log",
        "**/tmp",
        "**/temp",
        "**/.angular",
        "**/.git/worktrees",
      },
      scope_chdir = "global",
      silent_chdir = true,
      show_hidden = false,
      datapath = vim.fn.stdpath("data"),

      callbacks = {
        on_project_changed = function(project_root)
          -- Only close buffers from the old project
          local old_root = vim.g.project_root or ""
          for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) then
              local buftype = vim.bo[bufnr].buftype
              local bufpath = vim.api.nvim_buf_get_name(bufnr)
              if buftype == "" and bufpath:sub(1, #old_root) == old_root then
                vim.api.nvim_buf_delete(bufnr, { force = true })
              end
            end
          end
          -- Update the current project root
          vim.g.project_root = project_root
        end,
      },
    },

    config = function(_, opts)
      local project = require("project_nvim")
      project.setup(opts)

      require("telescope").load_extension("projects")

      -- Optional: keymap to open projects
      vim.keymap.set("n", "<leader>fp", function()
        vim.cmd("Telescope projects")
      end, { desc = "Switch project" })
    end,
  },
}
