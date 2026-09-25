local M = {}

local store = require("review.store")
local hooks = require("review.hooks")
local popup = require("review.popup")
local marks = require("review.marks")

local function notify(msg, level)
  vim.notify(msg, level, { title = "review.nvim" })
end

--- Resolve a comment to an absolute filesystem path for jumping/quickfix.
--- Handles nogit:<dir> roots (strip the prefix; the dir + basename is the file)
--- and normal git roots (root .. "/" .. rel). `repo_root` is the fallback root
--- resolved for the current buffer when the comment has no stored root.
---@param comment Comment
---@param repo_root? string
---@return string
local function comment_abspath(comment, repo_root)
  local storage = require("review.storage")
  local root = comment.git_root or repo_root
  if root and root ~= "" then
    if storage.is_nogit_root(root) then
      return root:sub(#storage.NOGIT_PREFIX + 1) .. "/" .. comment.file
    end
    return root .. "/" .. comment.file
  end
  return vim.fn.fnamemodify(comment.file, ":p")
end

--- Resolve the git root of the current buffer's file, load that repo's comments
--- and return them sorted. Both :Review quickfix and :Review list scope to the
--- repo you are looking at, so a session that touched several repos shows only
--- the current repo's comments.
---@return string|nil git_root
---@return Comment[] comments for that repo
local function current_repo_comments()
  local storage = require("review.storage")
  local bufname = vim.api.nvim_buf_get_name(0)
  local git_root
  if bufname and bufname ~= "" and not bufname:match("^%w+://") then
    git_root = storage.root_for(bufname)
  end
  -- Fall back to a codediff session root, then to cwd's repo.
  if not git_root then
    git_root = hooks.get_git_root()
  end
  if not git_root then
    git_root = storage.git_root_for(vim.fn.getcwd())
  end
  store.load(git_root)
  return git_root, store.get_for_repo(git_root)
end

--- Resolve the comment target at the cursor for edit/delete, working both in a
--- codediff session and in a plain buffer. Inside a session, defer to the
--- session-aware hook (knows old/new sides). Outside one, resolve the current
--- buffer's own file the same way :Review annotate does, loading that repo (or
--- nogit root) so store lookups see its comments.
---@return string|nil file relative path
---@return number|nil line 1-based cursor line
---@return "old"|"new"|nil side
local function cursor_target()
  local file, line, side = hooks.get_cursor_position()
  if file and line then
    return file, line, side
  end
  -- No codediff session: fall back to the current normal buffer.
  local bufname = vim.api.nvim_buf_get_name(0)
  if not bufname or bufname == "" or bufname:match("^%w+://") then
    return nil, nil, nil
  end
  local storage = require("review.storage")
  local root = storage.root_for(bufname)
  if not root or root == "" then
    return nil, nil, nil
  end
  store.load(root)
  local rel
  if storage.is_nogit_root(root) then
    rel = vim.fn.fnamemodify(bufname, ":t")
  else
    rel = bufname:gsub("^" .. vim.pesc(root) .. "/", "")
  end
  return rel, vim.api.nvim_win_get_cursor(0)[1], "new"
end

---@param initial_type? string a comment type key from config.comment_types
function M.add_at_cursor(initial_type)
  local file, line, side, git_root = hooks.get_cursor_position()
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
      store.add(file, line, comment_type, text, nil, side, git_root)
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
  local file, _, _, git_root = hooks.get_cursor_position()
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
        store.add(file, 0, comment_type, text, nil, nil, git_root)
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
  local file, start_line, end_line, side, git_root = hooks.get_visual_range()
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
      store.add(file, start_line, comment_type, text, end_line, side, git_root)
      vim.schedule(function()
        marks.refresh()
      end)
      notify(string.format("Added %s comment", comment_type), vim.log.levels.INFO)
    end
  end)
end

--- Refresh marks after an edit/delete. In a codediff session, marks.refresh()
--- re-renders the diff buffers. Outside a session it renders nothing (no
--- session buffers), so re-render the current normal buffer directly with the
--- known rel path/side, which clears stale marks and redraws from the store.
---@param file string rel path used for the store lookup
---@param side "old"|"new"|nil
local function refresh_marks(file, side)
  if hooks.get_session() then
    marks.refresh()
    return
  end
  marks.render_for_buffer(vim.api.nvim_get_current_buf(), side or "new", file)
end

--- Refresh marks after a bulk operation that may touch several files (delete_multi).
--- In a codediff session, marks.refresh() re-renders the diff buffers. Outside a
--- session, re-render every open normal buffer so deletions in any of them are
--- reflected without a manual :Review marks toggle. render_for_buffer clears the
--- namespace first, so removed comments drop their marks.
local function refresh_marks_bulk()
  if hooks.get_session() then
    marks.refresh()
    return
  end
  local review = require("review")
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      review._render_marks_for_buffer(bufnr)
    end
  end
end

function M.edit_at_cursor()
  local file, line, side = cursor_target()
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
        refresh_marks(file, side)
      end)
      notify("Comment updated", vim.log.levels.INFO)
    end
  end)
end

function M.delete_at_cursor()
  local file, line, side = cursor_target()
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
        refresh_marks(file, side)
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
  local repo_root, all_comments = current_repo_comments()

  if #all_comments == 0 then
    notify("No comments for this repo yet", vim.log.levels.INFO)
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

    -- Non-diff (or explorer miss): open the file itself. Prefer the comment's
    -- own git_root (then the repo root resolved for this buffer) so a comment
    -- from a sibling repo opens the right file regardless of nvim's cwd.
    if not jumped then
      local path = comment.file
      if vim.fn.filereadable(path) ~= 1 then
        local abs = comment_abspath(comment, repo_root)
        if abs and abs ~= "" then
          path = abs
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
  local _, all_comments = current_repo_comments()

  if #all_comments == 0 then
    notify("No comments for this repo yet", vim.log.levels.INFO)
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
                refresh_marks_bulk()
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
        vim.schedule(function() refresh_marks_bulk() end)
        notify("Comment deleted", vim.log.levels.INFO)
      end
    end)
  end
end

--- Populate the quickfix list with the current repo's comments and open it, so
--- you can :cnext/:cprev and jump to each. Scoped to the git root of the current
--- buffer's file: a session that touched several repos shows only this repo's
--- comments. Jump targets are built from each comment's stored git_root, so they
--- resolve regardless of nvim's cwd.
function M.quickfix()
  local cfg = require("review.config").get()
  local repo_root, comments = current_repo_comments()

  if #comments == 0 then
    notify("No comments for this repo yet", vim.log.levels.INFO)
    return
  end

  local absolute = cfg.quickfix and cfg.quickfix.path_style == "absolute"

  local items = {}
  for _, comment in ipairs(comments) do
    local type_info = cfg.comment_types[comment.type]
    local name = type_info and type_info.name or comment.type
    -- Absolute jump target: prefer the comment's own git_root, then the repo
    -- root resolved for this buffer, else fnamemodify(:p) as a last resort.
    -- comment_abspath handles nogit:<dir> roots for non-git files.
    local abs = comment_abspath(comment, repo_root)
    local side = (comment.side or "new") == "old" and " (old)" or ""
    table.insert(items, {
      filename = abs,
      module = absolute and abs or comment.file,
      lnum = comment.line == 0 and 1 or comment.line,
      col = 1,
      text = string.format("[%s]%s %s", string.upper(name), side, comment.text),
    })
  end

  vim.fn.setqflist({}, " ", { title = "Review comments", items = items })
  vim.cmd("copen")
end

return M
