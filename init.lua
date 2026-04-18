vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = "\\"

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    branch = "v2.5",
    import = "nvchad.plugins",
  },

  { import = "plugins" },
}, lazy_config)

-- load theme
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require "options"
require "autocmds"

vim.schedule(function()
  require "mappings"
end)

-- Only run this if Neovim is being launched by Neovide
if vim.g.neovide then
  -- Toggle fullscreen on F11 in Normal, Insert, and Visual modes
  vim.keymap.set({ 'n', 'v', 'i' }, '<F11>', function()
    vim.g.neovide_fullscreen = not vim.g.neovide_fullscreen
  end, { desc = 'Toggle Neovide Fullscreen' })
end

if vim.g.neovide then
  -- Faster animation (default 0.13)
  vim.g.neovide_cursor_animation_length = 0.05
  
  -- Shorter particle trail (default 0.8)
  vim.g.neovide_cursor_trail_size = 0.2
  
  -- Optional: completely disable the trail but keep the smooth movement
  -- vim.g.neovide_cursor_vfx_mode = "" 
end

-- ==============================================================================
-- Absolute Bulletproof Buffer Close (Keeps Layout Intact)
-- ==============================================================================

-- We attach the functions to _G (Global) so they can be safely called by our keymaps
_G.smart_close = function(force)
  local current_buf = vim.api.nvim_get_current_buf()
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = current_buf })
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

  -- 1. Bypass logic for Side Panels & Special Windows
  -- If you type :q in NvimTree, Lazy, Help, or a terminal, actually close the split.
  if buftype ~= "" or filetype == "NvimTree" or filetype == "lazy" then
    if force then vim.cmd('quit!') else vim.cmd('quit') end
    return
  end

  -- 2. Unsaved Changes Confirmation
  local is_modified = vim.api.nvim_get_option_value('modified', { buf = current_buf })
  if is_modified and not force then
    vim.api.nvim_echo({{"Are you sure you want to close the buffer without saving? (y/n) ", "WarningMsg"}}, false, {})
    local answer = vim.fn.getcharstr()
    vim.cmd('redraw')
    if answer:lower() == 'y' then
      _G.smart_close(true)
    end
    return
  end

  -- 3. Determine an alternate buffer to display to hold the window open
  local alt_buf = -1
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current_buf and vim.fn.buflisted(buf) == 1 then
      alt_buf = buf
      if buf == vim.fn.bufnr('#') then break end -- Prefer previous buffer
    end
  end
  --
  -- 3. THE FIX: Native NvChad Buffer Close
  -- We MUST use NvChad's internal tabufline. 
  -- If we manually bdelete, NvChad's background array goes out of sync 
  -- and it triggers an autocommand that breaks the window layout to "clean up".
  if force then
    vim.api.nvim_set_option_value('modified', false, { buf = current_buf })
  end

  -- If no alternate buffer exists, create a new empty scratch canvas
  if alt_buf == -1 then
    alt_buf = vim.api.nvim_create_buf(true, false)
  end

  -- 4. The Magic Fix: Detach the buffer from ALL splits BEFORE deleting it
  -- Neovim natively closes any split displaying a deleted buffer. 
  -- By sliding the alternate buffer into every window first, we completely decouple the UI.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == current_buf then
      vim.api.nvim_win_set_buf(win, alt_buf)
    end
  end

  -- 5. Delete the buffer safely
  -- Using schedule ensures the UI fully registers the window swaps before the buffer dies.
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(current_buf) then
      -- Temporarily clear the modified flag so NvChad allows it to be wiped
      vim.api.nvim_set_option_value('modified', false, { buf = current_buf })
      -- bwipeout entirely eradicates the buffer, forcing NvChad to clean up its top bar safely
      vim.cmd('silent! bwipeout! ' .. current_buf)
    end
  end)
end

_G.smart_wq = function()
  vim.cmd('write!')
  _G.smart_close(true)
end

_G.confirm_quit = function(all)
  vim.api.nvim_echo({{"Are you sure you want to quit Neovim? (y/n) ", "WarningMsg"}}, false, {})
  local answer = vim.fn.getcharstr()
  vim.cmd('redraw')
  if answer:lower() == 'y' then
    if all then vim.cmd('qa!') else vim.cmd('q!') end
  end
end

-- ==============================================================================
-- Custom Terminal Management
-- ==============================================================================

_G.run_custom_term = function(args, vertical)
  if vertical then
    vim.cmd("vsplit")
  else
    vim.cmd("split")
  end

  if args and args ~= "" then
    vim.cmd("terminal " .. args)
  else
    vim.cmd("terminal")
  end

  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value("buflisted", false, { buf = buf })

  vim.opt_local.number = false
  vim.opt_local.relativenumber = false
  vim.opt_local.signcolumn = "no"

  vim.cmd("startinsert")
end

-- ==============================================================================
-- 6. The Ultimate Command Interceptor
-- ==============================================================================
-- This intercepts the Enter key strictly in the command line.
-- If you typed exactly "q", it presses <C-c> to abort the command entirely, 
-- then runs our custom Lua code natively. This mathematically guarantees `:q` never propagates.
vim.keymap.set("c", "<CR>", function()
  if vim.fn.getcmdtype() == ":" then
    local cmd = vim.fn.getcmdline():match("^%s*(.-)%s*$") -- get command and trim spaces
    
    if cmd == "q" then
      return "<C-c><Cmd>lua _G.smart_close(false)<CR>"
    elseif cmd == "q!" then
      return "<C-c><Cmd>lua _G.smart_close(true)<CR>"
    elseif cmd == "wq" or cmd == "wq!" then
      return "<C-c><Cmd>lua _G.smart_wq()<CR>"
    elseif cmd == "qa" or cmd == "qa!" then
      return "<C-c><Cmd>lua _G.confirm_quit(true)<CR>"
    elseif cmd == "qw" or cmd == "qw!" then
      return "<C-c><Cmd>lua _G.confirm_quit(false)<CR>"
    end

    if cmd then
      local base, args = cmd:match("^([^%s]+)%s*(.*)$")
      if base == "term" or base == "te" or base == "terminal" then
        _G.pending_term_args = args or ""
        return "<C-c><Cmd>lua _G.run_custom_term(_G.pending_term_args, false)<CR>"
      elseif base == "vterm" then
        _G.pending_term_args = args or ""
        return "<C-c><Cmd>lua _G.run_custom_term(_G.pending_term_args, true)<CR>"
      end
    end
  end
  return "<CR>"
end, { expr = true, replace_keycodes = true, desc = "Intercept :q to keep layout intact" })

-- Standard keybinds
vim.keymap.set('n', '<F4>', function() _G.smart_close(false) end, { desc = 'Close buffer (with confirmation)' })
vim.keymap.set('n', '<leader>q', function() _G.smart_close(false) end, { desc = 'Close buffer, keep window' })

vim.g.nvim_tree_respect_buf_cwd = 1
