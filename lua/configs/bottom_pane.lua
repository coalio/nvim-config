local M = {}

local height = 12
local terminal_buf
local terminal_chan
local terminal_sessions = {}
local terminal_order = {}
local active_terminal_id
local terminal_session_width = 7
local problem_count = 0
local problems_loading = false
local diagnostics_response_received = false
local waiting_for_local_diagnostics = false
local local_diagnostics_epoch = 0
local waiting_for_local_diagnostics_epoch
local empty_problems_buf
local winbar_marker = "NvChadBottomPane"
local bottom_win
local active_kind
local problems_scope = "open"
local auto_problem_folds = false
local diagnostic_cache = {}
local diagnostic_source_conflicts = {}
local diagnostic_source_conflicts_loaded = false
local pending_buffer_refreshes = {}
local pending_problem_refresh
local pending_problem_poll_generation = 0
local diagnostic_refresh_requested_until = 0
local local_diagnostic_refresh_requested_until = 0
local reading_coc_diagnostics = false
local last_diagnostic_list_ns = 0
local last_diagnostic_list_result
local pending_problems_focus = false
local terminal_session_statuscolumn_expr = "%@v:lua.NvChadBottomPaneTerminalSessionClick@%{%v:lua.NvChadBottomPaneTerminalSessionStatusColumn()%}%T"
local terminal_session_winhighlight = table.concat({
  "Normal:BottomPaneTerminalSessionBase",
  "NormalNC:BottomPaneTerminalSessionBase",
  "EndOfBuffer:BottomPaneTerminalSessionBase",
  "LineNr:BottomPaneTerminalSessionBase",
  "CursorLine:BottomPaneTerminalSessionBase",
  "CursorLineNr:BottomPaneTerminalSessionBase",
  "SignColumn:BottomPaneTerminalSessionBase",
  "FoldColumn:BottomPaneTerminalSessionBase",
}, ",")

local function note_diagnostic_response()
  diagnostics_response_received = true
end

local function stop_timer(timer)
  if not timer then
    return
  end

  pcall(function()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end)
end

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function highlight_with_background(groups)
  for _, group in ipairs(groups) do
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    if ok and (hl.bg or hl.ctermbg) then
      return group
    end
  end

  return groups[#groups]
end

local function default_link(name, target)
  pcall(vim.api.nvim_set_hl, 0, name, {
    default = true,
    link = target,
  })
end

local function setup_terminal_session_highlights()
  default_link("BottomPaneTerminalSessionBase", "Normal")
  default_link("BottomPaneTerminalSessionInactive", "Comment")
  default_link("BottomPaneTerminalSessionActive", highlight_with_background({
    "PmenuSel",
    "Visual",
    "TabLineSel",
  }))
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

local function set_window_buffer(win, buf)
  if not is_valid_win(win) or not is_valid_buf(buf) then
    return false
  end

  local locked = false
  if vim.fn.exists("+winfixbuf") == 1 then
    local ok, value = pcall(vim.api.nvim_get_option_value, "winfixbuf", { win = win })
    locked = ok and value == true
    if locked then
      pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { scope = "local", win = win })
    end
  end

  local ok = pcall(vim.api.nvim_win_set_buf, win, buf)
  if locked then
    pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { scope = "local", win = win })
  end
  return ok
end

local function mark_bottom_pane_window(win, kind)
  if is_valid_win(win) and kind then
    vim.w[win].bottom_pane_kind = kind
    bottom_win = win
    active_kind = kind
  end
end

local function clear_bottom_pane_window(win)
  if win and is_valid_win(win) then
    vim.w[win].bottom_pane_kind = nil
  end

  if not win or win == bottom_win then
    bottom_win = nil
    active_kind = nil
  end
end

local function is_bottom_pane_winbar(win)
  return is_valid_win(win) and vim.wo[win].winbar:find(winbar_marker, 1, true) ~= nil
end

local function clear_bottom_pane_winbar(win)
  if is_bottom_pane_winbar(win) then
    vim.wo[win].winbar = ""
  end
end

local function set_winbar(win, active)
  if not is_valid_win(win) then
    return
  end

  local terminal_hl = active == "terminal" and "%#TabLineSel#" or "%#TabLine#"
  local problems_hl = active == "problems" and "%#TabLineSel#" or "%#TabLine#"
  local problems_label = ""
  if problems_loading then
    problems_label = " (...)"
  elseif problem_count > 0 then
    problems_label = string.format(" (%d)", problem_count)
  end

  vim.wo[win].winbar = table.concat {
    terminal_hl,
    "%@v:lua.NvChadBottomPaneTerminal@ Terminal %X",
    problems_hl,
    string.format("%%@v:lua.NvChadBottomPaneProblems@ Problems%s %%X", problems_label),
    "%#TabLineFill#",
  }
end

function _G.NvChadBottomPaneTerminal()
  require("configs.bottom_pane").open_terminal()
end

function _G.NvChadBottomPaneProblems()
  require("configs.bottom_pane").open_problems()
end

function _G.NvChadBottomPaneTerminalSessionStatusColumn()
  return require("configs.bottom_pane").terminal_session_statuscolumn()
end

function _G.NvChadBottomPaneTerminalSessionClick()
  return require("configs.bottom_pane").terminal_session_click()
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

local function find_editor_window()
  local current_win = vim.api.nvim_get_current_win()
  if is_editor_window(current_win) then
    return current_win
  end

  local previous_win = vim.fn.win_getid(vim.fn.winnr "#")
  if is_editor_window(previous_win) then
    return previous_win
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_editor_window(win) then
      return win
    end
  end
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
  local win = find_editor_window()
  if win then
    vim.api.nvim_set_current_win(win)
  end

  return win
end

local sync_active_terminal

local function sort_terminal_order()
  table.sort(terminal_order, function(a, b)
    return a < b
  end)
end

local function lowest_available_terminal_id()
  local id = 1
  while terminal_sessions[id] do
    id = id + 1
  end
  return id
end

local function remove_ordered_terminal(id)
  for index, session_id in ipairs(terminal_order) do
    if session_id == id then
      table.remove(terminal_order, index)
      return index
    end
  end
end

local function terminal_session_for_buf(buf)
  if not is_valid_buf(buf) then
    return nil
  end

  for _, session in pairs(terminal_sessions) do
    if session.buf == buf then
      return session
    end
  end
end

local function is_terminal_session_buf(buf)
  return terminal_session_for_buf(buf) ~= nil
end

local function forget_terminal_session_buf(buf)
  local session = terminal_session_for_buf(buf)
  if not session then
    return
  end

  terminal_sessions[session.id] = nil
  remove_ordered_terminal(session.id)
  if active_terminal_id == session.id then
    sync_active_terminal()
  end
end

