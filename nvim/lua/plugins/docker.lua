-- ~/.config/nvim/lua/plugins/docker.lua

return {
  -- 🐳 nvim-docker (unchanged)
  {
    "evanrelf/nvim-docker",
    dependencies = { "nvim-telescope/telescope.nvim" },
    config = function()
      require("nvim-docker").setup({
        keys = {
          { "<leader>Ds", function() require("nvim-docker").container_select("start") end, desc = "Start container" },
          { "<leader>Dr", function() require("nvim-docker").container_select("restart") end, desc = "Restart" },
          { "<leader>Dk", function() require("nvim-docker").container_select("stop") end, desc = "Stop" },
          { "<leader>Dl", function() require("nvim-docker").container_select("logs") end, desc = "Logs (follow)" },
          { "<leader>Di", function() require("nvim-docker").container_select("inspect") end, desc = "Inspect" },
          { "<leader>Dx", function() require("nvim-docker").container_select("exec") end, desc = "Exec shell" },
        },
      })
    end,
  },

  -- 🧠 Dockerfile LSP (FIXED)
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")

      -- ✅ Explicitly set cmd to use --stdio
      lspconfig.dockerls.setup({
        cmd = { "docker-langserver", "--stdio" },  -- ← THIS IS CRITICAL!
        filetypes = { "dockerfile", "Dockerfile" },
        capabilities = require("cmp_nvim_lsp").default_capabilities(),
        on_attach = function(client, bufnr)
          local opts = { buffer = bufnr, silent = true, noremap = true }
          vim.keymap.set("n", "gd", vim.diagnostic.open_float, opts)
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        end,
      })
    end,
  },

  -- 📦 Docker snippets (optional — works if you use luasnip correctly)
  {
    "L3MON4D3/docker-snippets",
    dependencies = { "hrsh7th/nvim-cmp" },
    config = function()
      local luasnip = require("luasnip")
      luasnip.config.setup({ history = true })
      -- Load Dockerfile snippets
      luasnip.load_snippets({ "dockerfile" })
    end,
  },

  -- 🧩 nvim-cmp + luasnip adapter
  {
    "hrsh7th/nvim-cmp",
    dependencies = { "saadparwaiz1/cmp_luasnip" },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<Tab>"] = cmp.mapping.confirm({ select = true }),
          ["<C-l>"] = function()
            if luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            end
          end,
        }),
        sources = cmp.config.sources({
          { name = "luasnip" },
          { name = "nvim_lsp" },
          { name = "buffer" },
        }),
      })
    end,
  },
}
