vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.updatetime = 300
vim.opt.signcolumn = "yes"

local keyset = vim.keymap.set
local opts = { silent = true, nowait = true }

keyset("n", "[g", "<Plug>(coc-diagnostic-prev)", opts)
keyset("n", "]g", "<Plug>(coc-diagnostic-next)", opts)

keyset("n", "gd", "<Plug>(coc-definition)", opts)
keyset("n", "gy", "<Plug>(coc-type-definition)", opts)
keyset("n", "gi", "<Plug>(coc-implementation)", opts)
keyset("n", "gr", "<Plug>(coc-references)", opts)

keyset("n", "K", function()
  local ft = vim.bo.filetype
  local cw = vim.fn.expand "<cword>"

  if ft == "vim" or ft == "help" then
    vim.cmd("help " .. cw)
  elseif vim.fn["coc#rpc#ready"]() == 1 then
    vim.fn.CocActionAsync "doHover"
  else
    vim.cmd("!" .. vim.o.keywordprg .. " " .. cw)
  end
end, opts)

keyset("n", "<leader>rn", "<Plug>(coc-rename)", opts)
keyset("n", "<leader>ca", "<Plug>(coc-codeaction-cursor)", opts)
keyset("x", "<leader>ca", "<Plug>(coc-codeaction-selected)", opts)
keyset("n", "<leader>qf", "<Plug>(coc-fix-current)", opts)

vim.api.nvim_create_user_command("Format", "call CocAction('format')", {})
vim.api.nvim_create_user_command("OR", "call CocActionAsync('runCommand', 'editor.action.organizeImport')", {})

require("configs.bottom_pane").setup()
