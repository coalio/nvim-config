local status_ok, alpha = pcall(require, "alpha")
if not status_ok then
  return
end

local startify = require "alpha.themes.startify"

math.randomseed(os.time())
local function get_startify_cow()
  local quotes = {
    "Talk is cheap. Show me the code.",
    "A user interface is like a joke. If you have to explain it, it's not that good.",
    "Make it work, make it right, make it fast.",
    "In theory, there is no difference between theory and practice...",
    "Vim: The editor of the beast.",
  }
  local quote = quotes[math.random(#quotes)]
  local width = string.len(quote) + 2
  local border = "+" .. string.rep("-", width) .. "+"

  return {
    border,
    "| " .. quote .. " |",
    border,
    "        o",
    "         o  ^__^",
    "          o (oo)\\_______",
    "            (__)\\       )\\/\\",
    "                ||----w |",
    "                ||     ||",
  }
end

local function session_files()
  local session_dir = vim.fn.expand "~/.local/state/nvim/sessions"
  local files = vim.fn.globpath(session_dir, "*.vim", false, true)
  table.sort(files, function(a, b)
    return (vim.fn.getftime(a) or 0) > (vim.fn.getftime(b) or 0)
  end)
  return files
end

local function session_dir(path)
  local name = vim.fn.fnamemodify(path, ":t:r")
  local dir = name:gsub("%%", "/")

  if vim.fn.isdirectory(dir) == 0 then
    local parts = vim.split(dir, "/", { plain = true })
    if #parts > 1 then
      table.remove(parts, #parts)
      local candidate = table.concat(parts, "/")
      if vim.fn.isdirectory(candidate) == 1 then
        dir = candidate
      end
    end
  end

  if dir:match("^%a/$") then
    dir = dir:gsub("^(%a)/", "%1:/")
  end

  return dir
end

local function session_button(path, index)
  local dir = session_dir(path)
  local label = dir:gsub(vim.env.HOME or "", "~")
  return startify.button(
    tostring(index),
    "  " .. label,
    string.format("<cmd>cd %s | lua require('persistence').load()<CR>", vim.fn.fnameescape(dir))
  )
end

local function recent_workspaces()
  local buttons = {}
  for _, path in ipairs(session_files()) do
    buttons[#buttons + 1] = session_button(path, #buttons + 1)
    if #buttons == 8 then
      break
    end
  end

  if #buttons == 0 then
    buttons[1] = {
      type = "text",
      val = "No saved workspaces yet",
      opts = { hl = "Comment", position = "center" },
    }
  end

  return buttons
end

startify.section.header.val = get_startify_cow()
startify.section.header.opts = {
  hl = "Keyword",
  position = "center",
}

startify.config.layout[1] = {
  type = "padding",
  val = function()
    local vim_height = vim.api.nvim_win_get_height(0)
    local content_height = 36
    local margin = math.floor((vim_height - content_height) / 2)
    return math.max(0, margin)
  end,
}

startify.config.opts.margin = 15

startify.section.top_buttons.val = {
  startify.button("e", "  New file", ":ene <BAR> startinsert <CR>"),
  startify.button("p", "  Recent Projects", ":Telescope projects<CR>"),
  startify.button("f", "  Browse", ":lua require('configs.browser').open(vim.fn.expand('~'))<CR>"),
  startify.button("q", "󰅙  Quit NVIM", ":qa<CR>"),
}

startify.section.mru.val = {}
startify.section.mru_cwd.val = {
  { type = "padding", val = 1 },
  { type = "text", val = "Recent workspaces", opts = { hl = "SpecialComment", position = "center" } },
  { type = "padding", val = 1 },
  {
    type = "group",
    val = recent_workspaces,
  },
}

alpha.setup(startify.config)
