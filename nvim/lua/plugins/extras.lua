return {
  -- Coding essentials
  { import = "lazyvim.plugins.extras.coding.mini-surround" },
  { import = "lazyvim.plugins.extras.coding.mini-comment" },

  -- UI/Util
  { import = "lazyvim.plugins.extras.ui.alpha" },
  { import = "lazyvim.plugins.extras.util.mini-hipatterns" },
  { import = "lazyvim.plugins.extras.util.project" },

  -- Lang extras (based on your languages: Python, JS/TS, Rust)
  { import = "lazyvim.plugins.extras.lang.python" },
  { import = "lazyvim.plugins.extras.lang.typescript" },

  { import = "lazyvim.plugins.extras.lang.tailwind" }, -- For CSS/JS if using Tailwind
  { import = "lazyvim.plugins.extras.lang.rust" },

  -- Editor/Diagnostics
  { import = "lazyvim.plugins.extras.editor.harpoon2" },
}
