local M = {}

---@class ReviewConfig
---@field comment_types table<string, CommentType>
---@field keymaps ReviewKeymaps
---@field codediff ReviewCodediffConfig
---@field export ReviewExportConfig
---@field popup ReviewPopupConfig
---@field storage ReviewStorageConfig
---@field tmux ReviewTmuxConfig
---@field herdr ReviewHerdrConfig
---@field quickfix ReviewQuickfixConfig

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
---@field send_tmux string|false
---@field send_herdr string|false
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

---@class ReviewStorageConfig
---@field expiry_days number|false days a saved review survives without a change; 0 or false keeps it forever (default)

---@class ReviewTmuxConfig
---@field send_enter boolean press Enter after sending (submit immediately); default false
---@field panes string[] pane targets always offered in the picker (besides live panes); "+" means next pane
---@field auto_select_panes string[] if non-empty, send to these panes directly without prompting

---@class ReviewHerdrConfig
---@field send_enter boolean press Enter after sending (submit immediately); default false
---@field panes string[] convenience targets offered in the picker; a direction ("right"/"left"/"up"/"down") = that neighbor of the calling pane, "current" = calling pane ($HERDR_PANE_ID), or an explicit pane id
---@field auto_select_panes string[] if non-empty, send to these targets directly without prompting (same vocabulary as panes)
---@field focus boolean focus the target pane after sending; directional targets only (default true)

---@class ReviewQuickfixConfig
---@field path_style "relative"|"absolute" path shown in the :Review quickfix list (default "relative")

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
    send_tmux = "T",
    send_herdr = "H",
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
  storage = {
    -- 0 (or false) keeps saved reviews forever. Set a positive number of days
    -- to have a review deleted once its file has gone that long without a
    -- change; adding or editing a comment resets the clock.
    expiry_days = 0,
  },
  tmux = {
    -- false: leave the text in the pane without submitting. true: press Enter
    -- after sending, submitting it immediately (handy for agent CLIs).
    send_enter = false,
    -- Pane targets always offered in the picker on top of the live panes.
    -- "+" is the next pane; you can also list explicit targets like "1.2".
    panes = { "+" },
    -- If non-empty, send to these panes directly and skip the picker.
    auto_select_panes = {},
  },
  herdr = {
    -- false: leave the text in the pane without submitting. true: press Enter
    -- after sending, submitting it immediately (handy for agent CLIs).
    send_enter = false,
    -- Convenience targets offered on top of the live panes. A direction
    -- ("right"/"left"/"up"/"down") resolves to that neighbor of the calling
    -- pane -- "right" suits an editor-left / agent-right layout. "current" is
    -- the calling pane ($HERDR_PANE_ID); you can also list explicit opaque
    -- pane ids like "w1:p1".
    panes = { "right" },
    -- If non-empty, send to these targets directly and skip the picker
    -- (same vocabulary as panes: a direction, "current", or a pane id).
    auto_select_panes = {},
    -- true: focus the target pane after sending. Focus-follow only applies to
    -- directional targets (herdr's pane focus is direction-based).
    focus = true,
  },
  quickfix = {
    -- Path shown in the :Review quickfix list. "relative" (default) shows the
    -- stored path relative to the git root; "absolute" shows the full path.
    -- Jumping works either way; this only affects what the quickfix line shows.
    path_style = "relative",
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
