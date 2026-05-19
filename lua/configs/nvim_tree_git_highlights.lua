local M = {}

local state_path = vim.fn.stdpath "state" .. "/nvim-tree-git-folder-highlights.json"
local augroup = vim.api.nvim_create_augroup("UserNvimTreeGitFolderHighlights", { clear = true })
local did_setup = false

local statuses = {
  {
    key = "dirty",
    label = "Modified / dirty",
    folder_hl = "NvimTreeGitFolderDirtyHL",
    enabled_link = "NvimTreeGitFileDirtyHL",
  },
  {
    key = "new",
    label = "New / untracked",
    folder_hl = "NvimTreeGitFolderNewHL",
    enabled_link = "NvimTreeGitFileNewHL",
  },
  {
    key = "deleted",
    label = "Deleted",
    folder_hl = "NvimTreeGitFolderDeletedHL",
    enabled_link = "NvimTreeGitFileDeletedHL",
  },
  {
    key = "ignored",
    label = "Ignored",
    folder_hl = "NvimTreeGitFolderIgnoredHL",
    enabled_link = "NvimTreeGitFileIgnoredHL",
  },
  {
    key = "staged",
    label = "Staged",
    folder_hl = "NvimTreeGitFolderStagedHL",
    enabled_link = "NvimTreeGitFileStagedHL",
  },
  {
    key = "renamed",
    label = "Renamed",
    folder_hl = "NvimTreeGitFolderRenamedHL",
    enabled_link = "NvimTreeGitFileRenamedHL",
  },
  {
    key = "merge",
    label = "Merge conflict",
    folder_hl = "NvimTreeGitFolderMergeHL",
    enabled_link = "NvimTreeGitFileMergeHL",
  },
}

local defaults = {}
local folder_hl_to_key = {}
for _, status in ipairs(statuses) do
  defaults[status.key] = true
  folder_hl_to_key[status.folder_hl] = status.key
end

M.state = vim.deepcopy(defaults)

local function decode_json(raw)
  if vim.json and vim.json.decode then
    return vim.json.decode(raw)
  end

  return vim.fn.json_decode(raw)
end

local function encode_json(value)
  if vim.json and vim.json.encode then
    return vim.json.encode(value)
  end

  return vim.fn.json_encode(value)
end

local function load_state()
  M.state = vim.deepcopy(defaults)

  if vim.fn.filereadable(state_path) ~= 1 then
    return
  end

  local ok, saved = pcall(decode_json, table.concat(vim.fn.readfile(state_path), "\n"))
  if not ok or type(saved) ~= "table" then
    return
  end

  for key in pairs(defaults) do
    if type(saved[key]) == "boolean" then
      M.state[key] = saved[key]
    end
  end
end

local function save_state(next_state)
  local ok, encoded = pcall(encode_json, next_state)
  if not ok then
    vim.notify("Could not encode nvim-tree git highlight settings", vim.log.levels.ERROR)
    return false
  end

  vim.fn.mkdir(vim.fn.fnamemodify(state_path, ":h"), "p")
  local write_ok = pcall(vim.fn.writefile, { encoded }, state_path)
  if not write_ok then
    vim.notify("Could not save nvim-tree git highlight settings", vim.log.levels.ERROR)
    return false
  end

  return true
end

local function patch_git_decorator()
  local GitDecorator = package.loaded["nvim-tree.renderer.decorator.git"]
  local DirectoryNode = package.loaded["nvim-tree.node.directory"]
  if not GitDecorator or not DirectoryNode then
    return
  end

  local original = GitDecorator._user_folder_highlight_original or GitDecorator.highlight_group
  GitDecorator._user_folder_highlight_original = original

  GitDecorator.highlight_group = function(self, node)
    if self.highlight_range == "none" then
      return nil
    end

    local git_xy = node:get_git_xy()
    if not git_xy then
      return nil
    end

    if node:is(DirectoryNode) then
      for _, xy in ipairs(git_xy) do
        local group = self.folder_hl_by_xy and self.folder_hl_by_xy[xy]
        local key = group and folder_hl_to_key[group]
        if group and (not key or M.state[key]) then
          return group
        end
      end

      return nil
    end

    return original(self, node)
  end
end

function M.apply()
  patch_git_decorator()

  for _, status in ipairs(statuses) do
    local link = M.state[status.key] and status.enabled_link or "NvimTreeFolderName"
    vim.api.nvim_set_hl(0, status.folder_hl, { link = link })
  end

  vim.cmd "redraw"
end

local function render(buf, next_state)
  local lines = {
    "Toggle Git folder highlighting",
    "",
  }

  for _, status in ipairs(statuses) do
    local checked = next_state[status.key] and "x" or " "
    table.insert(lines, string.format("[%s] %s", checked, status.label))
  end

  table.insert(lines, "")
  table.insert(lines, "Space: toggle  Enter/s: save  Esc/q: cancel")

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function status_index_from_cursor()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local index = row - 2
  if index < 1 or index > #statuses then
    return nil
  end

  return index
end

function M.open()
  if not did_setup then
    M.setup()
  end

  local next_state = vim.deepcopy(M.state)
  local height = #statuses + 4
  local columns = vim.o.columns
  local lines = vim.o.lines
  local width = math.min(48, math.max(32, columns - 4))
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.max(0, math.floor((columns - width) / 2)),
    row = math.max(0, math.floor((lines - height) / 2) - 1),
    style = "minimal",
    border = "rounded",
  })

  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "nvim-tree-git-highlights"
  vim.wo[win].cursorline = true

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function rerender()
    local cursor = vim.api.nvim_win_get_cursor(win)
    render(buf, next_state)
    vim.api.nvim_win_set_cursor(win, cursor)
  end

  local function toggle_current()
    local index = status_index_from_cursor()
    if not index then
      return
    end

    local key = statuses[index].key
    next_state[key] = not next_state[key]
    rerender()
  end

  local function save()
    if not save_state(next_state) then
      return
    end

    M.state = vim.deepcopy(next_state)
    M.apply()
    close()
  end

  render(buf, next_state)
  vim.api.nvim_win_set_cursor(win, { 3, 0 })

  local map_opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<Space>", toggle_current, map_opts)
  vim.keymap.set("n", "<CR>", save, map_opts)
  vim.keymap.set("n", "s", save, map_opts)
  vim.keymap.set("n", "<Esc>", close, map_opts)
  vim.keymap.set("n", "q", close, map_opts)
end

function M.setup()
  if did_setup then
    return
  end

  did_setup = true
  load_state()
  M.apply()

  vim.api.nvim_create_user_command("NvimTreeGitHighlights", M.open, { force = true })

  vim.api.nvim_create_autocmd({ "ColorScheme", "FileType" }, {
    group = augroup,
    pattern = { "*", "NvimTree" },
    callback = function(event)
      if event.event == "FileType" and event.match ~= "NvimTree" then
        return
      end

      M.apply()
    end,
  })
end

return M
