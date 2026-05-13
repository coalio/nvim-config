local M = {}
local skip_next_persistence_tree_refresh = false

local function reset_bottom_pane_diagnostics()
  local ok, bottom_pane = pcall(require, "configs.bottom_pane")
  if ok and type(bottom_pane.reset_diagnostics) == "function" then
    bottom_pane.reset_diagnostics()
  end
end

local function close_bottom_pane()
  local ok, bottom_pane = pcall(require, "configs.bottom_pane")
  if ok then
    bottom_pane.close()
  end
end

local function wipe_terminal_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
      vim.bo[buf].buflisted = false
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

local function unlock_current_window_for_replacement()
  if vim.fn.exists("+winfixbuf") == 0 then
    return
  end

  pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { scope = "local", win = 0 })
end

local function focus_buffer_target_window()
  local ok, bottom_pane = pcall(require, "configs.bottom_pane")
  if ok and bottom_pane.focus_buffer_target_window and bottom_pane.focus_buffer_target_window() then
    return true
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local fixed = vim.fn.exists("+winfixbuf") == 1 and vim.api.nvim_get_option_value("winfixbuf", { win = win })
      if
        not fixed
        and vim.bo[buf].buftype == ""
        and vim.bo[buf].filetype ~= "NvimTree"
        and vim.bo[buf].filetype ~= "trouble"
      then
        vim.api.nvim_set_current_win(win)
        return true
      end
    end
  end

  return false
end

local function prepare_workspace_replacement()
  close_bottom_pane()
  wipe_terminal_buffers()
  if not focus_buffer_target_window() then
    unlock_current_window_for_replacement()
  end
end

local function prepare_file_edit()
  if focus_buffer_target_window() then
    return
  end

  close_bottom_pane()
  if not focus_buffer_target_window() then
    unlock_current_window_for_replacement()
  end
end

local function close_alpha_buffer()
  local current = vim.api.nvim_get_current_buf()
  local current_name = vim.api.nvim_buf_get_name(current)
  if current_name ~= "" and not current_name:match("^alpha://") then
    return
  end

  local alphas = vim.fn.getbufinfo({ buflisted = 1 })
  for _, buf in ipairs(alphas) do
    if buf.name:match("^alpha://") then
      pcall(vim.api.nvim_buf_delete, buf.bufnr, { force = true })
    end
  end
end

local function normalize_dir(dir)
  return vim.fn.fnamemodify(dir or vim.loop.cwd(), ":p")
end

local function parent_dir(dir)
  local normalized = normalize_dir(dir)
  local trimmed = normalized:gsub("[/\\]+$", "")

  if trimmed == "" then
    return normalized
  end

  return vim.fn.fnamemodify(trimmed, ":h")
end

local function session_file_exists()
  local persistence = require "persistence"
  local current = persistence.current()
  if vim.fn.filereadable(current) == 1 then
    return true
  end

  local fallback = persistence.current({ branch = false })
  return vim.fn.filereadable(fallback) == 1
end

local function reset_workspace_buffers()
  prepare_workspace_replacement()

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  prepare_file_edit()
  pcall(vim.cmd, "enew")
end

local function scandir(dir)
  dir = normalize_dir(dir)

  local entries = {}
  local parent = parent_dir(dir)
  if parent ~= dir then
    entries[#entries + 1] = {
      name = "..",
      path = parent,
      is_dir = true,
      display = "  ..",
    }
  end

  local fs = vim.loop.fs_scandir(dir)
  if not fs then
    return entries
  end

  while true do
    local name, kind = vim.loop.fs_scandir_next(fs)
    if not name then
      break
    end

    if name ~= "." and name ~= ".." then
      local path = dir .. "/" .. name
      entries[#entries + 1] = {
        name = name,
        path = path,
        is_dir = kind == "directory",
        display = (kind == "directory" and "  " or "󰈔  ") .. name,
      }
    end
  end

  table.sort(entries, function(a, b)
    if a.name == ".." or b.name == ".." then
      return a.name == ".."
    end

    if a.is_dir ~= b.is_dir then
      return a.is_dir
    end
    return a.name:lower() < b.name:lower()
  end)

  return entries
end

