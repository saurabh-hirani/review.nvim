local M = {}

local store = require("review.store")
local hooks = require("review.hooks")
local popup = require("review.popup")
local marks = require("review.marks")

local function notify(msg, level)
  vim.notify(msg, level, { title = "review.nvim" })
end

---@param initial_type? string a comment type key from config.comment_types
function M.add_at_cursor(initial_type)
  local file, line, side = hooks.get_cursor_position()
  if not file or not line then
    notify("Could not determine cursor position", vim.log.levels.WARN)
    return
  end

  local existing = store.get_at_line(file, line, side)
  if existing then
    notify("Comment already exists at this line. Use edit instead.", vim.log.levels.WARN)
    return
  end

  popup.open(initial_type, nil, function(comment_type, text)
    if comment_type and text then
      store.add(file, line, comment_type, text, nil, side)
      vim.schedule(function()
        marks.refresh()
      end)
      notify(string.format("Added %s comment", comment_type), vim.log.levels.INFO)
    end
  end)
end

-- Alias for backwards compatibility
function M.add_with_menu()
  M.add_at_cursor()
end

---@param initial_type? string a comment type key from config.comment_types
function M.file_comment(initial_type)
  local file = hooks.get_cursor_position()
  if not file then
    notify("Could not determine file", vim.log.levels.WARN)
    return
  end

  local existing = store.get_file_comment(file)
  if existing then
    popup.open(existing.type, existing.text, function(new_type, text)
      if new_type and text then
        store.update(existing.id, text, new_type)
        vim.schedule(function()
          marks.refresh()
        end)
        notify("File comment updated", vim.log.levels.INFO)
      end
    end)
  else
    popup.open(initial_type, nil, function(comment_type, text)
      if comment_type and text then
        store.add(file, 0, comment_type, text)
        vim.schedule(function()
          marks.refresh()
        end)
        notify(string.format("Added %s file comment", comment_type), vim.log.levels.INFO)
      end
    end)
  end
end

---@param initial_type? string a comment type key from config.comment_types
function M.add_for_range(initial_type)
  local file, start_line, end_line, side = hooks.get_visual_range()
  if not file or not start_line or not end_line then
    notify("Could not determine visual selection", vim.log.levels.WARN)
    return
  end

  local existing = store.get_overlapping(file, start_line, end_line, side)
  if existing then
    notify("Comment already exists in this range. Use edit instead.", vim.log.levels.WARN)
    return
  end

  popup.open(initial_type, nil, function(comment_type, text)
    if comment_type and text then
      store.add(file, start_line, comment_type, text, end_line, side)
      vim.schedule(function()
        marks.refresh()
      end)
      notify(string.format("Added %s comment", comment_type), vim.log.levels.INFO)
    end
  end)
end

function M.edit_at_cursor()
  local file, line, side = hooks.get_cursor_position()
  if not file or not line then
    notify("Could not determine cursor position", vim.log.levels.WARN)
    return
  end

  local comment = store.get_at_line(file, line, side)
  if not comment and line == 1 then
    comment = store.get_file_comment(file)
  end
  if not comment then
    notify("No comment at cursor position", vim.log.levels.WARN)
    return
  end

  popup.open(comment.type, comment.text, function(new_type, text)
    if new_type and text then
      store.update(comment.id, text, new_type)
      -- Schedule refresh to run after popup is fully closed
      vim.schedule(function()
        marks.refresh()
      end)
      notify("Comment updated", vim.log.levels.INFO)
    end
  end)
end

function M.delete_at_cursor()
  local file, line, side = hooks.get_cursor_position()
  if not file or not line then
    notify("Could not determine cursor position", vim.log.levels.WARN)
    return
  end

  local comment = store.get_at_line(file, line, side)
  if not comment and line == 1 then
    comment = store.get_file_comment(file)
  end
  if not comment then
    notify("No comment at cursor position", vim.log.levels.WARN)
    return
  end

  vim.ui.select({ "Yes", "No" }, {
    prompt = "Delete this comment?",
  }, function(choice)
    if choice == "Yes" then
      store.delete(comment.id)
      -- Schedule refresh to run after UI is closed
      vim.schedule(function()
        marks.refresh()
      end)
      notify("Comment deleted", vim.log.levels.INFO)
    end
  end)
end

function M.goto_next()
  local file, line, side = hooks.get_cursor_position()
  if not file then
    return
  end

  local comments = store.get_for_file(file, side)
  for _, comment in ipairs(comments) do
    if comment.line > line then
      vim.api.nvim_win_set_cursor(0, { comment.line, 0 })
      return
    end
  end

  notify("No more comments in this file", vim.log.levels.INFO)
end

function M.goto_prev()
  local file, line, side = hooks.get_cursor_position()
  if not file then
    return
  end

  local comments = store.get_for_file(file, side)
  for i = #comments, 1, -1 do
    local comment = comments[i]
    if comment.line < line then
      vim.api.nvim_win_set_cursor(0, { comment.line, 0 })
      return
    end
  end

  notify("No previous comments in this file", vim.log.levels.INFO)
