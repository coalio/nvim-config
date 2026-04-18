require "nvchad.mappings"
local map = vim.keymap.set

map("n", "<C-p>", "<cmd>Telescope find_files<CR>", { desc = "Find files" })
map("n", "<F1>", "<cmd>Telescope keymaps<CR>", { desc = "Show keymaps" })
map("n", "<F2>", "<cmd>Telescope live_grep<CR>", { desc = "Live grep" })
map("n", "<F3>", "<cmd>set hlsearch!<CR>", { desc = "Toggle search highlight" })
map("n", "<C-_>", "<cmd>Telescope current_buffer_fuzzy_find<CR>", { desc = "Find in current buffer" })

map("n", "<C-S-b>", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle NvimTree" })

map("n", "<leader>rm", function()
  local api = require "nvim-tree.api"
  api.tree.find_file({ open = true, focus = true })
end, { desc = "Reveal current file in NvimTree" })
map("n", "<leader>f", function()
  require("configs.browser").browse_home()
end, { desc = "Browse folder" })
map("n", "<leader>nr", function()
  vim.opt.relativenumber = not vim.opt.relativenumber:get()
end, { desc = "Toggle relative line numbers" })

vim.api.nvim_create_user_command("Term", function(opts)
  _G.run_custom_term(opts.args, false)
end, { nargs = "*", complete = "shellcmd" })

vim.api.nvim_create_user_command("Vterm", function(opts)
  _G.run_custom_term(opts.args, true)
end, { nargs = "*", complete = "shellcmd" })

vim.cmd [[
  cnoreabbrev <expr> term getcmdtype() == ":" && getcmdline() =~# '^term\>' ? 'Term' : 'term'
  cnoreabbrev <expr> te getcmdtype() == ":" && getcmdline() =~# '^te\>' ? 'Term' : 'te'
  cnoreabbrev <expr> terminal getcmdtype() == ":" && getcmdline() =~# '^terminal\>' ? 'Term' : 'terminal'
  cnoreabbrev <expr> vterm getcmdtype() == ":" && getcmdline() =~# '^vterm\>' ? 'Vterm' : 'vterm'
]]

map("v", "<C-c>", '"+y', { desc = "Copy selection to system clipboard" })
map("n", "<C-c>", '"+yy', { desc = "Copy line to system clipboard" })

_G.ClipUnix = function()
  local content = vim.fn.getreg "+"
  content = content:gsub("\r\n", "\n"):gsub("\r", "")
  return content
end

map({ "i", "c" }, "<C-v>", "<C-R>=v:lua.ClipUnix()<CR>", { desc = "Paste from system clipboard" })

map("n", "<C-v>", function()
  vim.fn.setreg("z", _G.ClipUnix())
  vim.cmd [[normal! "zp]]
end, { desc = "Paste from system clipboard" })

map("t", "<C-v>", function()
  vim.api.nvim_chan_send(vim.bo.channel, _G.ClipUnix())
end, { desc = "Paste from system clipboard into terminal" })

_G.SmartQuit = function(cmd)
  local has_modified = false

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].modified and vim.bo[buf].buflisted then
      has_modified = true
      break
    end
  end

  if has_modified then
    local ans = vim.fn.input "Are you sure you want to quit? [Y/n] "
    vim.cmd "redraw"

    if ans:lower() == "y" or ans == "" then
      if cmd == "q" or cmd == "qw" then
        vim.cmd "q!"
      else
        vim.cmd "qa!"
      end
    else
      print "Quit canceled."
    end
  else
    if cmd == "qw" then
      vim.cmd "q"
    else
      vim.cmd(cmd)
    end
  end
end

vim.cmd [[
  function! s:CheckQuit(cmd)
    let c = char2nr(v:char)
    if getcmdtype() == ':' && getcmdline() == a:cmd && (c == 13 || c == 10)
      return 'lua _G.SmartQuit("' . a:cmd . '")'
    else
      return a:cmd
    endif
  endfunction

  cabbrev <expr> q <SID>CheckQuit('q')
  cabbrev <expr> qa <SID>CheckQuit('qa')
  cabbrev <expr> qw <SID>CheckQuit('qw')
]]
