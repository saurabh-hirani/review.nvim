local M = {}

function M.setup()
  -- Only infrastructure highlight groups are defined here. Per-type colours
  -- (the sign/box `hl` and the whole-line `line_hl`) are the user's responsibility:
  -- define your own highlight groups and reference them by name in
  -- comment_types[type].hl / .line_hl. Nothing type-specific is imposed by default.
  local links = {
    ReviewSign = "Comment",
    ReviewVirtText = "Comment",
    ReviewPickerHash = "Identifier",
    ReviewPickerMeta = "Comment",
    ReviewPickerSelected = "String",
  }

  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end

  vim.fn.sign_define("ReviewComment", {
    text = "●",
    texthl = "ReviewSign",
  })
end

return M
