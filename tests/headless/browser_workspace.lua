local uv = vim.uv or vim.loop

local target = vim.fn.expand(vim.env.BROWSER_WORKSPACE_TARGET or "~/code/chomik-widget")
local previous = vim.fn.expand(vim.env.BROWSER_WORKSPACE_PREVIOUS or "~/.config/nvim")

local function trim(path)
  return vim.fn.fnamemodify(path, ":p"):gsub("[/\\]+$", "")
end

local function fail(message)
  error(message, 0)
end

local function assert_dir(path, label)
  if vim.fn.isdirectory(path) ~= 1 then
    fail(label .. " does not exist: " .. path)
  end
end

local function tree_root()
  local ok, core = pcall(require, "nvim-tree.core")
  if not ok then
    return nil
  end

  return core.get_cwd()
end

local function tree_lines()
  local ok, view = pcall(require, "nvim-tree.view")
  if not ok then
    return {}
  end

  local bufnr = view.get_bufnr()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  return vim.api.nvim_buf_get_lines(bufnr, 0, 8, false)
end

local function snapshot(label)
  local lines = tree_lines()

  return {
    label = label,
    cwd = trim(vim.fn.getcwd()),
    uv_cwd = trim(uv.cwd()),
    tree = tree_root() and trim(tree_root()) or nil,
    tree_label = lines[1] or "",
    tree_lines = lines,
    filetype = vim.bo.filetype,
  }
end

local samples = {}

local function record(label)
  samples[#samples + 1] = snapshot(label)
end

local function dump_samples()
  for _, sample in ipairs(samples) do
    print(
      table.concat({
        "sample",
        sample.label,
        "cwd=" .. tostring(sample.cwd),
        "uv=" .. tostring(sample.uv_cwd),
        "tree=" .. tostring(sample.tree),
        "tree_label=" .. vim.inspect(sample.tree_label),
        "ft=" .. tostring(sample.filetype),
      }, " ")
    )
    for i, line in ipairs(sample.tree_lines) do
      print("tree_line " .. sample.label .. " " .. i .. " " .. line)
    end
  end
end

local function stop(command)
  pcall(function()
    require("persistence").stop()
  end)
  vim.cmd(command)
end

local function assert_workspace(label)
  local target_trimmed = trim(target)
  local current = snapshot(label)
  if current.cwd ~= target_trimmed then
    dump_samples()
    fail(label .. " cwd mismatch: expected " .. target_trimmed .. ", got " .. current.cwd)
  end

  if current.uv_cwd ~= target_trimmed then
    dump_samples()
    fail(label .. " uv cwd mismatch: expected " .. target_trimmed .. ", got " .. current.uv_cwd)
  end

  if current.tree ~= target_trimmed then
    dump_samples()
    fail(label .. " nvim-tree root mismatch: expected " .. target_trimmed .. ", got " .. tostring(current.tree))
  end

  local expected_label = vim.fn.fnamemodify(target_trimmed, ":t")
  if current.tree_label ~= expected_label then
    dump_samples()
    fail(
      label
        .. " rendered nvim-tree root label mismatch: expected "
        .. expected_label
        .. ", got "
        .. vim.inspect(current.tree_label)
    )
  end
end

local function check_workspace(label)
  record(label)
  local passed, check_err = xpcall(function()
    assert_workspace(label)
  end, debug.traceback)

  if not passed then
    print(check_err)
    stop "cquit"
  end
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

assert_dir(target, "target")
assert_dir(previous, "previous")

vim.schedule(function()
  local ok, err = xpcall(function()
    local api = require "nvim-tree.api"
    local browser = require "configs.browser"

    vim.cmd("cd " .. vim.fn.fnameescape(previous))
    api.tree.open({ path = previous })
    api.tree.focus()
    vim.cmd("lcd " .. vim.fn.fnameescape(previous))
    record("previous-tree-local-cwd")

    vim.cmd.wincmd "p"
    browser.open(target)
    record("browser-open")

    vim.defer_fn(function()
      feed "<C-o>"
      record("ctrl-o-fed")
    end, 100)

    for _, delay in ipairs({ 180, 350, 700 }) do
      vim.defer_fn(function()
        check_workspace("after-" .. delay .. "ms")
      end, delay)
    end

    vim.defer_fn(function()
      local tree_win = api.tree.winid()
      if tree_win and vim.api.nvim_win_is_valid(tree_win) then
        vim.api.nvim_win_call(tree_win, function()
          vim.cmd("lcd " .. vim.fn.fnameescape(previous))
        end)
        api.tree.focus()
      end

      record("stale-tree-window-cwd")
      vim.api.nvim_exec_autocmds("User", { pattern = "PersistenceLoadPost" })
    end, 850)

    for _, delay in ipairs({ 1000, 1400 }) do
      vim.defer_fn(function()
        check_workspace("after-delayed-persistence-" .. delay .. "ms")
      end, delay)
    end

    vim.defer_fn(function()
      local passed, final_err = xpcall(function()
        assert_workspace "final"
      end, debug.traceback)

      dump_samples()

      if not passed then
        print(final_err)
        stop "cquit"
        return
      end

      stop "qa!"
    end, 1500)
  end, debug.traceback)

  if not ok then
    print(err)
    stop "cquit"
  end
end)
