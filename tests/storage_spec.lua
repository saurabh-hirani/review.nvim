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
      assert.is_nil(path:match("_"))
      assert.truthy(path:match("%.json$"))
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
