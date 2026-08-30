local M = {}

local data_dir = vim.fn.stdpath("data") .. "/review"

---@type {rev1: string, rev2: string}|nil
local current_revisions = nil

function M.set_revisions(rev1, rev2)
  current_revisions = (rev1 and rev2) and { rev1 = rev1, rev2 = rev2 } or nil
end

function M.clear_revisions()
  current_revisions = nil
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

---@return string|nil
local function get_git_branch()
  local handle = io.popen("git rev-parse --abbrev-ref HEAD 2>/dev/null")
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

---@return string|nil
function M.get_storage_path()
  local git_root = get_git_root()
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

  local branch = get_git_branch()
  if not branch then
    return nil
  end

  local safe_branch = branch:gsub("[^%w%-_]", "_")
  return string.format("%s/%s-%s.json", data_dir, project_hash, safe_branch)
end

---@param comments table
function M.save(comments)
  local path = M.get_storage_path()
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

---@return table
function M.load()
  M.cleanup_expired()

  local path = M.get_storage_path()
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

function M.clear()
  local path = M.get_storage_path()
  if path then
    os.remove(path)
  end
end

return M
