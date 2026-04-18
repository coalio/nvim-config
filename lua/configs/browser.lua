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

local function scandir(dir)
  local entries = {}
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
    if a.is_dir ~= b.is_dir then
      return a.is_dir
    end
    return a.name:lower() < b.name:lower()
  end)

  return entries
end

local function set_workspace(dir)
  vim.cmd("cd " .. vim.fn.fnameescape(dir))
  pcall(function()
    require("persistence").load()
  end)

  close_alpha_buffer()

  local ok, api = pcall(require, "nvim-tree.api")
  if ok then
    api.tree.open()
    api.tree.focus()
  end
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

function M.open(dir)
  dir = vim.fn.fnamemodify(dir or vim.loop.cwd(), ":p")

  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  local function open_browser(target)
    M.open(target)
  end

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
            vim.cmd("cd " .. vim.fn.fnameescape(workspace))
            vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
            close_alpha_buffer()
          end
        end)
      end

      local function open_current_folder()
        actions.close(prompt_bufnr)
        vim.schedule(function()
          set_workspace(dir)
        end)
      end

      local function go_parent()
        actions.close(prompt_bufnr)
        vim.schedule(function()
          open_browser(vim.fn.fnamemodify(dir, ":h"))
        end)
      end

      actions.select_default:replace(edit_or_enter)
      map("i", "<CR>", edit_or_enter)
      map("n", "<CR>", edit_or_enter)
      map("i", "<C-o>", open_current_folder)
      map("n", "<C-o>", open_current_folder)
      map("i", "<C-h>", go_parent)
      map("n", "<C-h>", go_parent)
      return true
    end,
  }):find()
end

return M
