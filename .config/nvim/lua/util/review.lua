-- Manual review of agent-generated commits.
--
--   :Review start          pick a base commit -> diffview against the working tree
--   :Review continue       resume this branch's saved base + ✓ marks
--   :Review note <kind>    drop a `REVIEW: <kind>:` marker at the cursor
--   :Review viewed         toggle ✓ on the file under the cursor / being diffed
--   :Review doc            open the free-form review doc for this checkpoint
--   :Review list           every REVIEW: marker in the project, in Trouble
--
-- Mapped under `<leader>r`: r start, c continue, v viewed, i/s/q/n note
-- issue/suggestion/question/nit, d doc, l list.
--
-- Notes are handed back to the agent in one go via the global /address-review
-- command, which reads both the inline markers and the doc.

local M = {}

M.kinds = { "issue", "suggestion", "question", "nit" }

-- The base of the last `:Review start`, used to name the review doc.
M.base = nil

---@return string
function M.root()
  return vim.fs.root(0, ".git") or vim.uv.cwd() or "."
end

---@param args string[]
---@return string[]
local function git(args)
  local cmd = { "git", "-C", M.root() }
  vim.list_extend(cmd, args)
  local out = vim.system(cmd, { text = true }):wait()
  if out.code ~= 0 then
    return {}
  end
  return vim.split(vim.trim(out.stdout or ""), "\n", { trimempty = true })
end

---@param args string[]
---@return string?
local function git1(args)
  return git(args)[1]
end

