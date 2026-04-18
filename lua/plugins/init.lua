return {
  {
    "stevearc/conform.nvim",
    -- even = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  }, 

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
    import = "nvchad.blink.lazyspec",
    enabled = false,
  },

  {
    "saghen/blink.cmp",
    enabled = false,
  },

  -- 	"nvim-treesitter/nvim-treesitter",
  -- 	opts = {
  -- 		ensure_installed = {
  -- 			"vim", "lua", "vimdoc",
  --      "html", "css"
  -- 		},
  -- 	},
  -- },
  --

  -- My stuff goes here
  --

  {
    "goolord/alpha-nvim",
    lazy = false,
    config = function()
      require "configs.alpha"
    end,
  },
  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {
      options = { "buffers", "curdir", "folds", "help", "tabpages", "winsize", "winpos", "terminal", "localoptions" },
    },
  },
  {
    "mg979/vim-visual-multi",
    lazy = false,
    init = function()
      vim.cmd([[
        let g:VM_maps = {}
        let g:VM_maps['Find Under']         = '<C-d>'           " replace C-n
        let g:VM_maps['Find Subword Under'] = '<C-d>'           " replace visual C-n
        
        " Optional vertical spawning
        "let g:VM_maps['Add Cursor Down']    = '<C-Down>'
        "let g:VM_maps['Add Cursor Up']      = '<C-Up>'
      ]])
    end,
  },

  {
    "nvim-tree/nvim-tree.lua",
    opts = {
      sync_root_with_cwd = false,
      update_focused_file = {
        update_root = false,
      },
      renderer = {
        root_folder_label = ":t",
        highlight_opened_files = "name",
      },
    },
  },

  {
    "ahmedkhalf/project.nvim",
    lazy = false,
    config = function()
      require("project_nvim").setup({
        manual_mode = true,
      })
    end,
  },

  {
    "nvim-telescope/telescope.nvim",
    opts = function(_, opts)
      opts.extensions_list = opts.extensions_list or {}
      return opts
    end,
  },
  {
    "folke/which-key.nvim",
    enabled = false,
  },
  {
    "coalio/openclaude.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      terminal_cmd = "/home/coal/.local/bin/claude",
    },
    config = true,
    keys = {
      { "<leader>a", nil, desc = "AI/Claude Code (Claude Code)" },
      { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude (Claude Code)" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude (Claude Code)" },
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude (Claude Code)" },
      { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude (Claude Code)" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer (Claude Code)" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude (Claude Code)" },
      {
        "<leader>as",
        "<cmd>ClaudeCodeTreeAdd<cr>",
        desc = "Add file (Claude Code)",
        ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw" },
      },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff (Claude Code)" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff (Claude Code)" },
    },
  },
  {
    "folke/snacks.nvim",
    lazy = false,
  },

  { "MunifTanjim/nui.nvim", lazy = false }
}

