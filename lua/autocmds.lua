require "nvchad.autocmds"

local autocmd = vim.api.nvim_create_autocmd

pcall(vim.api.nvim_del_augroup_by_name, "nvchad_dashboard")

autocmd("BufReadPost", {
  pattern = "*",
  callback = function()
    local line = vim.fn.line("'\"")
    if
      line > 1
      and line <= vim.fn.line "$"
      and vim.bo.filetype ~= "commit"
      and vim.fn.index({ "xxd", "gitrebase" }, vim.bo.filetype) == -1
    then
      vim.cmd [[normal! g`"]]
    end
  end,
})

autocmd("VimEnter", {
  once = true,
  callback = function(data)
    local persistence = require "persistence"
    local no_args = vim.fn.argc() == 0
    local target = data.file ~= "" and vim.fn.fnamemodify(data.file, ":p") or vim.fn.getcwd()
    local is_dir = target ~= "" and vim.fn.isdirectory(target) == 1

    if is_dir then
      vim.cmd.cd(target)
    end

    if no_args then
      vim.schedule(function()
        persistence.load { last = true }
      end)
      return
    end

    if is_dir then
      vim.schedule(function()
        persistence.load()
      end)
    end
  end,
})

autocmd("User", {
  pattern = "PersistenceSavePre",
  callback = function()
    local ok, api = pcall(require, "nvim-tree.api")
    if ok and api.tree.is_visible() then
      api.tree.close()
    end
  end,
})

autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    vim.cmd "startinsert"
  end,
})