--- The trunk branch, as `origin/HEAD` says, else the first of the usual suspects.
---@return string?
function M.trunk()
  local head = git1({ "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
  if head then
    return head
  end
  for _, name in ipairs({ "main", "master", "development", "develop" }) do
    if git1({ "rev-parse", "--verify", "--quiet", name }) then
      return name
    end
  end
end

--- The branch directly below this one in a stack: the nearest local branch tip
--- that is an ancestor of HEAD (and isn't HEAD itself). Falls back to the
--- branch point against trunk.
---@return { commit: string, label: string }?
function M.pinned_base()
  local head = git1({ "rev-parse", "HEAD" })
  local current = git1({ "rev-parse", "--abbrev-ref", "HEAD" })
  local best ---@type { commit: string, label: string, distance: number }?

  for _, line in ipairs(git({ "for-each-ref", "--format=%(objectname) %(refname:short)", "refs/heads" })) do
    local sha, name = line:match("^(%S+) (.+)$")
    if sha and name ~= current and sha ~= head then
      local ok = vim.system({ "git", "-C", M.root(), "merge-base", "--is-ancestor", sha, "HEAD" }):wait()
      if ok.code == 0 then
        local distance = tonumber(git1({ "rev-list", "--count", sha .. "..HEAD" }) or "") or math.huge
        if not best or distance < best.distance then
          best = {
            commit = sha,
            label = ("base branch: %s — %d commit%s since"):format(name, distance, distance == 1 and "" or "s"),
            distance = distance,
          }
        end
      end
    end
  end
  if best then
    return { commit = best.commit, label = best.label }
  end

  local ref = M.trunk()
  local mb = ref and git1({ "merge-base", ref, "HEAD" })
  if not mb then
    return nil
  end
  local distance = tonumber(git1({ "rev-list", "--count", mb .. "..HEAD" }) or "") or 0
  return {
    commit = mb,
    label = ("branch point vs %s — %d commit%s since"):format(ref, distance, distance == 1 and "" or "s"),
  }
end

--- Ancestors of HEAD, with ref decorations kept inline after the subject.
--- The pinned base (stack parent, else branch point) comes first.
---@return table[]
function M.commits()
  local cwd = M.root()
  local items = {} ---@type table[]

  local pin = M.pinned_base()
  if pin then
    items[#items + 1] = {
      text = "◆ " .. pin.label,
      commit = pin.commit:sub(1, 8),
      msg = "◆ " .. pin.label,
      cwd = cwd,
    }
  end

  local log = git({
    "log",
    "--pretty=format:%h\t%s\t%d\t%ch\t%an",
    "--abbrev-commit",
    "--no-show-signature",
    "-n",
    "300",
    "HEAD",
  })
  for _, line in ipairs(log) do
    local commit, subject, decoration, date, author = line:match("^(.-)\t(.-)\t(.-)\t(.-)\t(.*)$")
    if commit then
      local msg = subject
      decoration = vim.trim(decoration)
      if decoration ~= "" then
        msg = msg .. " " .. decoration
      end
      items[#items + 1] = {
        text = table.concat({ commit, msg, author }, " "),
        commit = commit,
        msg = msg,
        date = date,
        author = author,
        cwd = cwd,
      }
    end
  end
  return items
end

--- Resolve a picked commit to the base to diff from. A no-op for our own
--- commits; the branch point for a trunk ref that has moved on since.
---@param commit string
---@return string
function M.resolve_base(commit)
  return git1({ "merge-base", commit, "HEAD" }) or commit
end

-- Files marked viewed in this session, keyed by repo-relative path. Persisted
-- per branch (see `M.save_state`) so `:Review continue` can restore them.
M.viewed = {}

--- Where the per-branch review state lives. Inside `.scratchpad/`, which is
--- globally gitignored, so it never reaches a commit.
---@return string
function M.state_path()
  return M.root() .. "/.scratchpad/manual-review/state.json"
end

---@return string
local function branch()
  return git1({ "rev-parse", "--abbrev-ref", "HEAD" }) or "detached"
end

--- The content hash of a file as it stands on disk — the same blob hash git
--- would give it. `"deleted"` when the file isn't there (a deletion in the diff
--- is still a reviewable change).
---@param path string
---@return string
local function content_hash(path)
  local abs = M.root() .. "/" .. path
  if vim.fn.filereadable(abs) == 0 then
    return "deleted"
  end
  return git1({ "hash-object", "--", abs }) or "unknown"
end

---@return table  -- the whole state file, `{ branches = { … } }`
local function read_state()
  local path = M.state_path()
  if vim.fn.filereadable(path) == 0 then
    return { branches = {} }
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok or type(decoded) ~= "table" then
    return { branches = {} }
  end
  decoded.branches = decoded.branches or {}
  return decoded
end

--- Persist this branch's base and viewed set. Each ✓ records the file's content
--- hash, so a file the agent changes afterwards can be un-ticked on restore.
function M.save_state()
  if not M.base then
    return
  end
  local state = read_state()
  local viewed = {} ---@type table<string, string>
  for path in pairs(M.viewed) do
    viewed[path] = content_hash(path)
  end
  state.branches[branch()] = { base = M.base, viewed = viewed }

  local dir = M.root() .. "/.scratchpad/manual-review"
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ vim.json.encode(state) }, M.state_path())
end

--- Restore this branch's saved review: the base, plus the ✓ marks whose files
--- haven't changed since. Returns the base, and how many marks were kept/dropped.
---@return string? base, integer kept, integer stale
function M.load_state()
  local entry = read_state().branches[branch()]
  if not entry or not entry.base then
    return nil, 0, 0
  end
  local kept, stale = 0, 0
  M.viewed = {}
  for path, hash in pairs(entry.viewed or {}) do
    if content_hash(path) == hash then
      M.viewed[path] = true
      kept = kept + 1
    else
      stale = stale + 1
    end
  end
  return entry.base, kept, stale
end

local ns = vim.api.nvim_create_namespace("review_viewed")

---@return table? view  -- the current DiffView, if any
local function current_view()
  local ok, lib = pcall(require, "diffview.lib")
  return ok and lib.get_current_view() or nil
end

-- Every panel redraw replaces the whole buffer (`nvim_buf_set_lines(0, -1)`),
-- which wipes extmarks in all namespaces — so opening a file erases the ✓ marks.
-- Diffview's user hooks can't cover this: the events that fire around a file
-- open (`file_open_post`, `files_updated`) are emitted on the *per-view*
-- emitter, and only `DiffviewGlobal.emitter` events reach user hooks. So repaint
-- from the one place where the lines actually change.
local patched = false

