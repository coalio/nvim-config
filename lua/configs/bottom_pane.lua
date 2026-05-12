local M = {}

local height = 12
local terminal_buf
local terminal_chan
local problem_count = 0
local empty_problems_buf

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function is_fixed_window(win)
  return is_valid_win(win)
    and vim.fn.exists("+winfixbuf") == 1
    and vim.api.nvim_get_option_value("winfixbuf", { win = win })
end

local function lock_window_to_buffer(win)
  if not is_valid_win(win) or vim.fn.exists("+winfixbuf") == 0 then
    return
  end

  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { scope = "local", win = win })
end

local function set_winbar(win, active)
  if not is_valid_win(win) then
    return
  end

  local terminal_hl = active == "terminal" and "%#TabLineSel#" or "%#TabLine#"
  local problems_hl = active == "problems" and "%#TabLineSel#" or "%#TabLine#"

  vim.wo[win].winbar = table.concat {
    terminal_hl,
    "%@v:lua.NvChadBottomPaneTerminal@ Terminal %X",
    problems_hl,
    string.format("%%@v:lua.NvChadBottomPaneProblems@ Problems (%d) %%X", problem_count),
    "%#TabLineFill#",
  }
end

function _G.NvChadBottomPaneTerminal()
  require("configs.bottom_pane").open_terminal()
end

function _G.NvChadBottomPaneProblems()
  require("configs.bottom_pane").open_problems()
end