end

function M.list()
  local config = require("review.config").get()
  local all_comments = store.get_all()

  if #all_comments == 0 then
    notify("No comments yet", vim.log.levels.INFO)
    return
  end

  -- Build display items
  local items = {}
  for _, comment in ipairs(all_comments) do
    local type_info = config.comment_types[comment.type]
    local icon = type_info and type_info.icon or "●"
    local name = type_info and type_info.name or comment.type
    local location
    local is_old = (comment.side or "new") == "old"
    if comment.line == 0 then
      location = comment.file
    elseif is_old then
      if comment.line_end and comment.line_end ~= comment.line then
        location = string.format("%s:~%d-~%d", comment.file, comment.line, comment.line_end)
      else
        location = string.format("%s:~%d", comment.file, comment.line)
      end
    elseif comment.line_end and comment.line_end ~= comment.line then
      location = string.format("%s:%d-%d", comment.file, comment.line, comment.line_end)
    else
      location = string.format("%s:%d", comment.file, comment.line)
    end
    local display = string.format("%s %s [%s] %s", icon, location, name, comment.text)
    table.insert(items, { display = display, comment = comment })
  end

  -- Show picker
  vim.ui.select(items, {
    prompt = "Comments:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if not choice then
      return
    end

    local comment = choice.comment
    local target_line = comment.line == 0 and 1 or comment.line

    -- In diff mode, load the file's diff via the explorer's own file-select
    -- callback (the maintained API), then place the cursor. Fall back to :edit
    -- for the no-diff/annotate workflow, or if the explorer API isn't available.
    local jumped = false
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    if ok then
      local tabpage = hooks.get_current_tabpage()
      local explorer = tabpage and lifecycle.get_explorer(tabpage)
      local refresh_ok, refresh = pcall(require, "codediff.ui.explorer.refresh")
      if explorer and explorer.on_file_select and refresh_ok then
        local files = refresh.get_all_files(explorer.tree) or {}
        for _, file in ipairs(files) do
          if file.data and file.data.path == comment.file then
            explorer.on_file_select(file.data)
            jumped = true
            break
          end
        end
      end
    end

    -- Non-diff (or explorer miss): open the file itself. Comments store paths
    -- relative to the git root, so resolve against it before editing.
    if not jumped then
      local path = comment.file
      if vim.fn.filereadable(path) ~= 1 then
        local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
        if vim.v.shell_error == 0 and git_root and git_root ~= "" then
          path = git_root .. "/" .. comment.file
        end
      end
      if vim.fn.filereadable(path) == 1 then
        vim.cmd("edit " .. vim.fn.fnameescape(path))
      end
    end

    -- Place the cursor after the buffer/diff has settled.
    vim.defer_fn(function()
      pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
    end, 100)
  end)
end

function M.delete_multi()
  local cfg = require("review.config").get()
  local all_comments = store.get_all()

  if #all_comments == 0 then
    notify("No comments yet", vim.log.levels.INFO)
    return
  end

  -- Build display entries
  local entries = {}
  local comment_map = {}
  for idx, comment in ipairs(all_comments) do
    local type_info = cfg.comment_types[comment.type]
    local icon = type_info and type_info.icon or "●"
    local name = type_info and type_info.name or comment.type
    local location
    local is_old = (comment.side or "new") == "old"
    if comment.line == 0 then
      location = comment.file
    elseif is_old then
      location = string.format("%s:~%d", comment.file, comment.line)
    else
      location = string.format("%s:%d", comment.file, comment.line)
    end
    local entry = string.format("%d. %s %s [%s] %s", idx, icon, location, name, comment.text)
    table.insert(entries, entry)
    comment_map[entry] = comment
  end

  -- Use fzf-lua multi-select if available, fall back to vim.ui.select
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if fzf_ok then
    fzf.fzf_exec(entries, {
      prompt = "Delete comments (Tab to select, Enter to confirm)> ",
      actions = {
        ["default"] = function(selected)
          if not selected or #selected == 0 then return end
          vim.ui.select({ "Yes", "No" }, {
            prompt = string.format("Delete %d comment(s)?", #selected),
          }, function(choice)
            if choice == "Yes" then
              for _, sel in ipairs(selected) do
                local comment = comment_map[sel]
                if comment then
                  store.delete(comment.id)
                end
              end
              vim.schedule(function()
                marks.refresh()
              end)
              notify(string.format("Deleted %d comment(s)", #selected), vim.log.levels.INFO)
            end
          end)
        end,
      },
      fzf_opts = { ["--multi"] = "" },
    })
  else
    -- Fallback: delete one at a time
    vim.ui.select(entries, { prompt = "Delete comment:" }, function(choice)
      if not choice then return end
      local comment = comment_map[choice]
      if comment then
        store.delete(comment.id)
        vim.schedule(function() marks.refresh() end)
        notify("Comment deleted", vim.log.levels.INFO)
      end
    end)
  end
end

return M
