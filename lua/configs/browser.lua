local M = {}

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
  return vim.fn.fnamemodify(normalize_dir(dir), ":h")
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

  vim.cmd("cd " .. vim.fn.fnameescape(dir))
  close_alpha_buffer()

  if opts.load_session then
    pcall(function()
      require("persistence").load()
    end)
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

  return dir
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

function M.set_workspace(dir, opts)
  return set_workspace(dir, opts)
end

function M.load_session(dir)
  return set_workspace(dir, { load_session = true })
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
            vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
          end
        end)
      end

      local function open_current_folder()
        actions.close(prompt_bufnr)
        vim.schedule(function()
          set_workspace(dir, { load_session = true, open_tree = true, focus_tree = true })
        end)
      end

      local function go_parent()
        actions.close(prompt_bufnr)
        vim.schedule(function()
          open_browser(parent_dir(dir))
        end)
      end

      actions.select_default:replace(edit_or_enter)
      map("i", "<CR>", edit_or_enter)
      map("n", "<CR>", edit_or_enter)
      map("i", "<C-o>", open_current_folder)
      map("n", "<C-o>", open_current_folder)
      map("i", "<BS>", go_parent)
      map("n", "<BS>", go_parent)
      map("i", "<C-h>", go_parent)
      map("n", "<C-h>", go_parent)
      return true
    end,
  }):find()
end

return M