local function is_editor_window(win)
  if not is_valid_win(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local buftype = vim.bo[buf].buftype
  local filetype = vim.bo[buf].filetype

  return buftype == "" and filetype ~= "NvimTree" and filetype ~= "trouble"
end

local function is_buffer_target_window(win)
  return is_editor_window(win) and not is_fixed_window(win)
end

local function focus_buffer_target_window()
  local current_win = vim.api.nvim_get_current_win()
  if is_buffer_target_window(current_win) then
    return current_win
  end

  local previous_win = vim.fn.win_getid(vim.fn.winnr "#")
  if is_buffer_target_window(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
    return previous_win
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_buffer_target_window(win) then
      vim.api.nvim_set_current_win(win)
      return win
    end
  end
end

local function focus_editor_window()
  if is_editor_window(vim.api.nvim_get_current_win()) then
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_editor_window(win) then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
end

local function close_terminal_windows()
  if not is_valid_buf(terminal_buf) then
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_valid_win(win) and vim.api.nvim_win_get_buf(win) == terminal_buf then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

local function close_empty_problems_windows()
  if not is_valid_buf(empty_problems_buf) then
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_valid_win(win) and vim.api.nvim_win_get_buf(win) == empty_problems_buf then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

local function find_window_for_buf(buf)
  if not is_valid_buf(buf) then
    return nil
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_valid_win(win) and vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
end

local function close_trouble()
  local ok, trouble = pcall(require, "trouble")
  if not ok then
    return
  end

  pcall(trouble.close, "qflist")
  pcall(trouble.close, { mode = "qflist" })
end

local function trouble_is_open()
  local ok, trouble = pcall(require, "trouble")
  if not ok then
    return false
  end

  local open = false
  pcall(function()
    open = trouble.is_open "qflist"
  end)

  if open then
    return true
  end

  pcall(function()
    open = trouble.is_open { mode = "qflist" }
  end)

  return open
end

local function is_bottom_pane_open()
  return find_window_for_buf(terminal_buf) ~= nil or find_window_for_buf(empty_problems_buf) ~= nil or trouble_is_open()
end

local function refresh_winbars(active)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if buf == terminal_buf then
      lock_window_to_buffer(win)
      set_winbar(win, active == "terminal" and "terminal" or nil)
    elseif vim.bo[buf].filetype == "trouble" or buf == empty_problems_buf then
      lock_window_to_buffer(win)
      set_winbar(win, active == "problems" and "problems" or nil)
    end
  end
end

local function ensure_empty_problems_buf()
  if not is_valid_buf(empty_problems_buf) then
    empty_problems_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[empty_problems_buf].bufhidden = "wipe"
    vim.bo[empty_problems_buf].buftype = "nofile"
    vim.bo[empty_problems_buf].swapfile = false
    vim.bo[empty_problems_buf].modifiable = true
    vim.api.nvim_buf_set_lines(empty_problems_buf, 0, -1, false, {
      "No problems.",
      "",
      "Diagnostics will appear here when available.",
    })
    vim.bo[empty_problems_buf].modifiable = false
  end

  return empty_problems_buf
end

local function open_bottom_window(buf, active)
  focus_editor_window()
  vim.cmd("belowright " .. height .. "split")

  local win = vim.api.nvim_get_current_win()
  if is_valid_buf(buf) then
    vim.api.nvim_win_set_buf(win, buf)
  end

  vim.api.nvim_win_set_height(win, height)
  vim.wo[win].winfixheight = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  lock_window_to_buffer(win)
  set_winbar(win, active)

  return win
end

local function ensure_terminal()
  if is_valid_buf(terminal_buf) and vim.bo[terminal_buf].buftype == "terminal" then
    return nil
  end

  terminal_buf = vim.api.nvim_create_buf(false, true)
  local win = open_bottom_window(terminal_buf, "terminal")
  terminal_chan = vim.fn.termopen(vim.o.shell)

  vim.bo[terminal_buf].buflisted = false
  vim.b[terminal_buf].bottom_pane_kind = "terminal"

  return win
end

function M.open_terminal(cmd)
  close_trouble()
  close_empty_problems_windows()

  local win = ensure_terminal() or find_window_for_buf(terminal_buf) or open_bottom_window(terminal_buf, "terminal")
  vim.api.nvim_set_current_win(win)
  set_winbar(win, "terminal")

  if cmd and cmd ~= "" then
    local chan = vim.bo[terminal_buf].channel or terminal_chan
    pcall(vim.api.nvim_chan_send, chan, cmd .. "\n")
  end

  vim.cmd "startinsert"
end

local function diagnostic_type(severity)
  severity = tostring(severity or ""):lower()

  if severity:find "error" then
    return "E"
  elseif severity:find "warning" then
    return "W"
  elseif severity:find "information" or severity:find "info" then
    return "I"
  end

  return "N"
end

local function update_coc_qflist()
  if vim.fn.exists "*CocAction" == 0 then
    vim.notify("coc.nvim is not loaded yet", vim.log.levels.WARN)
    return false
  end

  if vim.g.coc_service_initialized ~= 1 then
    vim.notify("coc.nvim is still starting; try :Problems again in a moment", vim.log.levels.WARN)
    return false
  end

  local ok, diagnostics = pcall(vim.fn.CocAction, "diagnosticList")
  if not ok or type(diagnostics) ~= "table" then
    vim.notify("Could not read CoC diagnostics", vim.log.levels.WARN)
    return false
  end

  local items = {}
  for _, item in ipairs(diagnostics) do
    local source = item.source and item.source ~= "" and item.source or "coc"
    local message = tostring(item.message or ""):gsub("%s+", " ")

    table.insert(items, {
      filename = item.file,
      bufnr = item.bufnr,
      lnum = tonumber(item.lnum) or 1,
      end_lnum = tonumber(item.end_lnum),
      col = tonumber(item.col) or 1,
      end_col = tonumber(item.end_col),
      type = diagnostic_type(item.severity),
      text = string.format("[%s] %s", source, message),
    })
  end

  vim.fn.setqflist({}, "r", {
    title = "CoC Problems",
    items = items,
  })

  problem_count = #items
  refresh_winbars()

  return #items > 0
end

function M.open_problems()
  local has_items = update_coc_qflist()

  close_terminal_windows()
  close_empty_problems_windows()

  if has_items then
    local ok, trouble = pcall(require, "trouble")
    if ok then
      trouble.open {
        mode = "qflist",
        focus = true,
        refresh = true,
        win = {
          type = "split",
          relative = "win",
          position = "bottom",
          size = height,
          wo = {
            winfixbuf = true,
          },
        },
      }

      vim.schedule(function()
        set_winbar(vim.api.nvim_get_current_win(), "problems")
        refresh_winbars("problems")
      end)
      return
    end

    vim.cmd("belowright " .. height .. "copen")
    lock_window_to_buffer(vim.api.nvim_get_current_win())
    set_winbar(vim.api.nvim_get_current_win(), "problems")
    refresh_winbars("problems")
    return
  end

  close_trouble()
  local buf = ensure_empty_problems_buf()
  local win = find_window_for_buf(buf) or open_bottom_window(buf, "problems")
  vim.api.nvim_set_current_win(win)
  set_winbar(win, "problems")
  refresh_winbars("problems")
end

function M.refresh_problems()
  local ok, trouble = pcall(require, "trouble")
  local has_items = update_coc_qflist()

  if ok and trouble.is_open "qflist" then
    if has_items then
      pcall(trouble.refresh, "qflist")
    else
      close_trouble()
      local buf = ensure_empty_problems_buf()
      local win = find_window_for_buf(buf) or open_bottom_window(buf, "problems")
      set_winbar(win, "problems")
    end
  end

  refresh_winbars()
end

function M.close()
  close_trouble()
  close_terminal_windows()
  close_empty_problems_windows()
end

function M.is_open()
  return is_bottom_pane_open()
end

function M.toggle_terminal()
  if is_bottom_pane_open() then
    M.close()
    return
  end

  M.open_terminal()
end

function M.focus_buffer_target_window()
  return focus_buffer_target_window()
end

function M.is_current_window_fixed()
  return is_fixed_window(vim.api.nvim_get_current_win())
end

function M.patch_nvchad_tabufline()
  local ok, tabufline = pcall(require, "nvchad.tabufline")
  if not ok or tabufline._bottom_pane_patched then
    return
  end

  local function route(fn)
    return function(...)
      if not focus_buffer_target_window() then
        return
      end

      local ran, err = pcall(fn, ...)
      if not ran and not tostring(err):find("winfixbuf", 1, true) then
        error(err)
      end
    end
  end

  local next_buf = tabufline.next
  local prev_buf = tabufline.prev
  local goto_buf = tabufline.goto_buf
  local close_buffer = tabufline.close_buffer

  tabufline.next = route(next_buf)
  tabufline.prev = route(prev_buf)
  tabufline.goto_buf = route(goto_buf)
  tabufline.close_buffer = function(bufnr)
    if is_fixed_window(vim.api.nvim_get_current_win()) and not bufnr then
      return
    end

    return route(close_buffer)(bufnr)
  end

  tabufline._bottom_pane_patched = true
end

function M.setup()
  M.patch_nvchad_tabufline()

  vim.api.nvim_create_user_command("BottomTerm", function(opts)
    M.open_terminal(opts.args)
  end, { nargs = "*", complete = "shellcmd" })

  vim.api.nvim_create_user_command("Problems", function()
    M.open_problems()
  end, {})

  vim.api.nvim_create_user_command("BottomPaneClose", function()
    M.close()
  end, {})

  local group = vim.api.nvim_create_augroup("BottomPane", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CocDiagnosticChange",
    callback = function()
      M.refresh_problems()
    end,
  })
end

return M
