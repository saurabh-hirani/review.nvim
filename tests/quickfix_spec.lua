local store = require("review.store")
local comments = require("review.comments")
local config = require("review.config")

-- :Review quickfix and :Review list scope to the git repo of the current
-- buffer's file. A session that touched several repos must show only the
-- current repo's comments, and jump targets must be built from each comment's
-- stored git_root so they resolve regardless of nvim's cwd.

describe("review.comments quickfix", function()
  local repo_root = vim.fn.getcwd() -- the review.nvim checkout is a git repo
  local other_root = "/some/other/repo"
  local bufnr

  before_each(function()
    store.clear()
    config.setup()
    -- A buffer whose file lives in this repo, so current_repo_comments resolves
    -- repo_root for it.
    bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(bufnr, repo_root .. "/lua/review/init.lua")
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    vim.fn.setqflist({}, "r")
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("lists only the current repo's comments", function()
    store.add("lua/review/init.lua", 3, "question", "this repo", nil, "new", repo_root)
    store.add("src/other.lua", 9, "note", "other repo", nil, "new", other_root)

    comments.quickfix()

    local qf = vim.fn.getqflist({ items = 1 }).items
    assert.equals(1, #qf)
    assert.truthy(qf[1].text:match("this repo"))
  end)

  it("builds the jump target from the comment's git_root", function()
    store.add("lua/review/init.lua", 3, "question", "why", nil, "new", repo_root)

    comments.quickfix()

    local qf = vim.fn.getqflist({ items = 1 }).items
    assert.equals(1, #qf)
    assert.equals(repo_root .. "/lua/review/init.lua", vim.fn.bufname(qf[1].bufnr))
  end)

  it("includes unattributed comments in the current repo view", function()
    store.add("lua/review/init.lua", 3, "question", "attributed", nil, "new", repo_root)
    store.add("legacy.lua", 1, "note", "legacy") -- no git_root

    comments.quickfix()

    local qf = vim.fn.getqflist({ items = 1 }).items
    assert.equals(2, #qf)
  end)
end)
