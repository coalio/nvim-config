local M = {}

local horizontal_scroll_columns = 16
local widest_line_cache = {}

local excluded_filetypes = {
  NvimTree = true,
  Trouble = true,
  alpha = true,
  lazy = true,
  trouble = true,
}

local excluded_buftypes = {
  acwrite = true,
  help = true,
  nofile = true,
  nowrite = true,
  prompt = true,
  quickfix = true,
  terminal = true,
}

local function set_window_option(win, option, value)
  pcall(vim.api.nvim_set_option_value, option, value, { scope = "local", win = win })
end

local function get_window_option(win, option, fallback)
  local ok, value = pcall(vim.api.nvim_get_option_value, option, { scope = "local", win = win })
  return ok and value or fallback
end

function M.is_editor_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local buftype = vim.bo[buf].buftype
  local filetype = vim.bo[buf].filetype

  return not excluded_buftypes[buftype] and not excluded_filetypes[filetype]
end

function M.configure_window(win)
  if not M.is_editor_window(win) then
    return false
  end

  for option, value in pairs {
    breakindent = false,
    linebreak = false,
    smoothscroll = false,
    wrap = false,
  } do
    set_window_option(win, option, value)
  end

  return true
end

local function target_window()
  local ok, mouse = pcall(vim.fn.getmousepos)
  if ok and type(mouse) == "table" then
    local win = tonumber(mouse.winid)
    if M.is_editor_window(win) then
      return win
    end
  end

  local current = vim.api.nvim_get_current_win()
  if M.is_editor_window(current) then
    return current
  end
end

local function set_virtualedit_for_scroll(win, enabled)
  if enabled then
    if not vim.w[win].editor_scroll_previous_virtualedit then
      vim.w[win].editor_scroll_previous_virtualedit = get_window_option(win, "virtualedit", "")
    end

    set_window_option(win, "virtualedit", "all")
    return
  end

  local previous = vim.w[win].editor_scroll_previous_virtualedit
  if previous ~= nil then
    set_window_option(win, "virtualedit", previous == "" and "none" or previous)
    vim.w[win].editor_scroll_previous_virtualedit = nil
  end
end

local function text_width(win)
  return math.max(1, vim.api.nvim_win_get_width(win) - (tonumber(vim.wo[win].sidescrolloff) or 0))
end

local function cursor_for_virtual_column(win, lnum, virtual_column)
  virtual_column = math.max(1, math.floor(virtual_column))

  local byte_column = tonumber(vim.fn.virtcol2col(win, lnum, virtual_column)) or 0
  if byte_column < 1 then
    return 1, virtual_column - 1, virtual_column - 1
  end

  local actual_virtual_column = tonumber(vim.fn.virtcol({ lnum, byte_column })) or virtual_column
  local coladd = math.max(0, virtual_column - actual_virtual_column)
  return byte_column, coladd, virtual_column - 1
end

local function line_end_virtual_column(lnum)
  return math.max(1, (tonumber(vim.fn.virtcol({ lnum, "$" })) or 1) - 1)
end

local function invalidate_widest_line_cache(buf)
  if buf then
    widest_line_cache[buf] = nil
  end
end

local function widest_line_virtual_column(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local cached = widest_line_cache[buf]
  if cached and cached.tick == tick then
    return cached.width
  end

  local widest = 1
  local line_count = vim.api.nvim_buf_line_count(buf)

  for lnum = 1, line_count do
    local width = line_end_virtual_column(lnum)
    if width > widest then
      widest = width
    end
  end

  widest_line_cache[buf] = {
    tick = tick,
    width = widest,
  }

  return widest
end

local function max_leftcol(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local width = text_width(win)
  local widest = widest_line_virtual_column(buf)

  return math.max(0, widest - width)
end

local function drag_cursor_into_view(win, view, target_leftcol)
  local width = text_width(win)
  local margin = math.min(tonumber(vim.wo[win].sidescrolloff) or 0, math.floor(width / 3))
  local left_bound = target_leftcol + margin + 1
  local right_bound = math.max(left_bound, target_leftcol + width - margin)
  local cursor_virtual_column = tonumber(vim.fn.virtcol "." ) or 1
  local target_virtual_column

  if cursor_virtual_column < left_bound then
    target_virtual_column = left_bound
  elseif cursor_virtual_column > right_bound then
    target_virtual_column = target_leftcol == 0 and math.min(right_bound, line_end_virtual_column(vim.fn.line ".")) or right_bound
  else
    return
  end

  local lnum = vim.fn.line "."
  local byte_column, coladd, curswant = cursor_for_virtual_column(win, lnum, target_virtual_column)
  set_virtualedit_for_scroll(win, coladd > 0)

  view.lnum = lnum
  view.col = byte_column - 1
  view.coladd = coladd
  view.curswant = curswant
end

function M.scroll_horizontally(columns, win)
  win = win or target_window()
  if not M.configure_window(win) then
    return false
  end

  vim.api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    local target_leftcol = math.min(max_leftcol(win), math.max(0, (tonumber(view.leftcol) or 0) + columns))
    drag_cursor_into_view(win, view, target_leftcol)
    view.leftcol = target_leftcol
    vim.fn.winrestview(view)
  end)

  return true
end

local function map_horizontal_scroll(lhs, columns, desc)
  vim.keymap.set({ "n", "x", "i" }, lhs, function()
    M.scroll_horizontally(columns)
  end, { desc = desc, silent = true })
end

function M.setup()
  vim.opt.wrap = false
  vim.opt.linebreak = false
  vim.opt.breakindent = false
  vim.opt.sidescroll = horizontal_scroll_columns
  vim.opt.sidescrolloff = 8
  pcall(function()
    vim.opt.smoothscroll = false
  end)

  local group = vim.api.nvim_create_augroup("EditorHorizontalScrolling", { clear = true })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout", "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(args)
      invalidate_widest_line_cache(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType", "WinEnter" }, {
    group = group,
    callback = function(args)
      local win = vim.api.nvim_get_current_win()
      if args.event == "BufWinEnter" then
        for _, candidate in ipairs(vim.fn.win_findbuf(args.buf)) do
          M.configure_window(candidate)
        end
        return
      end

      M.configure_window(win)
    end,
  })

  map_horizontal_scroll("<S-ScrollWheelUp>", -horizontal_scroll_columns, "Scroll editor left")
  map_horizontal_scroll("<S-ScrollWheelDown>", horizontal_scroll_columns, "Scroll editor right")
  map_horizontal_scroll("<ScrollWheelLeft>", -horizontal_scroll_columns, "Scroll editor left")
  map_horizontal_scroll("<ScrollWheelRight>", horizontal_scroll_columns, "Scroll editor right")
end

return M
