local store = require("review.store")
local export = require("review.export")
local config = require("review.config")

describe("review.export", function()
  before_each(function()
    store.clear()
  end)

  describe("generate_markdown", function()
    it("returns empty message when no comments", function()
      local md = export.generate_markdown()
      assert.matches("No comments yet", md)
    end)

    it("includes file and comment in output", function()
      store.add("src/main.lua", 10, "issue", "Fix this bug")

      local md = export.generate_markdown()
      assert.matches("src/main.lua:10", md)
      assert.matches("%[ISSUE%]", md)
      assert.matches("Fix this bug", md)
    end)

    it("formats comments as numbered list", function()
      store.add("a.lua", 1, "note", "Note A")
      store.add("b.lua", 1, "issue", "Issue B")
      store.add("a.lua", 5, "suggestion", "Suggestion A")

      local md = export.generate_markdown()
      assert.matches("1%. %*%*%[NOTE%]%*%*", md)
      assert.matches("2%. %*%*%[SUGGESTION%]%*%*", md)
      assert.matches("3%. %*%*%[ISSUE%]%*%*", md)
    end)

    it("uses tilde notation for old-side comments", function()
      store.add("src/main.lua", 10, "issue", "Removed bug", nil, "old")

      local md = export.generate_markdown()
      assert.matches("src/main.lua:~10", md)
    end)

    it("uses tilde on both ends for old-side range", function()
      store.add("src/main.lua", 10, "issue", "Old range", 15, "old")

      local md = export.generate_markdown()
      assert.matches("src/main.lua:~10%-~15", md)
    end)

    it("uses normal notation for new-side comments", function()
      store.add("src/main.lua", 10, "issue", "New side", nil, "new")

      local md = export.generate_markdown()
      assert.matches("src/main.lua:10", md)
      assert.not_matches("~10", md)
    end)
  end)

  describe("configurable preamble", function()
    after_each(function()
      config.setup({})
    end)

    it("uses default header and side_note", function()
      store.add("a.lua", 1, "note", "x")
      local md = export.generate_markdown()
      assert.matches("I reviewed your code", md)
      assert.matches("Lines prefixed with ~", md)
    end)

    it("uses a custom header", function()
      config.setup({ export = { header = "Custom intro." } })
      store.add("a.lua", 1, "note", "x")
      local md = export.generate_markdown()
      assert.matches("Custom intro%.", md)
      assert.not_matches("I reviewed your code", md)
    end)

    it("omits header when set to false", function()
      config.setup({ export = { header = false } })
      store.add("a.lua", 1, "note", "x")
      local md = export.generate_markdown()
      assert.not_matches("I reviewed your code", md)
    end)

    it("omits side_note when set to false", function()
      config.setup({ export = { side_note = false } })
      store.add("a.lua", 1, "note", "x")
      local md = export.generate_markdown()
      assert.not_matches("Lines prefixed with ~", md)
    end)

    it("derives Comment types line from popup.type_order names", function()
      config.setup({
        comment_types = { question = { key = "q", name = "Question", icon = "?", hl = "ReviewNote", line_hl = "ReviewNoteLine" } },
        popup = { type_order = { "suggestion", "question" }, default_type = "suggestion" },
      })
      store.add("a.lua", 1, "suggestion", "x")
      local md = export.generate_markdown()
      assert.matches("Comment types: SUGGESTION, QUESTION", md)
    end)
  end)

  describe("export.types filter", function()
    after_each(function()
      config.setup({})
    end)

    local function setup_types(export_types)
      config.setup({
        comment_types = {
          suggestion = { key = "s", name = "Suggestion", icon = "!", hl = "H", line_hl = "HL" },
          note = { key = "n", name = "Note", icon = "*", hl = "H", line_hl = "HL" },
        },
        popup = { type_order = { "suggestion", "note" }, default_type = "suggestion" },
        export = { types = export_types },
      })
    end

    it("exports every type when types is unset", function()
      setup_types(nil)
      store.add("a.lua", 1, "suggestion", "keep me")
      store.add("a.lua", 2, "note", "me too")

      assert.equals(2, #export.exported_comments())
      local md = export.generate_markdown()
      assert.matches("keep me", md)
      assert.matches("me too", md)
      assert.matches("Comment types: SUGGESTION, NOTE", md)
    end)

    it("omits comments whose type is not listed", function()
      setup_types({ "suggestion" })
      store.add("a.lua", 1, "suggestion", "keep me")
      store.add("a.lua", 2, "note", "drop me")

      assert.equals(1, #export.exported_comments())
      local md = export.generate_markdown()
      assert.matches("keep me", md)
      assert.not_matches("drop me", md)
      -- excluded types are dropped from the preamble too
      assert.matches("Comment types: SUGGESTION", md)
      assert.not_matches("NOTE", md)
      -- numbering stays contiguous over the filtered set
      assert.matches("1%. %*%*%[SUGGESTION%]%*%*", md)
      assert.not_matches("2%.", md)
    end)

    it("treats an empty list as nothing to export", function()
      setup_types({})
      store.add("a.lua", 1, "suggestion", "keep me")

      assert.equals(0, #export.exported_comments())
      assert.matches("No comments yet", export.generate_markdown())
    end)
  end)
end)