local function patch_redraw()
  if patched then
    return
  end
  local ok, panel = pcall(require, "diffview.ui.panel")
  if not ok or not panel.Panel then
    return
  end
  local redraw = panel.Panel.redraw
  panel.Panel.redraw = function(self, ...)
    local result = redraw(self, ...)
    vim.schedule(function()
      M.refresh_marks()
    end)
    return result
  end
  patched = true
end

--- Dim the "deleted" filler in a diff's left pane instead of painting it
--- `DiffDelete` red — a new file is otherwise a solid red rectangle.
---
--- Diffview's own `enhanced_diff_hl` option is meant to do this, but its
--- `hi()` helper merges the *resolved* attributes of the existing group before
--- applying the link, so the red background survives. Setting the link
--- explicitly is deterministic.
function M.dim_deleted_filler()
  vim.api.nvim_set_hl(0, "DiffviewDiffDeleteDim", { link = "NonText" })
  vim.api.nvim_set_hl(0, "DiffviewDiffDelete", { link = "DiffviewDiffDeleteDim" })
end

--- Install the ✓ repaint wrapper. Idempotent; called from `:Review start`, from
--- `:Review viewed`, and from diffview's `view_opened` hook.
function M.install()
  patch_redraw()
  M.dim_deleted_filler()
  M.refresh_marks()
end

--- Repaint the ✓ marks in the file panel.
function M.refresh_marks()
  local view = current_view()
  local panel = view and view.panel
  if not panel or not panel.bufid or not vim.api.nvim_buf_is_valid(panel.bufid) then
    return
  end
  vim.api.nvim_buf_clear_namespace(panel.bufid, ns, 0, -1)
  if not panel.components or not panel.components.comp then
    return
  end

  local lines = vim.api.nvim_buf_line_count(panel.bufid)
  panel.components.comp:deep_some(function(comp)
    local file = comp.name == "file" and comp.context or nil
    if file and file.path and M.viewed[file.path] and comp.lstart >= 0 and comp.lstart < lines then
      vim.api.nvim_buf_set_extmark(panel.bufid, ns, comp.lstart, 0, {
        virt_text = { { " ✓", "DiffviewFilePanelInsertions" } },
        virt_text_pos = "eol",
        line_hl_group = "Comment",
      })
    end
    return false
  end)
end

