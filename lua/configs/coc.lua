vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.updatetime = 300
vim.opt.signcolumn = "yes"

local keyset = vim.keymap.set
local opts = { silent = true, nowait = true }

local pyright_parameter_hints_enabled = false
local local_pyright_adapter_path = vim.fn.stdpath "config" .. "/coc-extensions/local-diagnostics/adapters/pyright.js"
local local_pyright_diagnostics_enabled = vim.g.local_diagnostics_pyright_enabled ~= false
  and vim.fn.filereadable(local_pyright_adapter_path) == 1

local function coc_config(key, value)
  if vim.fn.exists "*coc#config" == 1 then
    vim.fn["coc#config"](key, value)
  end
end

local function set_pyright_parameter_hints(enabled)
  pyright_parameter_hints_enabled = enabled
  coc_config("pyright.inlayHints", {
    parameterTypes = enabled,
  })
end

set_pyright_parameter_hints(false)
coc_config("localDiagnostics.pyright.enabled", local_pyright_diagnostics_enabled)

-- coc-pyright only reads this during activation, so it has to be set at startup.
coc_config("pyright.disableDiagnostics", local_pyright_diagnostics_enabled)

local clangd_path = vim.fn.expand "~/.config/coc/extensions/coc-clangd-data/install/22.1.0/clangd_22.1.0/bin/clangd"
if vim.fn.executable(clangd_path) == 1 then
  coc_config("clangd.path", clangd_path)
end

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
keyset("n", "<leader>ih", function()
  set_pyright_parameter_hints(not pyright_parameter_hints_enabled)
  vim.notify("Pyright parameter hints " .. (pyright_parameter_hints_enabled and "enabled" or "disabled"))
end, vim.tbl_extend("force", opts, { desc = "Toggle Pyright parameter hints" }))

vim.api.nvim_create_user_command("Format", "call CocAction('format')", {})
vim.api.nvim_create_user_command("OR", "call CocActionAsync('runCommand', 'editor.action.organizeImport')", {})

require("configs.local_diagnostics").setup()
require("configs.bottom_pane").setup()
