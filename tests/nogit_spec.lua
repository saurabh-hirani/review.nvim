local storage = require("review.storage")
local store = require("review.store")

describe("review non-git (path-based) support", function()
  after_each(function()
    storage.clear_revisions()
    store.reset()
  end)

  describe("storage.root_for / is_nogit_root", function()
    it("returns the git root for a path inside a repo", function()
      local root = storage.root_for(vim.fn.getcwd() .. "/lua/review/storage.lua")
      assert.is_not_nil(root)
      assert.is_false(storage.is_nogit_root(root))
    end)

    it("returns a nogit:<dir> root for a path outside any repo", function()
      local root = storage.root_for("/nonexistent-xyz/scratch.txt")
      assert.is_not_nil(root)
      assert.is_true(storage.is_nogit_root(root))
      -- The dir portion is the file's absolute parent directory.
      assert.equals(storage.NOGIT_PREFIX .. "/nonexistent-xyz", root)
    end)

    it("returns nil for empty input", function()
      assert.is_nil(storage.root_for(nil))
      assert.is_nil(storage.root_for(""))
    end)
  end)

  describe("storage.get_storage_path for nogit roots", function()
    it("builds a branchless <hash>-nogit.json filename", function()
      local root = storage.NOGIT_PREFIX .. "/tmp/some-dir"
      local path = storage.get_storage_path(root)
      assert.is_not_nil(path)
      assert.truthy(path:match("%-nogit%.json$"))
    end)

    it("keys distinct nogit dirs to distinct files", function()
      local a = storage.get_storage_path(storage.NOGIT_PREFIX .. "/tmp/dir-a")
      local b = storage.get_storage_path(storage.NOGIT_PREFIX .. "/tmp/dir-b")
      assert.is_not_nil(a)
      assert.is_not_nil(b)
      assert.are_not.equal(a, b)
    end)

    it("ignores an active revision range for nogit roots", function()
      storage.set_revisions("aaaaaaaa", "bbbbbbbb")
      local path = storage.get_storage_path(storage.NOGIT_PREFIX .. "/tmp/dir-c")
      storage.clear_revisions()
      -- Still the nogit filename, not the revision-scoped one.
      assert.truthy(path:match("%-nogit%.json$"))
      assert.is_nil(path:match("aaaaaaaa_bbbbbbbb"))
    end)
  end)

  describe("store round-trip under a nogit root", function()
    it("persists and reloads a comment keyed by a nogit root", function()
      local root = storage.NOGIT_PREFIX .. "/tmp/nogit-roundtrip"
      storage.clear(root)

      store.reset()
      store.add("scratch.txt", 3, "note", "outside git", nil, "new", root)

      -- New session: reset memory, reload only this root.
      store.reset()
      store.load(root)

      local comments = store.get_for_repo(root)
      assert.equals(1, #comments)
      assert.equals("scratch.txt", comments[1].file)
      assert.equals("outside git", comments[1].text)
      assert.equals(root, comments[1].git_root)

      storage.clear(root)
      store.reset()
      store.load(root)
      assert.equals(0, #store.get_for_repo(root))
    end)

    it("keeps nogit and git comments in separate storage files", function()
      local nogit_root = storage.NOGIT_PREFIX .. "/tmp/nogit-sep"
      local git_root = vim.fn.getcwd()
      storage.clear(nogit_root)
      storage.clear(git_root)

      store.reset()
      store.add("scratch.txt", 1, "note", "N", nil, "new", nogit_root)
      store.add("lua/review/init.lua", 1, "note", "G", nil, "new", git_root)

      store.reset()
      store.load(nogit_root)
      local only_nogit = store.get_for_repo(nogit_root)
      assert.equals(1, #only_nogit)
      assert.equals("N", only_nogit[1].text)

      storage.clear(nogit_root)
      storage.clear(git_root)
    end)
  end)
end)
