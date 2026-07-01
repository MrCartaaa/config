-- ~/.config/nvim/lua/plugins/docker.lua

return {
-- ✅ Better alternative: dockyard.nvim (modern, no LuaRocks dependency)
  {
    "emrearmagan/dockyard.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim" },
    config = function()
      require("dockyard").setup({
        -- Add your keymaps here if desired
      })
      -- Example keymap
      vim.keymap.set("n", "<leader>dd", "<cmd>DockyardToggle<cr>", { desc = "Toggle Dockyard" })
    end,
  },

  -- 🧠 Dockerfile LSP
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")

      lspconfig.dockerls.setup({
        cmd = { "docker-langserver", "--stdio" },
        filetypes = { "dockerfile", "Dockerfile" },
        -- Use default capabilities if cmp_nvim_lsp is not available
        capabilities = vim.lsp.protocol.make_client_capabilities(),
        on_attach = function(client, bufnr)
          local opts = { buffer = bufnr, silent = true, noremap = true }
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        end,
      })
    end,
  },

  -- 🧩 nvim-cmp + luasnip (kept as-is)
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
