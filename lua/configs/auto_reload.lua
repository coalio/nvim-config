local M = {}

local enabled = vim.g.auto_reload_external_changes_enabled ~= false
local watchers = {}
local pending_reloads = {}
local ignored_fs_events_until = {}
local ignored_filetypes = {
  NvimTree = true,
  Trouble = true,
  ["neo-tree"] = true,
  ["neo-tree-popup"] = true,
  lazy = true,
  trouble = true,
}

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function normalize_file(path)
  if not path or path == "" then
    return nil
  end

  return vim.fn.fnamemodify(path, ":p")
end

local function should_watch_buffer(buf)
  if not enabled or not is_valid_buf(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return false
  end

  if vim.bo[buf].buftype ~= "" or not vim.bo[buf].buflisted or ignored_filetypes[vim.bo[buf].filetype] then
    return false
  end

  local file = normalize_file(vim.api.nvim_buf_get_name(buf))
  return file and vim.fn.filereadable(file) == 1
end

local function listed_file_buffers()
  local buffers = {}

  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local buf = tonumber(info.bufnr)
    if buf and should_watch_buffer(buf) then
      table.insert(buffers, buf)
    end
  end

  return buffers
end

local function stop_watcher(buf)
  local watcher = watchers[buf]
  if not watcher then
    return
  end

  if watcher.handle and not watcher.handle:is_closing() then
    watcher.handle:stop()
    watcher.handle:close()
  end

  watchers[buf] = nil
end

local function stop_all_watchers()
  for buf in pairs(watchers) do
    stop_watcher(buf)
  end
end

local function emit_reloaded(buf, file)
  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "ExternalFileAutoReload",
    data = {
      bufnr = buf,
      file = file,
    },
  })
end

local function reload_buffer(buf)
  if not should_watch_buffer(buf) or vim.bo[buf].modified then
    return false
  end

  local file = normalize_file(vim.api.nvim_buf_get_name(buf))
  if not file then
    return false
  end

  local ok = pcall(vim.api.nvim_buf_call, buf, function()
    vim.cmd "silent! keepalt edit!"
  end)

  if ok then
    emit_reloaded(buf, file)
  end

  return ok
end

local function schedule_reload(buf)
  if not enabled or pending_reloads[buf] then
    return
  end

  pending_reloads[buf] = vim.defer_fn(function()
    pending_reloads[buf] = nil

    if enabled then
      reload_buffer(buf)
    end
  end, 120)
end

local function watch_buffer(buf)
  if not should_watch_buffer(buf) then
    stop_watcher(buf)
    return
  end

  local uv = vim.uv or vim.loop
  local file = normalize_file(vim.api.nvim_buf_get_name(buf))
  if not uv or not file then
    stop_watcher(buf)
    return
  end

  local existing = watchers[buf]
  if existing and existing.file == file then
    return
  end

  stop_watcher(buf)

  local handle = uv.new_fs_event()
  if not handle then
    return
  end

  local ok = pcall(function()
    handle:start(file, {}, vim.schedule_wrap(function()
      local ignore_until = ignored_fs_events_until[buf]
      if ignore_until and uv.hrtime() < ignore_until then
        return
      end

      schedule_reload(buf)
    end))
  end)

  if ok then
    watchers[buf] = { file = file, handle = handle }
  elseif not handle:is_closing() then
    handle:close()
  end
end

local function sync_watchers()
  local listed = {}

  if enabled then
    for _, buf in ipairs(listed_file_buffers()) do
      listed[buf] = true
      watch_buffer(buf)
    end
  end

  for buf in pairs(watchers) do
    if not listed[buf] then
      stop_watcher(buf)
    end
  end
end

function M.enabled()
  return enabled
end

function M.enable(opts)
  opts = opts or {}

  if enabled then
    return
  end

  enabled = true
  vim.g.auto_reload_external_changes_enabled = true
  sync_watchers()

  if not opts.silent then
    vim.notify "External file auto-reload enabled"
  end
end

function M.disable(opts)
  opts = opts or {}

  if not enabled then
    return
  end

  enabled = false
  vim.g.auto_reload_external_changes_enabled = false
  stop_all_watchers()

  if not opts.silent then
    vim.notify "External file auto-reload disabled"
  end
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("ExternalFileAutoReload", { clear = true })

  vim.api.nvim_create_user_command("AutoReloadExternalFilesToggle", function()
    M.toggle()
  end, {})

  vim.api.nvim_create_user_command("AutoReloadExternalFilesEnable", function()
    M.enable()
  end, {})

  vim.api.nvim_create_user_command("AutoReloadExternalFilesDisable", function()
    M.disable()
  end, {})

  vim.api.nvim_create_autocmd({ "BufAdd", "BufEnter", "BufFilePost", "BufReadPost" }, {
    group = group,
    callback = function(args)
      watch_buffer(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      local uv = vim.uv or vim.loop
      if uv then
        ignored_fs_events_until[args.buf] = uv.hrtime() + 1000000000
      end

      watch_buffer(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload", "BufWipeout" }, {
    group = group,
    callback = function(args)
      stop_watcher(args.buf)
      pending_reloads[args.buf] = nil
      ignored_fs_events_until[args.buf] = nil
    end,
  })

  vim.api.nvim_create_autocmd({ "VimEnter", "SessionLoadPost" }, {
    group = group,
    callback = sync_watchers,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = stop_all_watchers,
  })

  vim.schedule(sync_watchers)
end

return M
