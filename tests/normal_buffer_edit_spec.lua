-- Edit/delete of an existing annotation must work in a plain buffer (no
-- codediff session). Regression: edit_at_cursor/delete_at_cursor used the
-- session-only cursor hook and silently failed outside a diff.
local store = require("review.store")
local comments = require("review.comments")
local popup = require("review.popup")
local config = require("review.config")

describe("edit/delete in a normal buffer (no codediff session)", function()
  local bufnr
  local orig_open
  local git_root

  before_each(function()
    store.reset()
    config.setup()

    -- A real file inside this repo so root_for resolves a git root and the
    -- buffer's relative path matches the stored comment's file key.
    git_root = vim.fn.getcwd()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
    vim.api.nvim_buf_set_name(bufnr, git_root .. "/lua/review/store.lua")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "line 1", "line 2", "line 3", "line 4", "line 5", "line 6",
    })
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 5, 0 })

    orig_open = popup.open
  end)

  after_each(function()
    popup.open = orig_open
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    store.reset()
  end)

  it("edit_at_cursor updates an existing comment and refreshes the mark", function()
    local marks = require("review.marks")
    local c = store.add("lua/review/store.lua", 5, "note", "before", nil, "new", git_root)
    -- Render the initial mark so we can prove the edit refreshes it.
    marks.render_for_buffer(bufnr, "new", "lua/review/store.lua")

    -- Stub the popup to immediately confirm an edit.
    popup.open = function(_type, _text, cb)
      cb("suggestion", "after")
    end

    comments.edit_at_cursor()

    local updated = store.get(c.id)
    assert.equals("after", updated.text)
    assert.equals("suggestion", updated.type)

    -- The on-screen mark must show the new text without a manual toggle. Flush
    -- the scheduled refresh, then inspect the extmark virt_lines.
    vim.wait(50, function() return false end)
    local ns_id = vim.api.nvim_create_namespace("review")
    local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })
    assert.equals(1, #extmarks)
    local rendered = vim.inspect(extmarks[1][4].virt_lines or {})
    assert.truthy(rendered:find("after", 1, true))
    assert.is_nil(rendered:find("before", 1, true))
  end)

  it("delete_at_cursor removes an existing comment and clears the mark", function()
    local marks = require("review.marks")
    local c = store.add("lua/review/store.lua", 5, "note", "gone soon", nil, "new", git_root)
    marks.render_for_buffer(bufnr, "new", "lua/review/store.lua")

    -- Stub the confirmation prompt to choose "Yes".
    local orig_select = vim.ui.select
    vim.ui.select = function(_items, _opts, cb)
      cb("Yes")
    end

    comments.delete_at_cursor()

    vim.ui.select = orig_select
    assert.is_nil(store.get(c.id))

    vim.wait(50, function() return false end)
    local ns_id = vim.api.nvim_create_namespace("review")
    local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
    assert.equals(0, #extmarks)
  end)

  it("does nothing (warns) when there is no comment at the cursor", function()
    -- No comment added; edit should not error and should leave the store empty.
    local called = false
    popup.open = function()
      called = true
    end
    comments.edit_at_cursor()
    assert.is_false(called)
    assert.equals(0, store.count())
  end)

  it("delete_multi (:Review delete) removes the comment and clears the mark", function()
    local marks = require("review.marks")
    local c = store.add("lua/review/store.lua", 5, "note", "bulk delete", nil, "new", git_root)
    marks.render_for_buffer(bufnr, "new", "lua/review/store.lua")

    -- No fzf-lua in headless tests, so delete_multi uses the vim.ui.select
    -- fallback: first the entry list, then (some paths) a Yes/No. Pick the
    -- single entry, and answer "Yes" if a confirmation is asked.
    local orig_select = vim.ui.select
    vim.ui.select = function(items, _opts, cb)
      if items and items[1] == "Yes" then
        cb("Yes")
      else
        cb(items[1])
      end
    end

    comments.delete_multi()

    vim.ui.select = orig_select
    assert.is_nil(store.get(c.id))

    vim.wait(50, function() return false end)
    local ns_id = vim.api.nvim_create_namespace("review")
    local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
    assert.equals(0, #extmarks)
  end)
end)
