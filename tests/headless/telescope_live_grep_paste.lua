local sentinel = "ctrl-v-paste-sentinel"
local clipboard_read = false
local mode_before_paste = ""

local function stop(command)
  pcall(function()
    require("persistence").stop()
  end)
  vim.cmd(command)
end

local function fail(message)
  print(message)
  stop "cquit"
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local function messages()
  return vim.api.nvim_exec2("messages", { output = true }).output
end

vim.schedule(function()
  _G.ClipUnix = function()
    clipboard_read = true
    return sentinel
  end

  vim.defer_fn(function()
    -- NvChad schedules custom mappings during startup, so wait for that exact F2 mapping.
    local mapping = vim.fn.maparg("<F2>", "n", false, true)
    if type(mapping.callback) ~= "function" or mapping.desc ~= "Live grep" then
      fail("unexpected F2 mapping: " .. vim.inspect(mapping))
      return
    end

    -- Exercise the user's real entry point so command- and picker-local mappings are covered.
    feed "<F2>"
  end, 500)

  vim.defer_fn(function()
    if vim.bo.filetype ~= "TelescopePrompt" then
      fail("F2 did not open the Telescope live-grep prompt; current filetype: " .. vim.bo.filetype)
      return
    end

    mode_before_paste = vim.fn.mode()
    if not mode_before_paste:find("^i") then
      feed "i<C-v>"
    else
      feed "<C-v>"
    end
  end, 900)

  vim.defer_fn(function()
    local prompt = require("telescope.actions.state").get_current_line()
    local output = messages()

    if output:find("Nothing currently selected", 1, true) then
      fail(
        "Ctrl-V invoked Telescope's vertical-open action instead of clipboard paste; clipboard_read="
          .. tostring(clipboard_read)
          .. ", mode_before_paste="
          .. mode_before_paste
      )
      return
    end

    if prompt ~= sentinel then
      fail("Ctrl-V paste mismatch: expected " .. vim.inspect(sentinel) .. ", got " .. vim.inspect(prompt))
      return
    end

    print("F2 live-grep Ctrl-V paste passed: " .. prompt)
    stop "qa!"
  end, 1300)
end)
