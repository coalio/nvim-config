require "nvchad.options"

-- Disables 'unnamedplus' so y, d, c, p use Neovim's internal registers.
-- System clipboard will ONLY be used when you explicitly press Ctrl+C or Ctrl+V.
vim.opt.clipboard = ""

vim.o.guifont = "Hack Nerd Font Mono:h12"
