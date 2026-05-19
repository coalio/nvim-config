return {
  {
    "stevearc/conform.nvim",
    -- even = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  }, 

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    enabled = false,
  },

  {
    "neoclide/coc.nvim",
    branch = "release",
    lazy = false,
    init = function()
      local local_diagnostics_root = vim.fn.stdpath "config" .. "/coc-extensions/local-diagnostics"
      local local_pyright_adapter_path = local_diagnostics_root .. "/adapters/pyright.js"
      local local_pyright_diagnostics_enabled = vim.g.local_diagnostics_pyright_enabled ~= false
        and vim.fn.filereadable(local_pyright_adapter_path) == 1

      vim.opt.runtimepath:prepend(local_diagnostics_root)
      vim.g.coc_user_config = vim.tbl_extend("force", vim.g.coc_user_config or {}, {
        ["suggest.autoTrigger"] = "none",
        ["localDiagnostics.pyright.enabled"] = local_pyright_diagnostics_enabled,
        ["pyright.disableDiagnostics"] = local_pyright_diagnostics_enabled,
      })
      vim.g.coc_global_extensions = {
        "coc-clangd",
        "coc-css",
        "coc-eslint",
        "coc-html",
        "coc-json",
        "coc-pyright",
        "coc-tsserver",
      }
    end,
    config = function()
      require "configs.coc"
    end,
  },

  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      auto_preview = false,
      focus = true,
      multiline = false,
      win = {
        type = "split",
        relative = "win",
        position = "bottom",
        size = 12,
        wo = {
          winfixbuf = true,
          wrap = false,
        },
      },
    },
  },

  {
    import = "nvchad.blink.lazyspec",
    enabled = false,
  },

  {
    "saghen/blink.cmp",
    enabled = false,
  },

  {
    "rafamadriz/friendly-snippets",
    enabled = false,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "python",
      })
      return opts
    end,
  },

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
      options = { "buffers", "curdir", "folds", "help", "tabpages", "winsize", "winpos", "localoptions" },
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
    init = function()
      require("configs.nvim_tree_git_highlights").setup()
    end,
    opts = {
      sync_root_with_cwd = false,
      filters = {
        git_ignored = false,
      },
      update_focused_file = {
        update_root = false,
      },
      renderer = {
        root_folder_label = ":t",
        highlight_git = "name",
        highlight_opened_files = "name",
        icons = {
          show = {
            git = false,
          },
        },
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
    "coalio/codex.nvim",
    cmd = {
      "Codex",
      "CodexToggle",
      "CodexResume",
      "CodexFocus",
      "CodexSend",
      "CodexAdd",
      "CodexNew",
      "CodexInterrupt",
      "CodexSelectModel",
      "CodexApps",
      "CodexSkills",
      "CodexMcp",
      "CodexReloadMcp",
      "CodexStop",
    },
    opts = {
      keymaps = {
        toggle = nil,
        quit = "<C-q>",
        send = "<C-s>",
        interrupt = "<C-c>",
      },
      backend = "app_server",
      panel = true,
      width = 0.25,
      track_selection = true,
      app_server = {
        auto_start = true,
        experimental = true,
        dynamic_tools = true,
        enable_features = { "apps" },
      },
    },
    keys = {
      { "<leader>a", nil, desc = "AI/Codex" },
      {
        "<leader>ac",
        function()
          require("codex").toggle()
        end,
        desc = "Toggle Codex terminal",
        mode = { "n", "t" },
      },
      { "<leader>as", "<cmd>CodexSend<cr>", mode = { "n", "v" }, desc = "Send to Codex" },
      { "<leader>aC", "<cmd>CodexResume<cr>", desc = "Resume latest Codex session" },
      { "<leader>af", "<cmd>CodexFocus<cr>", desc = "Focus Codex terminal", mode = { "n", "t" } },
      { "<leader>ab", "<cmd>CodexAdd %<cr>", desc = "Add current buffer to Codex" },
      { "<leader>an", "<cmd>CodexNew<cr>", desc = "New Codex thread" },
      { "<leader>ai", "<cmd>CodexInterrupt<cr>", desc = "Interrupt Codex" },
      { "<leader>am", "<cmd>CodexMcp<cr>", desc = "Show Codex MCP tools" },
      { "<leader>aa", "<cmd>CodexApps<cr>", desc = "Add Codex app" },
      { "<leader>aS", "<cmd>CodexSkills<cr>", desc = "Add Codex skill" },
      { "<leader>aM", "<cmd>CodexSelectModel<cr>", desc = "Select Codex model" },
    },
  },
  {
    "folke/snacks.nvim",
    lazy = false,
  },

  { "MunifTanjim/nui.nvim", lazy = false }
}
