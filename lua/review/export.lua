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

return M
