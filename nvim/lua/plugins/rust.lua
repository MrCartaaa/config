-- ~/.config/nvim/lua/plugins/rust.lua
return {
  -- dap (debugging)
  {
    "mfussenegger/nvim-dap",
    lazy = false,
    config = function()
      local dap_ok, dap = pcall(require, "dap")
      if not dap_ok then
        return
      end

      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = {
          command = os.getenv("HOME") .. "/.local/bin/codelldb",
          args = { "--port", "${port}" },
        },
      }

      dap.configurations.rust = {
        {
          name = "Debug",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,

          -- Only for debug sessions
          env = {
            MAE_TESTCONTAINERS = "1",
          },
        },
      }
    end,
  },

  -- dap ui
  {
    "rcarriga/nvim-dap-ui",
    dependencies = "mfussenegger/nvim-dap",
    config = function()
      local dapui = require("dapui")
      dapui.setup()

      local dap = require("dap")
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end
    end,
  },

  -- rustaceanvim + rust-analyzer
  {
    "mrcjkb/rustaceanvim",
    version = "*",
    lazy = false,
    ft = { "rust" },
    opts = {
      neotest = true,
      server = {
        cmd = { "/usr/bin/rust-analyzer" },
        default_settings = {
          ["rust-analyzer"] = {
            cargo = {
              allFeatures = true,
            },
            checkOnSave = true,
            check = {
              command = "check"
              -- command = "clippy",
              -- extraArgs = { "--all-targets", "--all-features", "--", "-D", "warnings" },
            },
            runnables = {
              extraEnv = {
                MAE_TESTCONTAINERS = "1",
              },
            },
            procMacro = { enable = true },
          },
        },
      },
    },
    config = function(_, opts)
      vim.g.rustaceanvim = opts
    end,
  },

  -- neotest
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      "mrcjkb/rustaceanvim",
      "mfussenegger/nvim-dap",
    },
    lazy = false,
    keys = {
      { "<leader>t", "", desc = "+test" },

      {
        "<leader>tr",
        function()
          require("neotest").run.run({ env = { MAE_TESTCONTAINERS = "1" } })
        end,
        desc = "Run Nearest (MAE_TESTCONTAINERS=1)",
      },

      {
        "<leader>tt",
        function()
          require("neotest").run.run({
            file = vim.fn.expand("%:p"),
            suite = false,
            env = { MAE_TESTCONTAINERS = "1" },
          })
        end,
        desc = "Run File (MAE_TESTCONTAINERS=1)",
      },

      {
        "<leader>tT",
        function()
          require("neotest").run.run({ suite = true, env = { MAE_TESTCONTAINERS = "1" } })
        end,
        desc = "Run Test Suite (MAE_TESTCONTAINERS=1)",
      },

      {
        "<leader>td",
        function()
          require("neotest").run.run({ strategy = "dap", env = { MAE_TESTCONTAINERS = "1" } })
        end,
        desc = "Debug Nearest (MAE_TESTCONTAINERS=1)",
      },

      {
        "<leader>ts",
        function()
          require("neotest").summary.toggle()
        end,
        desc = "Toggle Summary",
      },
      {
        "<leader>to",
        function()
          require("neotest").output.open({ enter = true })
        end,
        desc = "Show Output",
      },
    },
    opts = function()
      local adapters = {}
      local ok, rust_adapter = pcall(require, "rustaceanvim.neotest")
      if ok then
        table.insert(adapters, rust_adapter())
      end

      return {
        adapters = adapters,
        output = { open_on_run = false },
        status = { virtual_text = true },
        quickfix = { enabled = false },
      }
    end,
  },
}
