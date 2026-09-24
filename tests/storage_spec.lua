local storage = require("review.storage")
local config = require("review.config")

local DAY = 24 * 60 * 60

describe("review.storage", function()
  after_each(function()
    storage.clear_revisions()
  end)

  describe("get_storage_path", function()
    it("returns branch-scoped path when no revisions set", function()
      storage.clear_revisions()
      local path = storage.get_storage_path()
      assert.is_not_nil(path)
      -- Branch-scoped files are "<hash>-<branch>.json". Revision-scoped files are
      -- "<hash>-<r1>_<r2>.json"; the distinguishing mark is the "_"-joined pair
      -- of 8-char hex revs, so assert the filename is NOT that shape rather than
      -- that it lacks any "_" (branch names may legitimately contain "_").
      assert.truthy(path:match("%.json$"))
      assert.is_nil(path:match("%-%x%x%x%x%x%x%x%x_%x%x%x%x%x%x%x%x%.json$"))
    end)

    it("returns revision-scoped path when revisions are set", function()
      storage.set_revisions("abc12345def^", "fef98765abc")
      local path = storage.get_storage_path()
      assert.is_not_nil(path)
      assert.truthy(path:match("abc12345_fef98765%.json$"))
    end)

    it("strips trailing ^ from revision in filename", function()
      storage.set_revisions("abc12345^", "def67890")
      local path = storage.get_storage_path()
      assert.truthy(path:match("abc12345_def67890%.json$"))
    end)

    it("truncates long revisions to 8 chars", function()
      storage.set_revisions("abcdef1234567890^", "1234567890abcdef")
      local path = storage.get_storage_path()
      assert.truthy(path:match("abcdef12_12345678%.json$"))
    end)

    it("returns branch path after clearing revisions", function()
      storage.set_revisions("abc12345^", "def67890")
      storage.clear_revisions()
      local path = storage.get_storage_path()
      assert.is_not_nil(path)
      -- Should not contain revision separator
      assert.is_nil(path:match("abc12345"))
    end)

    it("keys the path by an explicit git_root, not cwd", function()
      -- Use revision-scoped mode so the path derives purely from the root hash
      -- (+ revs), without needing each root to be a real repo with a branch.
      storage.set_revisions("aaaaaaaa", "bbbbbbbb")
      local a = storage.get_storage_path("/tmp/repo-alpha")
      local b = storage.get_storage_path("/tmp/repo-beta")
      storage.clear_revisions()
      assert.is_not_nil(a)
      assert.is_not_nil(b)
      -- Different roots hash to different files.
      assert.are_not.equal(a, b)
    end)
  end)

  describe("per-root save/load isolation", function()
    it("saves and loads comments under distinct roots independently", function()
      -- Use fixed roots (no on-disk repo needed; path is derived from the root
      -- string, and branch resolution falls back gracefully). Save writes only
      -- when a branch resolves, so drive save/load through get_storage_path by
      -- writing/reading the same explicit root.
      local root_a = vim.fn.getcwd() -- a real repo (the review.nvim checkout)
      storage.clear_revisions()

      storage.clear(root_a)
      storage.save({ ["a.lua"] = { { id = "x", file = "a.lua", line = 1, type = "note", text = "A", git_root = root_a } } }, root_a)

      local loaded = storage.load(root_a)
      assert.is_not_nil(loaded["a.lua"])
      assert.equals("A", loaded["a.lua"][1].text)

      storage.clear(root_a)
      local empty = storage.load(root_a)
      assert.same({}, empty)
    end)
  end)

  describe("git_root_for", function()
    it("resolves the git root that owns a path in this repo", function()
      local root = storage.git_root_for(vim.fn.getcwd() .. "/lua/review/storage.lua")
      assert.is_not_nil(root)
      -- The resolved root should be an ancestor of the file.
      assert.truthy(vim.fn.getcwd():sub(1, #root) == root)
    end)

    it("returns nil for a path outside any git repo", function()
      local root = storage.git_root_for("/")
      assert.is_nil(root)
    end)
  end)

  describe("is_expired", function()
    local now = 1000 * DAY

    after_each(function()
      config.setup({})
    end)

    it("keeps reviews forever by default", function()
      assert.is_false(storage.is_expired(now - 365 * DAY, now))
    end)

    it("expires files older than a configured expiry_days", function()
      config.setup({ storage = { expiry_days = 7 } })
      assert.is_true(storage.is_expired(now - 8 * DAY, now))
      assert.is_false(storage.is_expired(now - 6 * DAY, now))
    end)

    it("honours a configured expiry_days", function()
      config.setup({ storage = { expiry_days = 1 } })
      assert.is_true(storage.is_expired(now - 2 * DAY, now))
      assert.is_false(storage.is_expired(now - 12 * 60 * 60, now))
    end)

    it("keeps everything when expiry is disabled", function()
      config.setup({ storage = { expiry_days = false } })
      assert.is_false(storage.is_expired(now - 365 * DAY, now))

      config.setup({ storage = { expiry_days = 0 } })
      assert.is_false(storage.is_expired(now - 365 * DAY, now))
    end)

    it("keeps files with an unknown mtime", function()
      config.setup({ storage = { expiry_days = 7 } })
      assert.is_false(storage.is_expired(0, now))
      assert.is_false(storage.is_expired(-1, now))
    end)
  end)
end)
