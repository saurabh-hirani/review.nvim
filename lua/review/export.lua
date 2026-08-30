local M = {}

local config = require("review.config")
local store = require("review.store")

local function notify(msg, level)
  vim.notify(msg, level, { title = "review.nvim" })
end

---@return string|nil
local function get_git_root()
  local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    if result and result ~= "" then
      return result:gsub("%s+$", "")
    end
  end
  return nil
end

---@param file string
---@return string
local function resolve_path(file)
  local cfg = config.get()
  if cfg.export.path_style == "absolute" then
    local git_root = get_git_root()
    if git_root then
      return git_root .. "/" .. file
    end
  end
  return file
end

---Type keys allowed in the export, or nil when every type is exported.
---@return table<string, true>|nil
local function allowed_types()
  local types = config.get().export.types
  if not types then
    return nil
  end
  local allowed = {}
  for _, type_key in ipairs(types) do
    allowed[type_key] = true
  end
  return allowed
end

---Comments included in the export, filtered by export.types.
---@return Comment[]
function M.exported_comments()
  local allowed = allowed_types()
  if not allowed then
    return store.get_all()
  end
  return vim.tbl_filter(function(comment)
    return allowed[comment.type] == true
  end, store.get_all())
end

---@return string
function M.generate_markdown()
  local all_comments = M.exported_comments()

  if #all_comments == 0 then
    return "No comments yet."
  end

  local lines = {}
  local cfg = config.get()
  local allowed = allowed_types()

  -- Header (configurable; false/empty to omit)
  if cfg.export.header and cfg.export.header ~= "" then
    table.insert(lines, cfg.export.header)
    table.insert(lines, "")
  end

  -- Build comment types description from exported types in popup order
  local type_descriptions = {}
  for _, type_key in ipairs(cfg.popup.type_order) do
    if not allowed or allowed[type_key] then
      local type_info = cfg.comment_types[type_key]
      local name = type_info and type_info.name or type_key
      table.insert(type_descriptions, string.upper(name))
    end
  end
  table.insert(lines, "Comment types: " .. table.concat(type_descriptions, ", "))
  if cfg.export.side_note and cfg.export.side_note ~= "" then
    table.insert(lines, cfg.export.side_note)
  end
  table.insert(lines, "")

  -- Numbered list of comments
  for i, comment in ipairs(all_comments) do
    local type_name = string.upper(comment.type)
    local location
    local file_path = resolve_path(comment.file)
    local is_old = (comment.side or "new") == "old"
    if comment.line == 0 then
      location = file_path
    elseif is_old then
      if comment.line_end and comment.line_end ~= comment.line then
        location = string.format("%s:~%d-~%d", file_path, comment.line, comment.line_end)
      else
        location = string.format("%s:~%d", file_path, comment.line)
      end
    elseif comment.line_end and comment.line_end ~= comment.line then
      location = string.format("%s:%d-%d", file_path, comment.line, comment.line_end)
    else
      location = string.format("%s:%d", file_path, comment.line)
    end
    table.insert(lines, string.format("%d. **[%s]** `%s` - %s", i, type_name, location, comment.text))
  end

  return table.concat(lines, "\n")
end

function M.to_clipboard()
  local markdown = M.generate_markdown()
  local count = #M.exported_comments()

  if count == 0 then
    notify("No comments to export", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", markdown)
  vim.fn.setreg("*", markdown)

  -- Show content in a bottom split (editable — save to re-copy to clipboard)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(markdown, "\n"))
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
  vim.api.nvim_buf_set_name(buf, "review://export")

  -- Remember current window to restore focus after closing
  local prev_win = vim.api.nvim_get_current_win()

  -- Open at bottom with appropriate height
  local line_count = #vim.split(markdown, "\n")
  local height = math.min(line_count + 1, 15)
  vim.cmd("botright " .. height .. "split")
  vim.api.nvim_win_set_buf(0, buf)

  -- On save, copy buffer contents to clipboard
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = table.concat(lines, "\n")
      vim.fn.setreg("+", content)
      vim.fn.setreg("*", content)
      vim.api.nvim_set_option_value("modified", false, { buf = buf })
      notify("Copied to clipboard", vim.log.levels.INFO)
    end,
  })

  -- Map q to close the preview and restore focus
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(0, true)
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end, { buffer = buf, nowait = true })

  notify(string.format("Exported %d comment(s) to clipboard", count), vim.log.levels.INFO)
