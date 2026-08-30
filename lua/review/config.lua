local M = {}

---@class ReviewConfig
---@field comment_types table<string, CommentType>
---@field keymaps ReviewKeymaps
---@field codediff ReviewCodediffConfig
---@field export ReviewExportConfig
---@field popup ReviewPopupConfig

---@class CommentType
---@field key string
---@field name string
---@field icon string
---@field hl string
---@field line_hl string

---@class ReviewKeymaps
---@field add_comment string|false
---@field add_type_prefix string|false
---@field delete_comment string|false
---@field edit_comment string|false
---@field next_comment string|false
---@field prev_comment string|false
---@field list_comments string|false
---@field export_clipboard string|false
---@field send_sidekick string|false
---@field clear_comments string|false
---@field close string|false
---@field toggle_readonly string|false
---@field next_file string|false
---@field prev_file string|false
---@field toggle_file_panel string|false
---@field readonly_add string|false
---@field readonly_delete string|false
---@field readonly_edit string|false
---@field readonly_add_file string|false
---@field add_file_comment string|false
---@field popup_submit string|false
---@field popup_cancel string|false
---@field show_help string|false
---@field popup_cycle_type string|false

---@class ReviewCodediffConfig
---@field readonly boolean
---@field restore_edit_on_close boolean

---@class ReviewExportConfig
---@field path_style "relative"|"absolute"
---@field header string|false intro line(s) before the comment list; false to omit
---@field side_note string|false explanation of the ~ (old-side) prefix; false to omit
---@field types? string[] type keys to export; nil exports every type

---@class ReviewPopupConfig
---@field type_order string[]
---@field default_type? string

---@type ReviewConfig
M.defaults = {
  -- No comment types are shipped by default: the user defines them entirely.
  -- See the README for ready-to-copy examples (note/suggestion/issue/praise, etc).
  comment_types = {},
  keymaps = {
    -- Edit mode (leader-based)
    add_comment = "<localleader>cc",
    -- Per-type add keymaps are derived as add_type_prefix .. comment_type.key
    -- (e.g. prefix "<localleader>c" + note key "n" = "<localleader>cn").
    add_type_prefix = "<localleader>c",
    add_file_comment = "<localleader>cf",
    delete_comment = "<localleader>cd",
    edit_comment = "<localleader>ce",
    -- Navigation
    next_comment = "]n",
    prev_comment = "[n",
    next_file = "<Tab>",
    prev_file = "<S-Tab>",
    toggle_file_panel = "f",
    -- Common actions
    list_comments = "c",
    export_clipboard = "C",
    send_sidekick = "S",
    clear_comments = "<C-r>",
    close = "q",
    toggle_readonly = "R",
    -- Readonly mode (simple keys)
    readonly_add = "i",
    readonly_delete = "d",
    readonly_delete_multi = "D",
    readonly_edit = "e",
    readonly_add_file = "F",
    -- Help
    show_help = "?",
    -- Popup keymaps
    popup_submit = "<C-s>",
    popup_cancel = "q",
    popup_cycle_type = "<Tab>",
  },
  codediff = {
    readonly = true,
    restore_edit_on_close = false,
  },
  export = {
    path_style = "relative",
    header = "I reviewed your code and have the following comments. Please address them.",
    side_note = "Lines prefixed with ~ refer to the old (left) side of the diff.",
    -- nil = export every type. Set to a list of type keys to export only those
    -- (e.g. { "suggestion", "question" } to keep notes out of the export).
    types = nil,
  },
  popup = {
    type_order = {},
    default_type = nil,
  },
}

---@type ReviewConfig
M.config = vim.deepcopy(M.defaults)

---@param opts? ReviewConfig
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.defaults, opts)
  -- comment_types is a set of user-defined types, not a partial override: if the
  -- user supplies it, replace the defaults wholesale so built-in types don't leak
  -- in via deep-merge. (type_order is an array, so it already replaces cleanly.)
  if opts.comment_types then
    M.config.comment_types = opts.comment_types
  end
end

---@return ReviewConfig
function M.get()
  return M.config
end

return M