--- All files in the current diff, by repo-relative path.
---@return string[]
local function view_files()
  local view = current_view()
  local paths = {} ---@type string[]
  for _, kind in ipairs({ "working", "conflicting", "staged" }) do
    for _, f in ipairs(view and view.panel and view.panel.files and view.panel.files[kind] or {}) do
      paths[#paths + 1] = f.path
    end
  end
  return paths
end

--- Toggle "viewed" on the file under the cursor in the panel, or the file being
--- diffed. GitHub's checkbox: explicit, so it means you actually reviewed it.
function M.toggle_viewed()
  local view = current_view()
  if not view then
    vim.notify("no diffview open", vim.log.levels.WARN)
    return
  end
  patch_redraw()

  local file ---@type table?
  if view.panel and view.panel:is_focused() then
    local item = view.panel:get_item_at_cursor()
    -- A FileEntry carries a `layout`; a DirData row doesn't. (Both have `_node`
    -- and `path` in tree listing mode, so those can't tell them apart.)
    if item and not item.layout then
      vim.notify("that's a directory — mark files individually", vim.log.levels.WARN)
      return
    end
    file = item
  else
    file = view.cur_entry
  end

  if not file or not file.path then
    vim.notify("no file under the cursor", vim.log.levels.WARN)
    return
  end

  M.viewed[file.path] = not M.viewed[file.path] or nil
  M.refresh_marks()
  M.save_state()

  local total = #view_files()
  local seen = vim.tbl_count(M.viewed)
  vim.notify(
    ("%s %s  (%d/%d viewed)"):format(M.viewed[file.path] and "✓" or "○", file.path, seen, total),
    vim.log.levels.INFO
  )
end

--- Pick a base commit and diff it against the working tree.
function M.start()
  Snacks.picker.pick({
    source = "review_base",
    title = "Review base",
    finder = function()
      return M.commits()
    end,
    format = "git_log",
    preview = "git_show",
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      local base = M.resolve_base(item.commit)
      M.base = base:sub(1, 8)
      M.viewed = {} -- a new checkpoint starts with nothing reviewed
      M.save_state()
      patch_redraw()
      vim.cmd("DiffviewOpen " .. base)
    end,
  })
end

--- Resume the saved review for this branch: same base, ✓ marks restored except
--- on files that have changed since they were ticked.
function M.continue()
  local base, kept, stale = M.load_state()
  if not base then
    vim.notify("no saved review for this branch — starting a new one", vim.log.levels.INFO)
    M.start()
    return
  end
  M.base = base
  patch_redraw()
  vim.cmd("DiffviewOpen " .. base)
  vim.notify(
    ("resumed review from %s — %d viewed%s"):format(
      base,
      kept,
      stale > 0 and (", %d changed since (unmarked)"):format(stale) or ""
    ),
    vim.log.levels.INFO
  )
end

--- The marker line to insert: `REVIEW: <kind>:` as a comment for `commentstring`.
---@param kind string
---@param commentstring string
---@param indent string
---@return string line, integer col  -- byte offset where the note text starts
function M.marker(kind, commentstring, indent)
  local cs = commentstring
  if cs == "" or not cs:find("%%s") then
    cs = "# %s"
  end
  local left, right = cs:match("^(.-)%%s(.-)$")
  left, right = vim.trim(left or "#"), vim.trim(right or "")
  local prefix = ("%s%s REVIEW: %s: "):format(indent, left, kind)
  return prefix .. (right ~= "" and " " .. right or ""), #prefix
end

--- Insert a marker at the cursor, commented for the filetype.
---@param kind string
function M.note(kind)
  if not vim.tbl_contains(M.kinds, kind) then
    vim.notify(("unknown review kind %q (expected %s)"):format(kind, table.concat(M.kinds, "/")), vim.log.levels.ERROR)
    return
  end
  if not vim.bo.modifiable then
    vim.notify("buffer is not modifiable — open the working-tree file first", vim.log.levels.WARN)
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local current = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  local line, col = M.marker(kind, vim.bo.commentstring, current:match("^%s*") or "")

  vim.api.nvim_buf_set_lines(0, row, row, false, { line })
  vim.api.nvim_win_set_cursor(0, { row + 1, math.min(col, math.max(#line - 1, 0)) })
  if col >= #line then
    vim.cmd("startinsert!")
  else
    vim.cmd("startinsert")
  end
end

--- Default filename for this checkpoint's review doc.
---@return string
function M.doc_name()
  local branch = (git1({ "rev-parse", "--abbrev-ref", "HEAD" }) or "detached"):gsub("[^%w%-_]", "-")
  local base = M.base or git1({ "rev-parse", "--short", "HEAD" }) or "HEAD"
  return ("%s-%s-%s.md"):format(os.date("%Y-%m-%d"), branch, base)
end

--- Open (creating if needed) the review doc for this checkpoint.
function M.doc()
  vim.ui.input({ prompt = "Review doc: ", default = M.doc_name() }, function(name)
    if not name or name == "" then
      return
    end
    local dir = M.root() .. "/.scratchpad/manual-review"
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/" .. name

    local fresh = vim.fn.filereadable(path) == 0
    vim.cmd("botright split " .. vim.fn.fnameescape(path))
    if fresh then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        "---",
        "date: " .. os.date("%Y-%m-%d"),
        "branch: " .. (git1({ "rev-parse", "--abbrev-ref", "HEAD" }) or "detached"),
        "base: " .. (M.base or "?"),
        "head: " .. (git1({ "rev-parse", "--short", "HEAD" }) or "?"),
        "---",
        "",
        "# Review notes",
        "",
        "<!-- Notes that don't belong to a single line. Name the kind, same as",
        "     inline markers: issue (must fix) / suggestion (assess impact) /",
        "     question (answer in chat) / nit. No kind means issue. -->",
        "",
        "- ",
      })
      vim.api.nvim_win_set_cursor(0, { 14, 2 })
      vim.cmd("startinsert!")
    end
  end)
end

--- Every REVIEW: marker in the project, in a Trouble panel.
---
--- Not `:TodoTrouble keywords=REVIEW` — trouble's `todo` source hardcodes an
--- empty filter, so it would list TODO/FIXME/… alongside. Driving the search
--- directly filters properly, and only opens the panel once results are in.
function M.list()
  -- todo-comments is lazy-loaded on file events, so it may not be up yet — and
  -- its own setup defers by a tick when called during startup.
  if not package.loaded["todo-comments"] or not require("todo-comments.config").loaded then
    pcall(function()
      require("lazy").load({ plugins = { "todo-comments.nvim" } })
    end)
    vim.wait(500, function()
      return package.loaded["todo-comments"] and require("todo-comments.config").loaded
    end)
  end
  local ok, Search = pcall(require, "todo-comments.search")
  if not ok or not require("todo-comments.config").loaded then
    vim.notify("todo-comments is not available", vim.log.levels.ERROR)
    return
  end
  Search.search(function(results)
    if vim.tbl_isempty(results) then
      vim.notify("no REVIEW notes", vim.log.levels.INFO)
      return
    end
    vim.fn.setqflist({}, " ", { title = "REVIEW notes", items = results })
    if not pcall(vim.cmd, "Trouble qflist open") then
      vim.cmd("copen")
    end
  end, { keywords = "REVIEW", disable_not_found_warnings = true })
end

M.subcommands = { "start", "continue", "note", "doc", "list", "viewed" }

--- Completion for `:Review`: subcommands, then kinds for `note`.
---@param lead string
---@param line string
---@return string[]
function M.complete(lead, line)
  local words = vim.split(vim.trim(line), "%s+")
  local at_arg = #words > 2 or (#words == 2 and lead == "")
  local candidates = M.subcommands
  if at_arg then
    candidates = words[2] == "note" and M.kinds or {}
  end
  return vim.tbl_filter(function(c)
    return c:find(lead, 1, true) == 1
  end, candidates)
end

--- The `:Review` dispatcher.
---@param opts table
function M.dispatch(opts)
  local sub, arg = opts.fargs[1], opts.fargs[2]
  if sub == "start" then
    M.start()
  elseif sub == "continue" then
    M.continue()
  elseif sub == "note" then
    M.note(arg or "issue")
  elseif sub == "doc" then
    M.doc()
  elseif sub == "list" then
    M.list()
  elseif sub == "viewed" then
    M.toggle_viewed()
  else
    vim.notify("usage: :Review " .. table.concat(M.subcommands, "|"), vim.log.levels.ERROR)
  end
end

function M.setup()
  vim.api.nvim_create_user_command("Review", M.dispatch, {
    nargs = "+",
    desc = "Manual review of agent-generated commits",
    complete = M.complete,
  })

  -- `<leader>r` is uncontested (LazyVim only uses it for the `editor.refactoring`
  -- extra, which isn't enabled). The commands remain the discoverable route.
  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", "<leader>r" .. lhs, rhs, { desc = desc })
  end
  map("r", M.start, "Review: start (pick base)")
  map("c", M.continue, "Review: continue (saved base + ✓)")
  map("v", M.toggle_viewed, "Review: toggle viewed ✓")
  map("d", M.doc, "Review: open doc")
  map("l", M.list, "Review: list notes")
  for lhs, kind in pairs({ i = "issue", s = "suggestion", q = "question", n = "nit" }) do
    map(lhs, function()
      M.note(kind)
    end, "Review: note " .. kind)
  end

  -- Safety net: repaint whenever a file panel window is entered or its buffer is
  -- (re)displayed, which covers panel buffers being recreated rather than redrawn.
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = vim.api.nvim_create_augroup("review_viewed_marks", { clear = true }),
    callback = function(args)
      if vim.bo[args.buf].filetype == "DiffviewFiles" and next(M.viewed) then
        vim.schedule(function()
          M.install()
        end)
      end
    end,
  })

  -- Diffview re-runs its own highlight setup on every colorscheme change, so
  -- re-assert the dimmed filler after it (scheduled, to land last).
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("review_diff_hl", { clear = true }),
    callback = function()
      vim.schedule(M.dim_deleted_filler)
    end,
  })
end

return M