end

function M.preview()
  local markdown = M.generate_markdown()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(markdown, "\n"))
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
end

function M.to_sidekick()
  local ok, sidekick_cli = pcall(require, "sidekick.cli")
  if not ok then
    notify("sidekick.nvim not installed", vim.log.levels.ERROR)
    return
  end

  local count = #M.exported_comments()
  if count == 0 then
    notify("No comments to send", vim.log.levels.WARN)
    return
  end

  local markdown = M.generate_markdown()
  sidekick_cli.send({ msg = markdown })
  notify(string.format("Sent %d comment(s) to sidekick", count), vim.log.levels.INFO)
end

---Send `text` to a single tmux pane `target` via send-keys, optionally pressing Enter.
---@param target string
---@param text string
---@param send_enter boolean
local function tmux_send(target, text, send_enter)
  -- Escape single quotes for the single-quoted shell argument.
  local escaped = text:gsub("'", "'\\''")
  vim.fn.system(string.format("tmux send-keys -t '%s' '%s'", target, escaped))
  if send_enter then
    vim.fn.system(string.format("tmux send-keys -t '%s' Enter", target))
  end
end

---Normalise a picker choice into a tmux pane target. Exposed for testing.
---@param choice string
---@return string
function M._tmux_target_of(choice)
  if choice == "+ (next pane)" or choice == "+" then
    return "+"
  end
  -- Lines from `tmux list-panes` look like "1.0: nvim [win]"; take the "1.0".
  local index = choice:match("^(%d+%.%d+):")
  return index or choice
end

function M.to_tmux()
  if vim.fn.executable("tmux") ~= 1 then
    notify("tmux not found on PATH", vim.log.levels.ERROR)
    return
  end
  if vim.env.TMUX == nil then
    notify("Not inside a tmux session", vim.log.levels.ERROR)
    return
  end

  local count = #M.exported_comments()
  if count == 0 then
    notify("No comments to send", vim.log.levels.WARN)
    return
  end

  local markdown = M.generate_markdown()
  local cfg = config.get().tmux
  local send_enter = cfg.send_enter == true

  -- If auto_select_panes is set, send directly without prompting.
  if cfg.auto_select_panes and #cfg.auto_select_panes > 0 then
    for _, target in ipairs(cfg.auto_select_panes) do
      tmux_send(target, markdown, send_enter)
    end
    notify(string.format("Sent %d comment(s) to tmux", count), vim.log.levels.INFO)
    return
  end

  -- Build the pane list: "+ (next pane)", configured panes, then live panes.
  local items = { "+ (next pane)" }
  for _, pane in ipairs(cfg.panes or {}) do
    if pane ~= "+" then
      table.insert(items, pane)
    end
  end
  local live = vim.fn.systemlist(
    'tmux list-panes -s -F "#{window_index}.#{pane_index}: #{pane_current_command} [#{window_name}]"'
  )
  if vim.v.shell_error == 0 then
    vim.list_extend(items, live)
  end

  local function send_to(selected)
    if not selected or #selected == 0 then
      return
    end
    for _, choice in ipairs(selected) do
      tmux_send(M._tmux_target_of(choice), markdown, send_enter)
    end
    notify(string.format("Sent %d comment(s) to tmux", count), vim.log.levels.INFO)
  end

  -- fzf-lua multi-select if available (same pattern as delete_multi), else vim.ui.select.
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if fzf_ok then
    fzf.fzf_exec(items, {
      prompt = "Send to tmux pane(s) (Tab to select, Enter to confirm)> ",
      actions = {
        ["default"] = function(selected) send_to(selected) end,
      },
      fzf_opts = { ["--multi"] = "" },
    })
  else
    vim.ui.select(items, { prompt = "Send to tmux pane:" }, function(choice)
      if choice then send_to({ choice }) end
    end)
  end
end

return M