function sync_active_terminal()
  local session = active_terminal_id and terminal_sessions[active_terminal_id] or nil
  if session and is_valid_buf(session.buf) then
    terminal_buf = session.buf
    terminal_chan = session.chan
    return session
  end

  terminal_buf = nil
  terminal_chan = nil
  active_terminal_id = nil
  for _, id in ipairs(terminal_order) do
    session = terminal_sessions[id]
    if session and is_valid_buf(session.buf) then
      active_terminal_id = id
      terminal_buf = session.buf
      terminal_chan = session.chan
      return session
    end
  end
end

local function active_terminal_session()
  return sync_active_terminal()
end

local function session_label(label)
  if #label >= terminal_session_width then
    return label
  end

  local left = math.floor((terminal_session_width - #label) / 2)
  local right = terminal_session_width - #label - left
  return string.rep(" ", left) .. label .. string.rep(" ", right)
end

local function terminal_session_row_for_lnum(lnum)
  local first = tonumber(vim.fn.line "w0") or 1
  return tonumber(lnum) and (tonumber(lnum) - first + 1) or nil
end

local function terminal_session_id_for_view_row(row)
  row = tonumber(row)
  if not row or row < 1 then
    return nil
  end
  local id = terminal_order[row]
  if id and terminal_sessions[id] then
    return id
  end
end

local function render_terminal_session_statuscolumn()
  local row = terminal_session_row_for_lnum(vim.v.lnum)
  local id = terminal_session_id_for_view_row(row)
  if not id then
    return ""
  end

  local highlight = id == active_terminal_id and "%#BottomPaneTerminalSessionActive#" or "%#BottomPaneTerminalSessionInactive#"
  return highlight .. session_label(string.format("(%d)", id)) .. "%*"
end

local function close_terminal_windows()
  if #terminal_order == 0 then
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_valid_win(win) and is_terminal_session_buf(vim.api.nvim_win_get_buf(win)) then
      clear_bottom_pane_window(win)
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
      clear_bottom_pane_window(win)
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

local function find_terminal_window()
  for _, id in ipairs(terminal_order) do
    local session = terminal_sessions[id]
    local win = session and find_window_for_buf(session.buf)
    if win then
      return win
    end
  end
end

local function close_trouble()
  local ok, trouble = pcall(require, "trouble")
  if not ok then
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_valid_win(win) and vim.w[win].bottom_pane_kind == "problems" then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "trouble" then
        clear_bottom_pane_window(win)
      end
    end
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
  return find_terminal_window() ~= nil or find_window_for_buf(empty_problems_buf) ~= nil or trouble_is_open()
end

local function problems_pane_is_open()
  return active_kind == "problems" or find_window_for_buf(empty_problems_buf) ~= nil or trouble_is_open()
end

local function current_window_is_problems_pane()
  local win = vim.api.nvim_get_current_win()
  if not is_valid_win(win) then
    return false
  end

  if vim.w[win].bottom_pane_kind == "problems" then
    return true
  end

  local buf = vim.api.nvim_win_get_buf(win)
  return buf == empty_problems_buf or vim.bo[buf].filetype == "trouble"
end

local function configure_problem_window(win)
  if not is_valid_win(win) then
    return
  end

  for option, value in pairs {
    breakindent = false,
    linebreak = false,
    smoothscroll = false,
    wrap = false,
  } do
    pcall(vim.api.nvim_set_option_value, option, value, { scope = "local", win = win })
  end
  pcall(vim.api.nvim_set_option_value, "statuscolumn", "", { scope = "local", win = win })
end

local function configure_terminal_window(win)
  if not is_valid_win(win) then
    return
  end

  mark_bottom_pane_window(win, "terminal")
  lock_window_to_buffer(win)
  pcall(vim.api.nvim_set_option_value, "number", true, { scope = "local", win = win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { scope = "local", win = win })
  pcall(vim.api.nvim_set_option_value, "numberwidth", terminal_session_width, { scope = "local", win = win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { scope = "local", win = win })
  pcall(vim.api.nvim_set_option_value, "foldcolumn", "0", { scope = "local", win = win })
  pcall(vim.api.nvim_set_option_value, "statuscolumn", terminal_session_statuscolumn_expr, { scope = "local", win = win })
  pcall(vim.api.nvim_set_option_value, "cursorline", false, { scope = "local", win = win })
  pcall(vim.api.nvim_set_option_value, "winhighlight", terminal_session_winhighlight, { scope = "local", win = win })
end

local function get_problem_window_option(win, option, fallback)
  local ok, value = pcall(vim.api.nvim_get_option_value, option, { scope = "local", win = win })
  return ok and value or fallback
end

local function set_problem_window_option(win, option, value)
  pcall(vim.api.nvim_set_option_value, option, value, { scope = "local", win = win })
end

local function set_problem_virtualedit_for_scroll(win, enabled)
  if enabled then
    if not vim.w[win].bottom_pane_previous_virtualedit then
      vim.w[win].bottom_pane_previous_virtualedit = get_problem_window_option(win, "virtualedit", "")
    end

    set_problem_window_option(win, "virtualedit", "all")
    return
  end

  local previous = vim.w[win].bottom_pane_previous_virtualedit
  if previous ~= nil then
    set_problem_window_option(win, "virtualedit", previous == "" and "none" or previous)
    vim.w[win].bottom_pane_previous_virtualedit = nil
  end
end

local function window_text_width(win)
  return math.max(1, vim.api.nvim_win_get_width(win) - (tonumber(vim.wo[win].sidescrolloff) or 0))
end

local function line_end_virtual_column(lnum)
  return math.max(1, (tonumber(vim.fn.virtcol({ lnum, "$" })) or 1) - 1)
end

local function current_buffer_widest_line()
  local widest = 1

  for lnum = 1, vim.api.nvim_buf_line_count(0) do
    local width = line_end_virtual_column(lnum)
    if width > widest then
      widest = width
    end
  end

  return widest
end

local function max_window_leftcol(win)
  return math.max(0, current_buffer_widest_line() - window_text_width(win))
end

local function cursor_for_problem_virtual_column(win, lnum, virtual_column)
  virtual_column = math.max(1, math.floor(virtual_column))

  local byte_column = tonumber(vim.fn.virtcol2col(win, lnum, virtual_column)) or 0
  if byte_column < 1 then
    return 1, virtual_column - 1, virtual_column - 1
  end

  local actual_virtual_column = tonumber(vim.fn.virtcol({ lnum, byte_column })) or virtual_column
  local coladd = math.max(0, virtual_column - actual_virtual_column)
  return byte_column, coladd, virtual_column - 1
end

local function drag_problem_cursor_into_view(win, view, target_leftcol)
  local width = window_text_width(win)
  local margin = math.min(tonumber(vim.wo[win].sidescrolloff) or 0, math.floor(width / 3))
  local left_bound = target_leftcol + margin + 1
  local right_bound = math.max(left_bound, target_leftcol + width - margin)
  local cursor_virtual_column = tonumber(vim.fn.virtcol ".") or 1
  local target_virtual_column

  if cursor_virtual_column < left_bound then
    target_virtual_column = left_bound
  elseif cursor_virtual_column > right_bound then
    target_virtual_column = target_leftcol == 0 and math.min(right_bound, line_end_virtual_column(vim.fn.line ".")) or right_bound
  else
    return
  end

  local lnum = vim.fn.line "."
  local byte_column, coladd, curswant = cursor_for_problem_virtual_column(win, lnum, target_virtual_column)
  set_problem_virtualedit_for_scroll(win, coladd > 0)

  view.lnum = lnum
  view.col = byte_column - 1
  view.coladd = coladd
  view.curswant = curswant
end

local function scroll_window_horizontally(win, columns)
  if not is_valid_win(win) then
    return
  end

  vim.api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    local target_leftcol = math.min(max_window_leftcol(win), math.max(0, (tonumber(view.leftcol) or 0) + columns))
    drag_problem_cursor_into_view(win, view, target_leftcol)
    view.leftcol = target_leftcol
    vim.fn.winrestview(view)
  end)
end

local function refresh_winbars(active)
  active = active or active_kind

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local kind = vim.w[win].bottom_pane_kind

    if is_terminal_session_buf(buf) then
      kind = "terminal"
      local session = terminal_session_for_buf(buf)
      if session then
        active_terminal_id = session.id
        sync_active_terminal()
      end
      configure_terminal_window(win)
      set_winbar(win, active == kind and kind or nil)
    elseif buf == empty_problems_buf or (kind == "problems" and vim.bo[buf].filetype == "trouble") then
      kind = "problems"
      lock_window_to_buffer(win)
      configure_problem_window(win)
      mark_bottom_pane_window(win, kind)
      set_winbar(win, active == kind and kind or nil)
    elseif kind == "problems" and vim.bo[buf].buftype == "quickfix" then
      lock_window_to_buffer(win)
      configure_problem_window(win)
      set_winbar(win, active == kind and kind or nil)
    else
      clear_bottom_pane_winbar(win)
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
    vim.api.nvim_buf_set_lines(empty_problems_buf, 0, -1, false, {})
    vim.bo[empty_problems_buf].modifiable = false
  end

  return empty_problems_buf
end

local function set_empty_problems_content(kind)
  local buf = ensure_empty_problems_buf()
  local lines

  if kind == "loading" then
    problems_loading = true
    problem_count = 0
    lines = {
      "Waiting for CoC to finish running diagnostics...",
      "",
      "Diagnostics will appear here when available.",
    }
  else
    problems_loading = false
    problem_count = 0
    lines = {
      "No problems.",
      "",
      "Diagnostics will appear here when available.",
    }
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  refresh_winbars("problems")
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
  vim.wo[win].statuscolumn = ""
  lock_window_to_buffer(win)
  mark_bottom_pane_window(win, active)
  set_winbar(win, active)

  return win
end

local function prepare_terminal_window(buf)
  local win = find_terminal_window()
  if win then
    set_window_buffer(win, buf)
  else
    win = open_bottom_window(buf, "terminal")
  end

  vim.api.nvim_set_current_win(win)
  configure_terminal_window(win)
  set_winbar(win, "terminal")
  return win
end

local function create_terminal_session(cmd)
  local id = lowest_available_terminal_id()
  local buf = vim.api.nvim_create_buf(false, true)
  local session = {
    id = id,
    buf = buf,
    chan = nil,
  }

  terminal_sessions[id] = session
  table.insert(terminal_order, id)
  sort_terminal_order()
  active_terminal_id = id
  sync_active_terminal()

  local win = prepare_terminal_window(buf)
  local chan
  vim.api.nvim_win_call(win, function()
    chan = vim.fn.termopen(vim.o.shell)
  end)

  session.chan = chan
  terminal_buf = buf
  terminal_chan = chan

  vim.bo[buf].buflisted = false
  vim.b[buf].bottom_pane_kind = "terminal"
  configure_terminal_window(win)

  if cmd and cmd ~= "" then
    pcall(vim.api.nvim_chan_send, chan, cmd .. "\n")
  end

  return session, win
end

local function ensure_terminal_session()
  local session = active_terminal_session()
  if session and is_valid_buf(session.buf) and vim.bo[session.buf].buftype == "terminal" then
    return session
  end

  for _, id in ipairs(terminal_order) do
    session = terminal_sessions[id]
    if session and is_valid_buf(session.buf) and vim.bo[session.buf].buftype == "terminal" then
      active_terminal_id = id
      return sync_active_terminal()
    end
  end

  return create_terminal_session()
end

function M.select_terminal(id)
  id = tonumber(id)
  local session = id and terminal_sessions[id] or nil
  if not session or not is_valid_buf(session.buf) then
    return false
  end

  pending_problems_focus = false
  close_trouble()
  close_empty_problems_windows()

  active_terminal_id = id
  sync_active_terminal()
  local win = find_window_for_buf(session.buf) or prepare_terminal_window(session.buf)
  vim.api.nvim_set_current_win(win)
  set_window_buffer(win, session.buf)
  configure_terminal_window(win)
  set_winbar(win, "terminal")
  refresh_winbars("terminal")
  vim.cmd "startinsert"
  return true
end

function M.open_terminal(cmd)
  pending_problems_focus = false
  close_trouble()
  close_empty_problems_windows()

  local session = ensure_terminal_session()
  if not session then
    return
  end

  local win = find_window_for_buf(session.buf) or prepare_terminal_window(session.buf)
  vim.api.nvim_set_current_win(win)
  set_window_buffer(win, session.buf)
  configure_terminal_window(win)
  set_winbar(win, "terminal")
  refresh_winbars("terminal")

  if cmd and cmd ~= "" then
    local chan = vim.bo[session.buf].channel or session.chan
    pcall(vim.api.nvim_chan_send, chan, cmd .. "\n")
  end

  vim.cmd "startinsert"
end

function M.new_terminal(cmd)
  pending_problems_focus = false
  close_trouble()
  close_empty_problems_windows()

  create_terminal_session(cmd)
  refresh_winbars("terminal")
  vim.cmd "startinsert"
end

function M.next_terminal()
  if #terminal_order == 0 then
    M.open_terminal()
    return
  end

  local current_index = 1
  for index, id in ipairs(terminal_order) do
    if id == active_terminal_id then
      current_index = index
      break
    end
  end

  local next_index = current_index % #terminal_order + 1
  M.select_terminal(terminal_order[next_index])
end

function M.prev_terminal()
  if #terminal_order == 0 then
    M.open_terminal()
    return
  end

  local current_index = 1
  for index, id in ipairs(terminal_order) do
    if id == active_terminal_id then
      current_index = index
      break
    end
  end

  local prev_index = current_index == 1 and #terminal_order or current_index - 1
  M.select_terminal(terminal_order[prev_index])
end

function M.close_current_terminal()
  local session = active_terminal_session()
  if not session then
    return false
  end

  local id = session.id
  local win = find_window_for_buf(session.buf) or find_terminal_window()
  local removed_index = remove_ordered_terminal(id) or 1
  terminal_sessions[id] = nil

  local next_id = terminal_order[removed_index] or terminal_order[removed_index - 1] or terminal_order[1]
  if session.chan then
    pcall(vim.fn.jobstop, session.chan)
  end

  if next_id and terminal_sessions[next_id] then
    active_terminal_id = next_id
    local next_session = sync_active_terminal()
    if is_valid_win(win) and next_session then
      set_window_buffer(win, next_session.buf)
      vim.api.nvim_set_current_win(win)
      configure_terminal_window(win)
      set_winbar(win, "terminal")
      refresh_winbars("terminal")
      vim.cmd "startinsert"
    end
  else
    active_terminal_id = nil
    terminal_buf = nil
    terminal_chan = nil
    if is_valid_win(win) then
      clear_bottom_pane_window(win)
      pcall(vim.api.nvim_win_close, win, true)
    end
    refresh_winbars()
  end

  if is_valid_buf(session.buf) then
    pcall(vim.api.nvim_buf_delete, session.buf, { force = true })
  end

  return true
end

function M.terminal_session_statuscolumn()
  return render_terminal_session_statuscolumn()
end

function M.terminal_session_click()
  local pos = vim.fn.getmousepos()
  if not pos or not is_valid_win(pos.winid) or vim.w[pos.winid].bottom_pane_kind ~= "terminal" then
    return
  end

  local row = vim.api.nvim_win_call(pos.winid, function()
    local first = tonumber(vim.fn.line "w0") or 1
    return (tonumber(pos.line) or first) - first + 1
  end)
  local id = terminal_session_id_for_view_row(row)
  if id then
    M.select_terminal(id)
  end
end

local function diagnostic_type(severity)
  local numeric_severity = tonumber(severity)
  if numeric_severity == 1 then
    return "E"
  elseif numeric_severity == 2 then
    return "W"
  elseif numeric_severity == 3 then
    return "I"
  elseif numeric_severity == 4 then
    return "H"
  end

  severity = tostring(severity or ""):lower()

  if severity:find "error" then
    return "E"
  elseif severity:find "warning" then
    return "W"
  elseif severity:find "information" or severity:find "info" then
    return "I"
  elseif severity:find "hint" then
    return "H"
  end

  return "N"
end

local function normalize_file(path)
  if not path or path == "" then
    return nil
  end

  return vim.fn.fnamemodify(path, ":p")
end

local function normalize_diagnostic_source(source)
  return tostring(source or ""):lower()
end

local function diagnostic_source(item)
  return item.source and item.source ~= "" and item.source or "coc"
end

local function diagnostic_message(item)
  return tostring(item.message or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function register_conflicting_diagnostic_source(source, conflicts)
  local source_key = normalize_diagnostic_source(source)
  if source_key == "" or type(conflicts) ~= "table" then
    return
  end

  diagnostic_source_conflicts[source_key] = diagnostic_source_conflicts[source_key] or {}
  for _, conflict in ipairs(conflicts) do
    local conflict_key = normalize_diagnostic_source(conflict)
    if conflict_key ~= "" then
      diagnostic_source_conflicts[source_key][conflict_key] = true
    end
  end
end

register_conflicting_diagnostic_source("local:pyright", { "Pyright" })

local function diagnostic_file(item)
  local file = normalize_file(item.file)
  if file then
    return file
  end

  local bufnr = tonumber(item.bufnr)
  if bufnr and is_valid_buf(bufnr) then
    return normalize_file(vim.api.nvim_buf_get_name(bufnr))
  end
end

local function diagnostic_conflict_key(item)
  return table.concat({
    diagnostic_file(item) or "",
    tostring(tonumber(item.lnum) or 0),
    tostring(tonumber(item.col) or 0),
    diagnostic_message(item),
  }, "\31")
end

local function current_editor_buf()
  local win = find_editor_window()
  return win and vim.api.nvim_win_get_buf(win) or nil
end

local function current_editor_file()
  local buf = current_editor_buf()
  return buf and normalize_file(vim.api.nvim_buf_get_name(buf)) or nil
end

local function listed_file_buffer_items()
  local items = {}

  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local buf = tonumber(info.bufnr)
    local file = normalize_file(info.name)

    if buf and file and vim.api.nvim_buf_is_valid(buf) and vim.fn.filereadable(file) == 1 then
      local ok, buftype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = buf })
      if ok and buftype == "" then
        table.insert(items, { buf = buf, file = file })
      end
    end
  end

  return items
end

local function listed_file_buffers()
  local files = {}

  for _, item in ipairs(listed_file_buffer_items()) do
    files[item.file] = true
  end

  return files
end

local function diagnostic_is_in_scope(item, scope, current_buf, current_file)
  local item_file = normalize_file(item.file)

  if scope == "current" then
    return (item.bufnr and current_buf and item.bufnr == current_buf) or (item_file and item_file == current_file)
  end

  return true
end

local function sort_diagnostics(diagnostics)
  table.sort(diagnostics, function(a, b)
    local a_level = tonumber(a.level) or 0
    local b_level = tonumber(b.level) or 0
    if a_level ~= b_level then
      return a_level < b_level
    end

    local a_file = normalize_file(a.file) or ""
    local b_file = normalize_file(b.file) or ""
    if a_file ~= b_file then
      return a_file < b_file
    end

    local a_lnum = tonumber(a.lnum) or 0
    local b_lnum = tonumber(b.lnum) or 0
    if a_lnum ~= b_lnum then
      return a_lnum < b_lnum
    end

    return (tonumber(a.col) or 0) < (tonumber(b.col) or 0)
  end)

  return diagnostics
end

local function diagnostics_from_buffer_var(buf)
  if not is_valid_buf(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return nil
  end

  local file = normalize_file(vim.api.nvim_buf_get_name(buf))
  if not file then
    return nil
  end

  local ok, diagnostics = pcall(vim.api.nvim_buf_get_var, buf, "coc_diagnostic_map")
  if not ok or type(diagnostics) ~= "table" then
    return nil
  end

  local items = {}
  for _, item in ipairs(diagnostics) do
    if type(item) == "table" then
      local copy = vim.tbl_extend("force", {}, item)
      copy.file = normalize_file(copy.file) or file
      copy.bufnr = copy.bufnr or buf
      table.insert(items, copy)
    end
  end

  if #items == 0 then
    return nil
  end

  return items
end

local function buffer_diagnostic_count(buf)
  if not is_valid_buf(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return nil
  end

  local ok, info = pcall(vim.api.nvim_buf_get_var, buf, "coc_diagnostic_info")
  if not ok or type(info) ~= "table" then
    return nil
  end

  if type(info.total) == "number" then
    return info.total
  end

  local total = 0
  for _, key in ipairs { "error", "warning", "information", "hint" } do
    total = total + (tonumber(info[key]) or 0)
  end

  return total
end

local function update_cache_from_buffer(buf, clear_missing)
  if not is_valid_buf(buf) or not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= "" then
    return false
  end

  local file = normalize_file(vim.api.nvim_buf_get_name(buf))
  if not file then
    return false
  end

  local diagnostics = diagnostics_from_buffer_var(buf)
  if diagnostics then
    diagnostic_cache[file] = diagnostics

    return true
  elseif clear_missing and buffer_diagnostic_count(buf) == 0 then
    diagnostic_cache[file] = nil
    return true
  end

  return false
end

local function sync_cache_from_buffer_vars(clear_missing)
  for _, item in ipairs(listed_file_buffer_items()) do
    update_cache_from_buffer(item.buf, clear_missing)
  end
end

local function prune_diagnostic_cache_to_open_buffers()
  local open_files = listed_file_buffers()
  local changed = false

  for file in pairs(diagnostic_cache) do
    if not open_files[file] then
      diagnostic_cache[file] = nil
      changed = true
    end
  end

  return changed
end

local function update_diagnostic_cache(diagnostics)
  local open_files = listed_file_buffers()
  local grouped = {}

  prune_diagnostic_cache_to_open_buffers()

  for _, item in ipairs(diagnostics) do
    local file = normalize_file(item.file)
    if file and open_files[file] then
      grouped[file] = grouped[file] or {}
      table.insert(grouped[file], item)
    end
  end

  for file, items in pairs(grouped) do
    diagnostic_cache[file] = items
  end
end

local function cached_diagnostics()
  local items = {}

  for _, diagnostics in pairs(diagnostic_cache) do
    vim.list_extend(items, diagnostics)
  end

  return sort_diagnostics(items)
end

local function diagnostics_for_scope(diagnostics)
  sync_cache_from_buffer_vars(false)
  update_diagnostic_cache(diagnostics)

  local current_buf = current_editor_buf()
  local current_file = current_buf and normalize_file(vim.api.nvim_buf_get_name(current_buf)) or nil
  local current_has_global_diagnostics = false
  local current_diagnostics = {}

  if current_file then
    for _, item in ipairs(diagnostics) do
      if diagnostic_is_in_scope(item, "current", current_buf, current_file) then
        table.insert(current_diagnostics, item)
      end

      if normalize_file(item.file) == current_file then
        current_has_global_diagnostics = true
      end
    end
  end

  if current_file and not current_has_global_diagnostics and buffer_diagnostic_count(current_buf) == 0 then
    diagnostic_cache[current_file] = nil
  end

  if problems_scope == "open" then
    return cached_diagnostics()
  end

  return sort_diagnostics(current_diagnostics)
end

local function coc_ready()
  return vim.fn.exists "*CocAction" == 1 and vim.g.coc_service_initialized == 1
end

local function sync_local_diagnostic_adapter_metadata()
  if diagnostic_source_conflicts_loaded or not coc_ready() then
    return
  end

  local ok, local_diagnostics = pcall(require, "configs.local_diagnostics")
  if not ok or type(local_diagnostics.adapters) ~= "function" then
    return
  end

  local result = local_diagnostics.adapters()
  if type(result) ~= "table" or result.ok == false or type(result.adapters) ~= "table" then
    return
  end

  diagnostic_source_conflicts_loaded = true

  for _, adapter in ipairs(result.adapters) do
    if type(adapter) == "table" then
      register_conflicting_diagnostic_source(adapter.source, adapter.conflictsWithSources)
    end
  end
end

local function suppress_conflicting_diagnostics(diagnostics)
  sync_local_diagnostic_adapter_metadata()

  local covered = {}
  for _, item in ipairs(diagnostics) do
    local conflicts = diagnostic_source_conflicts[normalize_diagnostic_source(diagnostic_source(item))]
    if conflicts then
      local key = diagnostic_conflict_key(item)
      covered[key] = covered[key] or {}
      for conflict_source in pairs(conflicts) do
        covered[key][conflict_source] = true
      end
    end
  end

  if vim.tbl_isempty(covered) then
    return diagnostics
  end

  local filtered = {}
  for _, item in ipairs(diagnostics) do
    local source = normalize_diagnostic_source(diagnostic_source(item))
    local conflicts_for_key = covered[diagnostic_conflict_key(item)]
    if not (conflicts_for_key and conflicts_for_key[source]) then
      table.insert(filtered, item)
    end
  end

  return filtered
end

local function set_qflist_from_diagnostics(diagnostics)
  diagnostics = suppress_conflicting_diagnostics(diagnostics)

  local items = {}
  for _, item in ipairs(diagnostics) do
    local source = diagnostic_source(item)
    local message = diagnostic_message(item)

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

  if #items > 0 then
    note_diagnostic_response()
  end

  problem_count = #items
  refresh_winbars()
  last_diagnostic_list_result = #items > 0

  return last_diagnostic_list_result
end

local function cached_diagnostics_for_scope()
  sync_cache_from_buffer_vars(false)

  local diagnostics = cached_diagnostics()
  if problems_scope == "open" then
    return diagnostics
  end

  local current_buf = current_editor_buf()
  local current_file = current_buf and normalize_file(vim.api.nvim_buf_get_name(current_buf)) or nil
  local current_diagnostics = {}

  if not current_file then
    return current_diagnostics
  end

  for _, item in ipairs(diagnostics) do
    if diagnostic_is_in_scope(item, "current", current_buf, current_file) then
      table.insert(current_diagnostics, item)
    end
  end

  return sort_diagnostics(current_diagnostics)
end

local function update_qflist_from_cached_diagnostics()
  local diagnostics = cached_diagnostics_for_scope()
  if #diagnostics == 0 then
    return false
  end

  return set_qflist_from_diagnostics(diagnostics)
end

local function update_coc_qflist(opts)
  opts = opts or {}

  if vim.fn.exists "*CocAction" == 0 then
    if not opts.silent then
      vim.notify("coc.nvim is not loaded yet", vim.log.levels.WARN)
    end
    return nil
  end

  if not coc_ready() then
    if not opts.silent then
      vim.notify("coc.nvim is still starting; try :Problems again in a moment", vim.log.levels.WARN)
    end
    return nil
  end

  if reading_coc_diagnostics then
    return last_diagnostic_list_result
  end

  local uv = vim.uv or vim.loop
  local now = uv and uv.hrtime() or 0
  if not opts.force and now > 0 and last_diagnostic_list_ns > 0 and (now - last_diagnostic_list_ns) < 150000000 then
    return last_diagnostic_list_result
  end

  reading_coc_diagnostics = true
  local ok, diagnostics = pcall(vim.fn.CocAction, "diagnosticList")
  reading_coc_diagnostics = false
  last_diagnostic_list_ns = now

  if not ok then
    if not opts.silent then
      vim.notify("Could not read CoC diagnostics", vim.log.levels.WARN)
    end
    return nil
  end

  if type(diagnostics) ~= "table" then
    diagnostics = {}
  end

  diagnostics = diagnostics_for_scope(diagnostics)
  return set_qflist_from_diagnostics(diagnostics)
end

local function refresh_problem_state_soon(delay)
  if pending_problem_refresh then
    return
  end

  pending_problem_refresh = vim.defer_fn(function()
    pending_problem_refresh = nil

    if problems_pane_is_open() then
      M.refresh_problems({ silent = true })
    end
  end, delay or 150)
end

local function prepare_buffer_for_diagnostics(buf)
  return is_valid_buf(buf) and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == ""
end

local function request_coc_diagnostic_refresh()
  if not coc_ready() or vim.fn.exists "*CocActionAsync" == 0 then
    return false
  end

  local uv = vim.uv or vim.loop
  if uv then
    local now = uv.hrtime()
    if diagnostic_refresh_requested_until > now then
      return true
    end
    diagnostic_refresh_requested_until = now + 1500000000
  end

  local ok = pcall(vim.fn.CocActionAsync, "diagnosticRefresh")
  return ok
end

local function request_local_diagnostic_refresh()
  local uv = vim.uv or vim.loop
  if uv then
    local now = uv.hrtime()
    if local_diagnostic_refresh_requested_until > now then
      return waiting_for_local_diagnostics
    end
    local_diagnostic_refresh_requested_until = now + 2000000000
  end

  local ok, local_diagnostics = pcall(require, "configs.local_diagnostics")
  if not ok or type(local_diagnostics.refresh_open) ~= "function" then
    return false
  end

  local ok = local_diagnostics.refresh_open()
  if ok then
    waiting_for_local_diagnostics = true
    waiting_for_local_diagnostics_epoch = local_diagnostics_epoch
  end

  return ok
end

local function clear_local_diagnostics_for_file(file)
  if not file then
    return
  end

  local ok, local_diagnostics = pcall(require, "configs.local_diagnostics")
  if not ok or type(local_diagnostics.clear) ~= "function" then
    return
  end

  pcall(local_diagnostics.clear, file)
end

local function clear_all_local_diagnostics()
  local ok, local_diagnostics = pcall(require, "configs.local_diagnostics")
  if not ok or type(local_diagnostics.clear) ~= "function" then
    return false
  end

  local ok_clear, result = pcall(local_diagnostics.clear)
  return ok_clear and type(result) == "table"
end

local function remove_buffer_diagnostics(buf, file)
  file = normalize_file(file)
  if not file and is_valid_buf(buf) then
    file = normalize_file(vim.api.nvim_buf_get_name(buf))
  end

  if file then
    diagnostic_cache[file] = nil
    clear_local_diagnostics_for_file(file)
  end

  prune_diagnostic_cache_to_open_buffers()

  if problems_pane_is_open() then
    refresh_problem_state_soon(10)
  end
end

local function schedule_buffer_diagnostic_reload(buf)
  if pending_buffer_refreshes[buf] then
    return
  end

  pending_buffer_refreshes[buf] = vim.defer_fn(function()
    pending_buffer_refreshes[buf] = nil

    if not is_valid_buf(buf) then
      return
    end

    if not prepare_buffer_for_diagnostics(buf) then
      return
    end

    request_coc_diagnostic_refresh()
    request_local_diagnostic_refresh()

    vim.defer_fn(function()
      update_cache_from_buffer(buf, true)
      refresh_problem_state_soon(200)
    end, 500)

    vim.defer_fn(function()
      update_cache_from_buffer(buf, true)
      refresh_problem_state_soon(200)
    end, 1500)

    vim.defer_fn(function()
      update_cache_from_buffer(buf, true)
      refresh_problem_state_soon(200)
    end, 3000)
  end, 120)
end

local function schedule_problem_refreshes()
  pending_problem_poll_generation = pending_problem_poll_generation + 1
  local generation = pending_problem_poll_generation

  for _, delay in ipairs({ 500, 1200, 2500, 4500, 7000 }) do
    vim.defer_fn(function()
      if generation ~= pending_problem_poll_generation then
        return
      end

      if problems_pane_is_open() then
        request_local_diagnostic_refresh()
        sync_cache_from_buffer_vars(false)
        M.refresh_problems({ silent = true })
      end
    end, delay)
  end
end

function M.refresh_open_file_diagnostics()
  if not problems_pane_is_open() then
    return false
  end

  if not coc_ready() then
    return false
  end

  request_coc_diagnostic_refresh()
  request_local_diagnostic_refresh()
  sync_cache_from_buffer_vars(false)
  schedule_problem_refreshes()

  return true
end

local function start_problem_diagnostics(delay, attempts, opts)
  attempts = attempts or 0
  opts = opts or {}

  if not problems_pane_is_open() then
    return
  end

  if not opts.background then
    problems_loading = true
    diagnostics_response_received = false
    waiting_for_local_diagnostics = false
    waiting_for_local_diagnostics_epoch = nil
    refresh_winbars("problems")
  end

  vim.defer_fn(function()
    if not problems_pane_is_open() then
      return
    end

    if M.refresh_open_file_diagnostics() then
      vim.defer_fn(function()
        if problems_pane_is_open() then
          refresh_problem_state_soon(100)
        end
      end, 900)
    elseif attempts < 40 then
      start_problem_diagnostics(500, attempts + 1, opts)
    end
  end, delay or 0)
end

local function open_trouble_problems(focus)
  local ok, trouble = pcall(require, "trouble")
  if not ok then
    return nil
  end

  local previous_win = vim.api.nvim_get_current_win()
  local anchor_win = find_editor_window() or previous_win
  local view = trouble.open {
    mode = "qflist",
    auto_preview = false,
    focus = focus ~= false,
    multiline = false,
    refresh = true,
    win = {
      type = "split",
      relative = "win",
      position = "bottom",
      size = height,
      win = anchor_win,
      wo = {
        winfixbuf = true,
        wrap = false,
      },
    },
  }

  local function apply_problem_folds()
    if not auto_problem_folds or problems_scope ~= "open" or not view or not view.renderer then
      return
    end

    if current_window_is_problems_pane() then
      return
    end

    local current_file = current_editor_file()
    local folded = {}

    for _, node in ipairs(view.renderer.root_nodes or {}) do
      local node_file = node.item and normalize_file(node.item.filename)
      if current_file and node_file == current_file then
        folded[node.id] = nil
      elseif not node:is_leaf() then
        folded[node.id] = true
      end
    end

    view.renderer._folded = folded
    view:render()
  end

  local function document_trouble_keymaps(win)
    if not is_valid_win(win) then
      return
    end

    local buf = vim.api.nvim_win_get_buf(win)
    vim.keymap.set("n", "s", function()
      if not view then
        return
      end

      local filter = view:get_filter("severity")
      local severity = ((filter and filter.filter.severity or 0) + 1) % 5
      view:filter({ severity = severity }, {
        id = "severity",
        template = "{hl:Title}Filter:{hl} {severity}",
        del = severity == 0,
      })
    end, { buffer = buf, nowait = true, desc = "Problems: cycle severity filter" })

    local function map_horizontal_scroll(lhs, columns, desc)
      vim.keymap.set("n", lhs, function()
        local current_win = vim.api.nvim_get_current_win()
        local target_win = current_window_is_problems_pane() and current_win or win
        scroll_window_horizontally(target_win, columns)
      end, { buffer = buf, nowait = true, desc = desc })
    end

    map_horizontal_scroll("<S-ScrollWheelUp>", -16, "Problems: scroll left")
    map_horizontal_scroll("<S-ScrollWheelDown>", 16, "Problems: scroll right")
    map_horizontal_scroll("<ScrollWheelLeft>", -16, "Problems: scroll left")
    map_horizontal_scroll("<ScrollWheelRight>", 16, "Problems: scroll right")
  end

  local function apply_trouble_winbar()
    local win = view and view.win and view.win.win
    if is_valid_win(win) then
      mark_bottom_pane_window(win, "problems")
      lock_window_to_buffer(win)
      configure_problem_window(win)
      set_winbar(win, "problems")
      document_trouble_keymaps(win)
    end

    apply_problem_folds()
    refresh_winbars("problems")

    if focus ~= false and is_valid_win(win) then
      pcall(vim.api.nvim_set_current_win, win)
    end

    if focus == false and is_valid_win(previous_win) then
      pcall(vim.api.nvim_set_current_win, previous_win)
    end
  end

  if view and view.wait then
    view:wait(apply_trouble_winbar)
  else
    vim.schedule(apply_trouble_winbar)
  end
  vim.defer_fn(apply_trouble_winbar, 50)

  return view
end

local function open_empty_problems(focus, kind)
  local previous_win = vim.api.nvim_get_current_win()
  local buf = ensure_empty_problems_buf()
  set_empty_problems_content(kind)
  local win = find_window_for_buf(buf) or open_bottom_window(buf, "problems")

  mark_bottom_pane_window(win, "problems")
  set_winbar(win, "problems")
  refresh_winbars("problems")

  if focus ~= false then
    vim.api.nvim_set_current_win(win)
  elseif is_valid_win(previous_win) then
    pcall(vim.api.nvim_set_current_win, previous_win)
  end

  return win
end

local function open_cached_problems(focus)
  if not update_qflist_from_cached_diagnostics() then
    return false
  end

  pending_problems_focus = focus ~= false
  problems_loading = false
  diagnostics_response_received = true
  waiting_for_local_diagnostics = false
  waiting_for_local_diagnostics_epoch = nil
  close_empty_problems_windows()

  if not open_trouble_problems(focus) then
    vim.cmd("belowright " .. height .. "copen")
    local win = vim.api.nvim_get_current_win()
    mark_bottom_pane_window(win, "problems")
    lock_window_to_buffer(win)
    set_winbar(win, "problems")

    if focus == false then
      focus_editor_window()
    end
  end

  refresh_winbars("problems")
  return true
end

local function open_cached_qflist_problems(focus)
  local info = vim.fn.getqflist({ title = 1, size = 1 })
  if type(info) ~= "table" or info.title ~= "CoC Problems" or (tonumber(info.size) or 0) == 0 then
    return false
  end

  pending_problems_focus = focus ~= false
  problems_loading = false
  diagnostics_response_received = true
  waiting_for_local_diagnostics = false
  waiting_for_local_diagnostics_epoch = nil
  problem_count = tonumber(info.size) or problem_count
  close_empty_problems_windows()

  if not open_trouble_problems(focus) then
    vim.cmd("belowright " .. height .. "copen")
    local win = vim.api.nvim_get_current_win()
    mark_bottom_pane_window(win, "problems")
    lock_window_to_buffer(win)
    set_winbar(win, "problems")

    if focus == false then
      focus_editor_window()
    end
  end

  refresh_winbars("problems")
  return true
end

function M.open_problems()
  close_terminal_windows()
  close_trouble()
  close_empty_problems_windows()

  pending_problems_focus = true
  if open_cached_problems(true) or open_cached_qflist_problems(true) then
    start_problem_diagnostics(0, 0, { background = true })
    return
  end

  if diagnostics_response_received and last_diagnostic_list_ns > 0 and last_diagnostic_list_result == false then
    open_empty_problems(true, "empty")
    start_problem_diagnostics(0, 0, { background = true })
    return
  end

  open_empty_problems(true, "loading")
  start_problem_diagnostics()
end

function M.refresh_problems(opts)
  opts = opts or {}
  local ok, trouble = pcall(require, "trouble")
  local problems_was_open = active_kind == "problems" or find_window_for_buf(empty_problems_buf) ~= nil or trouble_is_open()
  local focus_problems = pending_problems_focus or current_window_is_problems_pane()
  local has_items = update_coc_qflist(opts)

  if not problems_was_open then
    refresh_winbars()
    return
  end

  if has_items == nil then
    if problem_count > 0 and (trouble_is_open() or #vim.fn.getqflist() > 0) then
      refresh_winbars("problems")
      return
    end

    open_empty_problems(focus_problems, "loading")
    return
  end

  if has_items then
    pending_problems_focus = false
    problems_loading = false
    diagnostics_response_received = true
    waiting_for_local_diagnostics = false
    waiting_for_local_diagnostics_epoch = nil

    if ok and trouble.is_open "qflist" then
      open_trouble_problems(focus_problems)
    else
      close_empty_problems_windows()
      if not open_trouble_problems(focus_problems) then
        vim.cmd("belowright " .. height .. "copen")
        local win = vim.api.nvim_get_current_win()
        mark_bottom_pane_window(win, "problems")
        lock_window_to_buffer(win)
        set_winbar(win, "problems")
        if not focus_problems then
          focus_editor_window()
        end
      end
    end

    refresh_winbars("problems")
    return
  end

  if problems_loading and (waiting_for_local_diagnostics or not diagnostics_response_received) then
    open_empty_problems(focus_problems, "loading")
    return
  end

  pending_problems_focus = false
  problems_loading = false
  waiting_for_local_diagnostics = false
  waiting_for_local_diagnostics_epoch = nil

  if ok and trouble.is_open "qflist" then
    close_trouble()
  end

  open_empty_problems(focus_problems, "empty")
end

function M.set_problems_scope(scope)
  if scope ~= "current" and scope ~= "open" then
    vim.notify("Problems scope must be 'current' or 'open'", vim.log.levels.WARN)
    return
  end

  local changed = problems_scope ~= scope

  if problems_scope == scope then
    if problems_pane_is_open() then
      M.refresh_problems()
    end
    return
  end

  problems_scope = scope
  if problems_pane_is_open() then
    M.refresh_problems()
  end

  if changed then
    vim.notify("Problems scope: " .. (problems_scope == "open" and "all diagnostics" or "current file"))
  end
end

function M.toggle_problems_scope()
  M.set_problems_scope(problems_scope == "current" and "open" or "current")
end

function M.set_auto_problem_folds(enabled)
  enabled = enabled ~= false
  if auto_problem_folds == enabled then
    return
  end

  auto_problem_folds = enabled
  vim.notify("Problems auto folding: " .. (auto_problem_folds and "enabled" or "disabled"))

  if auto_problem_folds and problems_pane_is_open() then
    M.refresh_problems({ silent = true })
  end
end

function M.toggle_auto_problem_folds()
  M.set_auto_problem_folds(not auto_problem_folds)
end

function M.close()
  pending_problems_focus = false
  problems_loading = false
  waiting_for_local_diagnostics = false
  waiting_for_local_diagnostics_epoch = nil
  close_trouble()
  close_terminal_windows()
  close_empty_problems_windows()
  refresh_winbars()
end

function M.reset_diagnostics()
  pending_problem_poll_generation = pending_problem_poll_generation + 1
  stop_timer(pending_problem_refresh)
  pending_problem_refresh = nil

  for buf, timer in pairs(pending_buffer_refreshes) do
    stop_timer(timer)
    pending_buffer_refreshes[buf] = nil
  end

  diagnostic_cache = {}
  problem_count = 0
  problems_loading = false
  diagnostics_response_received = false
  waiting_for_local_diagnostics = false
  waiting_for_local_diagnostics_epoch = nil
  pending_problems_focus = false
  diagnostic_refresh_requested_until = 0
  local_diagnostic_refresh_requested_until = 0
  reading_coc_diagnostics = false
  last_diagnostic_list_ns = 0
  last_diagnostic_list_result = nil

  vim.fn.setqflist({}, "r", {
    title = "CoC Problems",
    items = {},
  })

  if clear_all_local_diagnostics() then
    local_diagnostics_epoch = local_diagnostics_epoch + 1
  end
  refresh_winbars()
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
  setup_terminal_session_highlights()
  M.patch_nvchad_tabufline()

  vim.api.nvim_create_user_command("BottomTerm", function(opts)
    M.open_terminal(opts.args)
  end, { nargs = "*", complete = "shellcmd" })

  vim.api.nvim_create_user_command("BottomTermNew", function(opts)
    M.new_terminal(opts.args)
  end, { nargs = "*", complete = "shellcmd" })

  vim.api.nvim_create_user_command("BottomTermSelect", function(opts)
    M.select_terminal(opts.args)
  end, {
    nargs = 1,
    complete = function()
      local ids = {}
      for _, id in ipairs(terminal_order) do
        table.insert(ids, tostring(id))
      end
      return ids
    end,
  })

  vim.api.nvim_create_user_command("BottomTermNext", function()
    M.next_terminal()
  end, {})

  vim.api.nvim_create_user_command("BottomTermPrev", function()
    M.prev_terminal()
  end, {})

  vim.api.nvim_create_user_command("BottomTermClose", function()
    M.close_current_terminal()
  end, {})

  vim.api.nvim_create_user_command("Problems", function()
    M.open_problems()
  end, {})

  vim.api.nvim_create_user_command("ProblemsScope", function(opts)
    M.set_problems_scope(opts.args)
  end, {
    nargs = 1,
    complete = function()
      return { "current", "open" }
    end,
  })

  vim.api.nvim_create_user_command("ProblemsToggleScope", function()
    M.toggle_problems_scope()
  end, {})

  vim.api.nvim_create_user_command("ProblemsToggleAutoFolds", function()
    M.toggle_auto_problem_folds()
  end, {})

  vim.api.nvim_create_user_command("ProblemsRefreshOpenFiles", function()
    M.refresh_open_file_diagnostics()
  end, {})

  vim.api.nvim_create_user_command("BottomPaneClose", function()
    M.close()
  end, {})

  local group = vim.api.nvim_create_augroup("BottomPane", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = setup_terminal_session_highlights,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      if win == bottom_win then
        problems_loading = false
        waiting_for_local_diagnostics = false
        waiting_for_local_diagnostics_epoch = nil
        clear_bottom_pane_window(win)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload", "BufWipeout" }, {
    group = group,
    callback = function(args)
      local file = args.file
      if (not file or file == "") and is_valid_buf(args.buf) then
        file = vim.api.nvim_buf_get_name(args.buf)
      end

      forget_terminal_session_buf(args.buf)
      pending_buffer_refreshes[args.buf] = nil
      remove_buffer_diagnostics(args.buf, file)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "FileChangedShellPost" }, {
    group = group,
    callback = function(args)
      if not problems_pane_is_open() then
        return
      end

      schedule_buffer_diagnostic_reload(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ExternalFileAutoReload",
    callback = function(args)
      if not problems_pane_is_open() then
        return
      end

      local buf = args.data and tonumber(args.data.bufnr)
      if buf then
        schedule_buffer_diagnostic_reload(buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].buftype ~= "" or vim.bo[args.buf].filetype == "trouble" then
        return
      end

      vim.schedule(function()
        if active_kind == "problems" then
          refresh_problem_state_soon(100)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CocDiagnosticChange",
    callback = function()
      if not problems_pane_is_open() then
        return
      end

      note_diagnostic_response()
      sync_cache_from_buffer_vars(false)
      refresh_problem_state_soon(100)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LocalDiagnosticsRefresh",
    callback = function()
      local epoch = tonumber(vim.g.local_diagnostics_refresh_epoch)
      if waiting_for_local_diagnostics_epoch and epoch and epoch < waiting_for_local_diagnostics_epoch then
        return
      end

      waiting_for_local_diagnostics = false
      waiting_for_local_diagnostics_epoch = nil
      note_diagnostic_response()

      if not problems_pane_is_open() then
        return
      end

      sync_cache_from_buffer_vars(false)
      refresh_problem_state_soon(50)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CocNvimInit",
    callback = function()
      if problems_pane_is_open() then
        start_problem_diagnostics()
      end
    end,
  })

end

return M
