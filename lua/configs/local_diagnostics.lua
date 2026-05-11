local M = {}

local command_prefix = "localDiagnostics"

local function coc_can_run_commands()
  return vim.fn.exists "*CocAction" == 1 and vim.g.coc_service_initialized == 1
end

local function coc_can_run_async_commands()
  return vim.fn.exists "*CocActionAsync" == 1 and vim.g.coc_service_initialized == 1
end

local function result_ok(result)
  return type(result) == "table" and result.ok == true
end

function M.file_uri(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  if path:match "^[%a][%w+.-]*:" then
    return path
  end

  return vim.uri_from_fname(vim.fn.fnamemodify(path, ":p"))
end

function M.run(command, ...)
  if not coc_can_run_commands() then
    return nil, "coc.nvim is not initialized"
  end

  local ok, result = pcall(vim.fn.CocAction, "runCommand", command, ...)
  if not ok then
    return nil, result
  end

  if type(result) == "table" and result.ok == false then
    return nil, result.error or "local diagnostics command failed", result
  end

  return result
end

function M.run_async(command, ...)
  if not coc_can_run_async_commands() then
    return false, "coc.nvim is not initialized"
  end

  local ok, err = pcall(vim.fn.CocActionAsync, "runCommand", command, ...)
  if not ok then
    return false, err
  end

  return true
end

function M.ping()
  return M.run(command_prefix .. ".ping")
end

function M.status()
  return M.run(command_prefix .. ".status")
end

function M.adapters()
  return M.run(command_prefix .. ".adapters")
end

function M.refresh_open(opts)
  return M.run_async(command_prefix .. ".refreshOpen", opts or {})
end

function M.set(uri_or_path, diagnostics, opts)
  local uri = M.file_uri(uri_or_path)
  if not uri then
    return nil, "uri_or_path must be a non-empty string"
  end

  return M.run(command_prefix .. ".set", uri, diagnostics or {}, opts or {})
end

function M.clear(uri_or_path)
  if uri_or_path == nil or uri_or_path == "" then
    return M.run(command_prefix .. ".clear")
  end

  local uri = M.file_uri(uri_or_path)
  if not uri then
    return nil, "uri_or_path must be a non-empty string"
  end

  return M.run(command_prefix .. ".clear", uri)
end

function M.ready()
  local result = M.ping()
  return result_ok(result)
end

function M.setup()
  vim.api.nvim_create_user_command("LocalDiagnosticsStatus", function()
    local status, err = M.status()
    if not status then
      vim.notify("Local diagnostics unavailable: " .. tostring(err), vim.log.levels.WARN)
      return
    end

    vim.notify(
      string.format(
        "Local diagnostics: %d URIs, %d diagnostics%s",
        tonumber(status.uris) or 0,
        tonumber(status.diagnostics) or 0,
        status.lastUpdate and (", updated " .. status.lastUpdate) or ""
      )
    )
  end, {})

  vim.api.nvim_create_user_command("LocalDiagnosticsClear", function(opts)
    local result, err = M.clear(opts.args)
    if not result then
      vim.notify("Could not clear local diagnostics: " .. tostring(err), vim.log.levels.WARN)
      return
    end

    vim.notify "Local diagnostics cleared"
  end, { nargs = "?", complete = "file" })

  vim.api.nvim_create_user_command("LocalDiagnosticsRefresh", function()
    local ok, err = M.refresh_open()
    if not ok then
      vim.notify("Could not refresh local diagnostics: " .. tostring(err), vim.log.levels.WARN)
    end
  end, {})
end

return M