local function set_workspace(dir, opts)
  opts = opts or {}
  dir = normalize_dir(dir)
  local previous_dir = normalize_dir(vim.loop.cwd())

  if previous_dir ~= dir then
    reset_bottom_pane_diagnostics()
  end

  vim.cmd("cd " .. vim.fn.fnameescape(dir))
  close_alpha_buffer()

  if opts.reset_buffers then
    reset_workspace_buffers()
  elseif opts.load_session then
    prepare_workspace_replacement()
  else
    prepare_file_edit()
  end

  local loaded_session = false
  if opts.load_session and session_file_exists() then
    prepare_workspace_replacement()
    pcall(function()
      skip_next_persistence_tree_refresh = true
      require("persistence").load()
      loaded_session = true
    end)

    if not loaded_session then
      skip_next_persistence_tree_refresh = false
    end
  end

  if opts.load_session and not loaded_session and vim.fn.bufname() ~= "" then
    prepare_file_edit()
    pcall(vim.cmd, "enew")
  end

  local ok, api = pcall(require, "nvim-tree.api")
  if ok then
    local visible = api.tree.is_visible()

    if visible then
      api.tree.change_root(dir)
    elseif opts.open_tree or opts.focus_tree then
      api.tree.open()
      api.tree.change_root(dir)
    end

    if opts.focus_tree then
      api.tree.focus()
    end
  end

  return dir, loaded_session
end

local function repo_root(path)
  local git_dir = vim.fs.find(".git", {
    upward = true,
    path = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h"),
  })[1]

  if git_dir then
    return vim.fn.fnamemodify(git_dir, ":h")
  end
end

local function open_browser(target)
  M.open(target)
end

local function open_project_picker()
  local history = require "project_nvim.utils.history"
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  local projects = history.get_recent_projects()
  if #projects == 0 then
    vim.notify("No recent projects", vim.log.levels.INFO)
    return
  end

  for i = 1, math.floor(#projects / 2) do
    projects[i], projects[#projects - i + 1] = projects[#projects - i + 1], projects[i]
  end

  pickers.new({}, {
    prompt_title = "Recent Projects",
    finder = finders.new_table {
      results = projects,
      entry_maker = function(entry)
        local label = entry:gsub(vim.env.HOME or "", "~")
        return {
          value = entry,
          display = label,
          ordinal = label,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    previewer = false,
    attach_mappings = function(prompt_bufnr, map)
      local function select_project()
        local entry = action_state.get_selected_entry()
        if not entry then
          return
        end

        actions.close(prompt_bufnr)
        vim.schedule(function()
          set_workspace(entry.value, { open_tree = true, focus_tree = true })
        end)
      end

      actions.select_default:replace(select_project)
      map("i", "<CR>", select_project)
      map("n", "<CR>", select_project)
      return true
    end,
  }):find()
end

function M.consume_persistence_tree_refresh_skip()
  if not skip_next_persistence_tree_refresh then
    return false
  end

  skip_next_persistence_tree_refresh = false
  return true
end

function M.set_workspace(dir, opts)
  return set_workspace(dir, opts)
end

function M.load_session(dir)
  return set_workspace(dir, { load_session = true, reset_buffers = true })
end

function M.open_recent_projects()
  open_project_picker()
end

function M.browse_home()
  M.open(vim.fn.expand "~")
end

function M.open(dir)
  dir = normalize_dir(dir)

  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  pickers.new({}, {
    prompt_title = "Browse: " .. vim.fn.fnamemodify(dir, ":~"),
    finder = finders.new_table {
      results = scandir(dir),
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.name,
          path = entry.path,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    previewer = false,
    layout_strategy = "center",
    layout_config = {
      width = 0.7,
      height = 0.6,
      anchor = "N",
      prompt_position = "top",
    },
    attach_mappings = function(prompt_bufnr, map)
      local function selected()
        local entry = action_state.get_selected_entry()
        return entry and entry.value or nil
      end

      local function edit_or_enter()
        local entry = selected()
        if not entry then
          return
        end

        actions.close(prompt_bufnr)
        vim.schedule(function()
          if entry.is_dir then
            open_browser(entry.path)
          else
            local workspace = repo_root(entry.path) or vim.fn.fnamemodify(entry.path, ":h")
            set_workspace(workspace)
            prepare_file_edit()
            vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
          end
        end)
      end

      local function open_current_folder()
        actions.close(prompt_bufnr)
        vim.schedule(function()
          set_workspace(dir, { load_session = true, reset_buffers = true, open_tree = true, focus_tree = true })
        end)
      end

      actions.select_default:replace(edit_or_enter)
      map("i", "<CR>", edit_or_enter)
      map("n", "<CR>", edit_or_enter)
      map("i", "<C-o>", open_current_folder)
      map("n", "<C-o>", open_current_folder)
      return true
    end,
  }):find()
end

return M
