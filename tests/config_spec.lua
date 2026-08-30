local config = require("review.config")

describe("review.config", function()
  after_each(function()
    config.setup({})
  end)

  describe("defaults", function()
    it("ships no comment types (fully user-defined)", function()
      config.setup({})
      local cfg = config.get()
      assert.same({}, cfg.comment_types)
      assert.same({}, cfg.popup.type_order)
      assert.is_nil(cfg.popup.default_type)
    end)

    it("defaults quickfix.path_style to relative", function()
      config.setup({})
      assert.equal("relative", config.get().quickfix.path_style)
    end)
  end)

  describe("comment_types override", function()
    it("replaces defaults wholesale (nothing leaks in)", function()
      config.setup({
        comment_types = {
          bug = { key = "b", name = "Bug", icon = "!", hl = "ReviewIssue", line_hl = "ReviewIssueLine" },
        },
        popup = { type_order = { "bug" }, default_type = "bug" },
      })
      local cfg = config.get()
      local keys = vim.tbl_keys(cfg.comment_types)
      assert.same({ "bug" }, keys)
      assert.same({ "bug" }, cfg.popup.type_order)
    end)
  end)
end)
