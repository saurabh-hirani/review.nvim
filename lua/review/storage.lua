local M = {}

-- Storage directory. Overridable via $REVIEW_NVIM_DATA_DIR so tests can isolate
-- from the user's real review data (and from each other).
local data_dir = vim.env.REVIEW_NVIM_DATA_DIR or (vim.fn.stdpath("data") .. "/review")

---@type {rev1: string, rev2: string}|nil
local current_revisions = nil

function M.set_revisions(rev1, rev2)
  current_revisions = (rev1 and rev2) and { rev1 = rev1, rev2 = rev2 } or nil
end

function M.clear_revisions()
  current_revisions = nil
end

---Git root of nvim's cwd (fallback when no explicit root is supplied).
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

---Git root that owns an arbitrary file or directory path, independent of cwd.
---This is what lets one nvim session store comments per-repo across several
---repos: the storage key follows the file, not the working directory.
---@param path string absolute or relative file/dir path
---@return string|nil
function M.git_root_for(path)
  if not path or path == "" then
    return nil
  end
  local dir = vim.fn.fnamemodify(path, ":p:h")
  local cmd = string.format("git -C %s rev-parse --show-toplevel 2>/dev/null", vim.fn.shellescape(dir))
  local handle = io.popen(cmd)
  if handle then
    local result = handle:read("*a")
    handle:close()
    if result and result ~= "" then
      return result:gsub("%s+$", "")
    end
  end
  return nil
end

---Current branch of the repo at `git_root` (or cwd's repo when nil).
---@param git_root? string
---@return string|nil
local function get_git_branch(git_root)
  local cmd
  if git_root and git_root ~= "" then
    cmd = string.format("git -C %s rev-parse --abbrev-ref HEAD 2>/dev/null", vim.fn.shellescape(git_root))
  else
    cmd = "git rev-parse --abbrev-ref HEAD 2>/dev/null"
  end
  local handle = io.popen(cmd)
  if handle then
    local result = handle:read("*a")
    handle:close()
    if result and result ~= "" then
      return result:gsub("%s+$", "")
    end
  end
  return nil
end

---@param str string
---@return string
local function hash(str)
  local h = 0
  for i = 1, #str do
    h = ((h * 31) + string.byte(str, i)) % 2147483647
  end
  return string.format("%x", h)
end

---@param rev string
---@return string
local function short_rev(rev)
  return rev:gsub("%^$", ""):sub(1, 8)
end

---Storage file path for a given repo root (defaults to cwd's repo). The key is
---hash(git_root) plus the repo's branch (or the revision range), so each repo
---and branch gets its own file regardless of nvim's cwd.
---@param git_root? string absolute repo root; nil falls back to cwd's repo
---@return string|nil
function M.get_storage_path(git_root)
  git_root = git_root or get_git_root()
  if not git_root then
    return nil
  end

  local project_hash = hash(git_root)

  -- Ensure directory exists (pcall to suppress error if exists)
  pcall(vim.fn.mkdir, data_dir, "p")

  if current_revisions then
    local r1 = short_rev(current_revisions.rev1)
    local r2 = short_rev(current_revisions.rev2)
    return string.format("%s/%s-%s_%s.json", data_dir, project_hash, r1, r2)
  end

  local branch = get_git_branch(git_root)
  if not branch then
    return nil
  end

  local safe_branch = branch:gsub("[^%w%-_]", "_")
  return string.format("%s/%s-%s.json", data_dir, project_hash, safe_branch)
end

---@param comments table
---@param git_root? string repo root to save under (defaults to cwd's repo)
function M.save(comments, git_root)
  local path = M.get_storage_path(git_root)
  if not path then
    return
  end

  local data = vim.fn.json_encode(comments)
  local file = io.open(path, "w")
  if file then
    file:write(data)
    file:close()
  end
end

local cleanup_done = false

---Is a saved review file past its expiry?
---@param mtime number file modification time (0 or less when unknown)
---@param now? number defaults to os.time()
---@return boolean
function M.is_expired(mtime, now)
  local expiry_days = require("review.config").get().storage.expiry_days
  -- false/0/negative keeps reviews forever
  if not expiry_days or expiry_days <= 0 then
    return false
  end
  if mtime <= 0 then
    return false
  end
  return ((now or os.time()) - mtime) > (expiry_days * 24 * 60 * 60)
end

function M.cleanup_expired()
  if cleanup_done then
    return
  end
  cleanup_done = true

  vim.defer_fn(function()
    local files = vim.fn.glob(data_dir .. "/*.json", false, true)
    local now = os.time()
    for _, filepath in ipairs(files) do
      if M.is_expired(vim.fn.getftime(filepath), now) then
        os.remove(filepath)
      end
    end
  end, 0)
end

---@param git_root? string repo root to load from (defaults to cwd's repo)
---@return table
function M.load(git_root)
  M.cleanup_expired()

  local path = M.get_storage_path(git_root)
  if not path then
    return {}
  end

  local file = io.open(path, "r")
  if not file then
    return {}
  end

  local content = file:read("*a")
  file:close()

  if content and content ~= "" then
    local ok, data = pcall(vim.fn.json_decode, content)
    if ok and data then
      return data
    end
  end

  return {}
end

---@param git_root? string repo root to clear (defaults to cwd's repo)
function M.clear(git_root)
  local path = M.get_storage_path(git_root)
  if path then
    os.remove(path)
  end
end

return M
