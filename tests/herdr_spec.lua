local export = require("review.export")
local config = require("review.config")

describe("review herdr", function()
  describe("_herdr_target_of", function()
    it("maps the current-pane label to $HERDR_PANE_ID", function()
      vim.env.HERDR_PANE_ID = "w1:p9"
      assert.equal("w1:p9", export._herdr_target_of("current"))
      assert.equal("w1:p9", export._herdr_target_of("current pane ($HERDR_PANE_ID)"))
      vim.env.HERDR_PANE_ID = nil
    end)

    it("takes the leading pane id token from a picker line", function()
      assert.equal("w1:p1", export._herdr_target_of("w1:p1  nvim"))
      assert.equal("w2:p3", export._herdr_target_of("w2:p3"))
    end)
  end)

  describe("_herdr_pane_items", function()
    it("builds 'id  desc' lines, preferring agent then label then cwd basename", function()
      local json = vim.json.encode({
        result = {
          panes = {
            { pane_id = "w1:p1", label = "editor", agent = "codex" },
            { pane_id = "w1:p2", label = "editor" },
            { pane_id = "w1:p3", cwd = "/Users/me/github/review.nvim" },
            { pane_id = "w1:p4" },
          },
        },
      })
      local items = export._herdr_pane_items(json)
      assert.same({ "w1:p1  codex", "w1:p2  editor", "w1:p3  review.nvim", "w1:p4" }, items)
    end)

    it("excludes the caller pane", function()
      local json = vim.json.encode({
        result = { panes = { { pane_id = "w1:p1", agent = "a" }, { pane_id = "w1:p2", agent = "b" } } },
      })
      assert.same({ "w1:p2  b" }, export._herdr_pane_items(json, "w1:p1"))
    end)

    it("returns empty on malformed or unexpected JSON", function()
      assert.same({}, export._herdr_pane_items("not json"))
      assert.same({}, export._herdr_pane_items(vim.json.encode({ result = {} })))
    end)
  end)

  describe("_herdr_neighbor_of", function()
    it("pulls neighbor_pane_id out of neighbor JSON", function()
      local json = vim.json.encode({
        result = { neighbor = { pane_id = "w1:p1", direction = "right", neighbor_pane_id = "w1:p2" } },
      })
      assert.equal("w1:p2", export._herdr_neighbor_of(json))
    end)

    it("returns nil when there is no neighbor or JSON is bad", function()
      assert.is_nil(export._herdr_neighbor_of(vim.json.encode({ result = { neighbor = {} } })))
      assert.is_nil(export._herdr_neighbor_of("not json"))
    end)
  end)

  describe("config defaults", function()
    it("ships a herdr block and an H keymap", function()
      config.setup({})
      local cfg = config.get()
      assert.equal("H", cfg.keymaps.send_herdr)
      assert.is_false(cfg.herdr.send_enter)
      assert.same({ "right" }, cfg.herdr.panes)
      assert.same({}, cfg.herdr.auto_select_panes)
    end)
  end)
end)
