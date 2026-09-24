local M = {}

local storage = require("review.storage")

---@class Comment
---@field id string
---@field file string path relative to git_root (or cwd's repo when git_root is nil)
---@field line number
---@field line_end? number
---@field side? "old"|"new"
---@field git_root? string absolute path of the git root `file` is relative to
---@field type string a comment type key from config.comment_types
---@field text string
---@field created_at number

-- In-memory comments keyed by file path (relative to their git root). Matching
-- helpers (get_at_line, get_for_file, ...) work off this map. Persistence,
-- however, is per-repo: comments are grouped by git_root and each group is saved
-- to its own storage file. This lets one nvim session hold comments for several
-- repos at once while each repo keeps its own on-disk review file.
---@type table<string, Comment[]>
M.comments = {}

-- git roots whose storage files have been loaded into M.comments this session.
-- A special key `false` marks "cwd repo loaded" (comments with no git_root).
---@type table<string|boolean, true>
local loaded_roots = {}

local id_counter = 0

---@return string
local function generate_id()
  id_counter = id_counter + 1
  return string.format("comment_%d_%d", os.time(), id_counter)
end

---Group all in-memory comments by their git_root (nil -> false bucket).
---@return table<string|boolean, table<string, Comment[]>>
local function group_by_root()
  local groups = {}
  for file, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      local root = comment.git_root or false
      groups[root] = groups[root] or {}
      groups[root][file] = groups[root][file] or {}
      table.insert(groups[root][file], comment)
    end
  end
  return groups
end

---Persist a single repo's comments to its own storage file. `root` is the
---absolute git root, or false for the cwd-repo bucket (git_root nil).
---@param root string|boolean
local function persist_root(root)
  local groups = group_by_root()
  local repo_comments = groups[root] or {}
  local git_root = (root ~= false) and root or nil
  storage.save(repo_comments, git_root)
end

---Persist every repo touched in memory. Used after bulk operations.
local function persist_all()
  -- Save each currently-loaded root even if it became empty (so deletes stick).
  local groups = group_by_root()
  local roots = {}
  for root in pairs(loaded_roots) do roots[root] = true end
  for root in pairs(groups) do roots[root] = true end
  for root in pairs(roots) do
    local git_root = (root ~= false) and root or nil
    storage.save(groups[root] or {}, git_root)
  end
end

function M.reset()
  M.comments = {}
  loaded_roots = {}
  id_counter = 0
end

---Load a specific repo's comments into memory (idempotent per root/session).
---Pass nil to load the cwd repo's comments.
---@param git_root? string
function M.load(git_root)
  local key = git_root or false
  if loaded_roots[key] then
    return
  end
  local data = storage.load(git_root)
  for file, comments in pairs(data) do
    -- Merge, avoiding duplicate ids if the same file appears under two roots.
    M.comments[file] = M.comments[file] or {}
    local seen = {}
    for _, c in ipairs(M.comments[file]) do seen[c.id] = true end
    for _, c in ipairs(comments) do
      if not seen[c.id] then
        table.insert(M.comments[file], c)
      end
      local num = tonumber(tostring(c.id):match("comment_%d+_(%d+)"))
      if num and num > id_counter then
        id_counter = num
      end
    end
  end
  loaded_roots[key] = true
end

---@param file string relative path
---@param line number
---@param type string a comment type key from config.comment_types
---@param text string
---@param line_end? number
---@param side? "old"|"new"
---@param git_root? string absolute git root `file` is relative to
---@return Comment
function M.add(file, line, type, text, line_end, side, git_root)
  if not M.comments[file] then
    M.comments[file] = {}
  end

  local comment = {
    id = generate_id(),
    file = file,
    line = line,
    line_end = (line_end and line_end ~= line) and line_end or nil,
    side = side or "new",
    git_root = git_root,
    type = type,
    text = text,
    created_at = os.time(),
  }

  table.insert(M.comments[file], comment)
  -- Mark this repo loaded so a later M.load(git_root) does not clobber the
  -- just-added comment by reloading from a stale/empty file.
  loaded_roots[git_root or false] = true
  persist_root(git_root or false)
  return comment
end

---@param id string
---@return Comment|nil
function M.get(id)
  for _, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      if comment.id == id then
        return comment
      end
    end
  end
  return nil
end

---@param file string
---@param side? "old"|"new"
---@return Comment[]
function M.get_for_file(file, side)
  local comments = M.comments[file] or {}
  if not side then
    return comments
  end
  local filtered = {}
  for _, comment in ipairs(comments) do
    if comment.line == 0 or (comment.side or "new") == side then
      table.insert(filtered, comment)
    end
  end
  return filtered
end

---@param file string
---@return Comment|nil
function M.get_file_comment(file)
  local comments = M.comments[file] or {}
  for _, comment in ipairs(comments) do
    if comment.line == 0 then
      return comment
    end
  end
  return nil
end

---@param file string
---@param line number
---@param side? "old"|"new"
---@return Comment|nil
function M.get_at_line(file, line, side)
  local comments = M.comments[file] or {}
  for _, comment in ipairs(comments) do
    local line_end = comment.line_end or comment.line
    if line >= comment.line and line <= line_end then
      if not side or (comment.side or "new") == side then
        return comment
      end
    end
  end
  return nil
end

---@param file string
---@param start_line number
---@param end_line number
---@param side? "old"|"new"
---@return Comment|nil
function M.get_overlapping(file, start_line, end_line, side)
  local comments = M.comments[file] or {}
  for _, comment in ipairs(comments) do
    local c_end = comment.line_end or comment.line
    if comment.line <= end_line and c_end >= start_line then
      if not side or (comment.side or "new") == side then
        return comment
      end
    end
  end
  return nil
end

---@param id string
---@param text string
---@param new_type? string a comment type key from config.comment_types
---@return boolean
function M.update(id, text, new_type)
  for _, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      if comment.id == id then
        comment.text = text
        if new_type then
          comment.type = new_type
        end
        persist_root(comment.git_root or false)
        return true
      end
    end
  end
  return false
end

---@param id string
---@return boolean
function M.delete(id)
  for file, comments in pairs(M.comments) do
    for i, comment in ipairs(comments) do
      if comment.id == id then
        local root = comment.git_root or false
        table.remove(comments, i)
        if #comments == 0 then
          M.comments[file] = nil
        end
        persist_root(root)
        return true
      end
    end
  end
  return false
end

---Sort helper shared by get_all / get_for_repo.
---@param list Comment[]
local function sort_comments(list)
  table.sort(list, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.line < b.line
  end)
  return list
end

---@return Comment[]
function M.get_all()
  local all = {}
  for _, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      table.insert(all, comment)
    end
  end
  return sort_comments(all)
end

---Comments belonging to a single repo root. Comments with no git_root are
---"unattributed" (legacy, or authored outside a resolvable repo) and are
---included for whatever repo is asked, so they never silently disappear.
---@param git_root? string
---@return Comment[]
function M.get_for_repo(git_root)
  local all = {}
  for _, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      if comment.git_root == nil or (comment.git_root == git_root) then
        table.insert(all, comment)
      end
    end
  end
  return sort_comments(all)
end

---@return table<string, Comment[]>
function M.get_all_by_file()
  return M.comments
end

---@return number
function M.count()
  local count = 0
  for _, comments in pairs(M.comments) do
    count = count + #comments
  end
  return count
end

---Clear all in-memory comments and every loaded repo's storage file.
function M.clear()
  local roots = {}
  for root in pairs(loaded_roots) do roots[root] = true end
  for _, comments in pairs(M.comments) do
    for _, c in ipairs(comments) do roots[c.git_root or false] = true end
  end
  M.reset()
  for root in pairs(roots) do
    local git_root = (root ~= false) and root or nil
    storage.clear(git_root)
  end
  storage.clear_revisions()
end

return M
