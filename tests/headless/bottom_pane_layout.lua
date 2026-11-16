-- run with: nvim --headless -u NONE -i NONE -l tests/headless/bottom_pane_layout.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, { rpc = true })
assert(child > 0, "could not start the layout test editor")

local function exec(code, ...)
  return vim.rpcrequest(child, "nvim_exec_lua", code, { ... })
end

local function wait_for(code, label)
  assert(vim.wait(1000, function()
    return exec(code)
  end, 10), label)
end

local ok, err = xpcall(function()
  -- isolate the layout from installed plugins while using native resize events
  exec([[
    vim.o.columns = 180
    vim.o.lines = 50
    vim.opt.runtimepath:append(...)
    vim.o.shell = "sh"
    vim.o.equalalways = false
    pane = require("configs.bottom_pane")
    pane.setup()
    resize_events = 0
    vim.api.nvim_create_autocmd("WinResized", {
      callback = function()
        resize_events = resize_events + 1
      end,
    })
    editor = vim.api.nvim_get_current_win()

    vim.cmd("topleft 25vnew")
    tree = vim.api.nvim_get_current_win()
    vim.bo.buftype = "nofile"
    vim.bo.filetype = "NvimTree"
    vim.wo.winfixwidth = true
    vim.api.nvim_set_current_win(editor)

    vim.cmd("botright 40vnew")
    plugin = vim.api.nvim_get_current_win()
    vim.bo.buftype = "nofile"
    vim.bo.filetype = "plugin-panel"
    vim.wo.winfixwidth = true
    vim.api.nvim_set_current_win(editor)

    pane.open_terminal()
    vim.cmd("stopinsert")
    term = vim.api.nvim_get_current_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.w[win].bottom_pane_terminal_session_rail then
        rail = win
      end
    end
    assert(rail, "missing session sidebar")
    rail_width = vim.api.nvim_win_get_width(rail)
    term_width = vim.api.nvim_win_get_width(term)
    term_buf = vim.api.nvim_win_get_buf(term)
    vim.api.nvim_set_current_win(editor)

    function layout_matches()
      return vim.api.nvim_win_get_width(rail) == rail_width
        and vim.api.nvim_win_get_width(term) + rail_width + 1 == vim.api.nvim_win_get_width(editor)
    end
  ]], root)

  -- closing a full-height right pane must give its space to the terminal
  exec([[vim.api.nvim_win_close(plugin, true)]])
  wait_for([[
    return vim.api.nvim_win_get_width(rail) == rail_width
      and vim.api.nvim_win_get_width(term) > term_width
  ]], "closing the right pane expanded the session sidebar instead of the terminal")
  exec([[
    assert(vim.api.nvim_get_current_win() == editor, "layout refresh moved focus")
    assert(vim.api.nvim_win_get_buf(term) == term_buf, "layout refresh replaced the terminal session")
    assert(vim.api.nvim_win_get_width(tree) == 25, "layout refresh resized the tree")
  ]])

  -- native resize events must handle arbitrary pane changes without focus changes
  for _, width in ipairs({ 45, 18 }) do
    exec([[
      previous_resize_events = resize_events
      vim.api.nvim_win_set_width(tree, ...)
    ]], width)
    wait_for(
      [[return resize_events > previous_resize_events and layout_matches()]],
      "tree resize did not refresh the layout"
    )
    exec([[
      assert(vim.api.nvim_win_get_width(tree) == ..., "layout refresh undid the requested tree width")
      assert(vim.api.nvim_get_current_win() == editor, "tree resize moved focus")
    ]], width)
  end

  exec([[vim.api.nvim_win_set_width(rail, rail_width + 15)]])
  wait_for([[return layout_matches()]], "resizing the session divider did not restore its width")

  -- opening, resizing, and closing plugin panes must preserve their requested widths
  for _, equalalways in ipairs({ false, true }) do
    exec([[
      vim.o.equalalways = ...
      vim.cmd("botright 35vnew")
      plugin = vim.api.nvim_get_current_win()
      vim.bo.buftype = "nofile"
      vim.wo.winfixwidth = true
    ]], equalalways)
    wait_for([[return layout_matches()]], "opening the plugin pane broke the bottom divisions")
    for _, width in ipairs({ 50, 28 }) do
      exec([[vim.api.nvim_win_set_width(plugin, ...)]], width)
      wait_for([[return layout_matches()]], "plugin resize did not refresh the bottom divisions")
      exec([[
        assert(vim.api.nvim_win_get_width(plugin) == ..., "layout refresh undid the plugin width")
        assert(vim.api.nvim_get_current_win() == plugin, "layout refresh stole plugin focus")
      ]], width)
    end
    exec([[
      vim.api.nvim_set_current_win(editor)
      term_width = vim.api.nvim_win_get_width(term)
      vim.api.nvim_win_close(plugin, true)
    ]])
    wait_for([[
      return layout_matches() and vim.api.nvim_win_get_width(term) > term_width
    ]], "closing the reopened plugin pane did not expand the terminal")
  end

  -- screen and height changes should keep the same terminal session and divisions
  exec([[
    vim.o.columns = 150
    vim.o.lines = 42
    vim.api.nvim_win_set_height(editor, 22)
  ]])
  wait_for([[return layout_matches()]], "screen resize broke the bottom divisions")
  exec([[
    assert(vim.api.nvim_win_get_buf(term) == term_buf, "resize replaced the terminal session")
    assert(vim.api.nvim_get_current_win() == editor, "resize changed editor focus")
  ]])

  -- a queued refresh must not switch tabs, and returning must restore the rail
  exec([[
    original_tab = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_win_set_width(rail, rail_width + 10)
    vim.cmd("tabnew")
  ]])
  exec([[
    assert(vim.api.nvim_get_current_tabpage() ~= original_tab, "layout refresh switched tabs")
    vim.cmd("tabclose")
  ]])
  wait_for([[return layout_matches()]], "returning to the terminal tab did not refresh its layout")

  -- closing the tree should release its space to the terminal as well
  exec([[
    term_width = vim.api.nvim_win_get_width(term)
    vim.api.nvim_win_close(tree, true)
  ]])
  wait_for([[
    return layout_matches() and vim.api.nvim_win_get_width(term) > term_width
  ]], "closing the tree did not expand the terminal")

  -- queued callbacks must tolerate closed panes without recreating their windows
  exec([[
    vim.api.nvim_win_set_width(rail, rail_width + 10)
    pane.close()
    vim.o.columns = 180
  ]])
  exec([[
    assert(not vim.api.nvim_win_is_valid(term), "closed terminal was recreated")
    assert(not vim.api.nvim_win_is_valid(rail), "closed sidebar was recreated")
    assert(#vim.api.nvim_list_wins() == 1, "layout refresh opened an unexpected window")
    assert(vim.v.errmsg == "", vim.v.errmsg)
  ]])
end, function(message)
  return debug.traceback(vim.inspect(message))
end)

vim.fn.jobstop(child)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
print("bottom pane layout: passed")
