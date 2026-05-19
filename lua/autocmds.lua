require "nvchad.autocmds"

local autocmd = vim.api.nvim_create_autocmd

local function wipe_terminal_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
      vim.bo[buf].buflisted = false
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

local function close_bottom_pane()
  local ok, bottom_pane = pcall(require, "configs.bottom_pane")
  if ok then
    bottom_pane.close()
  end
end

local function is_codex_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local ft = vim.bo[buf].filetype
  local name = vim.api.nvim_buf_get_name(buf)
  return ft == "codex" or ft == "codex-session-list" or name:match "^codex://"
end

local function close_codex_panes()
  local codex = package.loaded["codex"]
  if codex and type(codex.close) == "function" then
    pcall(codex.close)
  end

  local session_list = package.loaded["codex.session_list"]
  if session_list and type(session_list.close) == "function" then
    pcall(session_list.close)
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.w[win].codex_session_list or is_codex_buffer(buf) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_codex_buffer(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

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
    close_codex_panes()
    close_bottom_pane()
    wipe_terminal_buffers()

    local ok, api = pcall(require, "nvim-tree.api")
    if ok and api.tree.is_visible() then
      api.tree.close()
    end
  end,
})

autocmd("User", {
  pattern = "PersistenceLoadPost",
  callback = function()
    vim.schedule(function()
      local browser = package.loaded["configs.browser"]
      if browser and browser.consume_persistence_tree_refresh_skip and browser.consume_persistence_tree_refresh_skip() then
        return
      end

      close_bottom_pane()
      wipe_terminal_buffers()

      local ok, api = pcall(require, "nvim-tree.api")
      if ok then
        if not api.tree.is_visible() then
          api.tree.open()
        end
        api.tree.change_root(vim.fn.getcwd())
      end
    end)
  end,
})

autocmd("TermOpen", {
  pattern = "*",
  callback = function(args)
    vim.bo[args.buf].buflisted = false
    vim.cmd "startinsert"
  end,
})
