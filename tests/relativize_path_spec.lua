local hooks = require("review.hooks")

-- Core cross-repo fix: reviewing a file whose git root differs from nvim's cwd
-- (e.g. a diff of a sibling repo's file). codediff hands a Path object
-- {relative, absolute} whose `.absolute` is resolved against the file's own git
-- root. relativize_path must strip against that root using the Path's absolute
-- field, not re-derive with fnamemodify(:p), which would anchor a relative path
-- to cwd and yield a path under the wrong repo.

describe("hooks relativize_path", function()
  local function fake_lifecycle(git_root)
    return {
      get_git_context = function()
        return { git_root = git_root }
      end,
    }
  end

  it("returns rel path and the file's own git root from a Path object", function()
    local root = "/repos/boilerplate"
    local path = {
      relative = "helm/charts/otel-config/Chart.yaml",
      absolute = root .. "/helm/charts/otel-config/Chart.yaml",
    }

    local rel, git_root = hooks._relativize_path(path, fake_lifecycle(root), 1)

    assert.equals("helm/charts/otel-config/Chart.yaml", rel)
    assert.equals(root, git_root)
  end)

  it("uses the Path absolute even when it lies outside cwd", function()
    local root = "/repos/boilerplate"
    local path = {
      relative = "templates/instrumentation.yaml",
      absolute = root .. "/templates/instrumentation.yaml",
    }

    local rel, git_root = hooks._relativize_path(path, fake_lifecycle(root), 1)

    assert.equals("templates/instrumentation.yaml", rel)
    assert.equals(root, git_root)
    assert.is_nil(rel:match("^/"))
  end)

  it("falls back to a cwd-relative path with no git context", function()
    local rel, git_root = hooks._relativize_path(
      "some/file.lua",
      { get_git_context = function() return nil end },
      1
    )
    assert.equals("some/file.lua", rel)
    assert.is_nil(git_root)
  end)
end)
