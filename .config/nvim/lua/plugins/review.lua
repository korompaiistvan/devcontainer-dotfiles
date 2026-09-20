-- Manual review of agent-generated commits. Logic lives in `util.review`;
-- this file only wires it up. See that module's header for the workflow.
return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles", "DiffviewFocusFiles" },
    opts = {
      -- Dims the "deleted" filler in the left pane (linked to `Comment`) instead
      -- of painting it `DiffDelete` red — otherwise a new file is a solid red
      -- rectangle the width of the pane.
      enhanced_diff_hl = true,
      file_panel = { listing_style = "tree" },
      -- Only `DiffviewGlobal.emitter` events reach user hooks, so per-file events
      -- (`file_open_post`, `files_updated`) are not available here. The ✓ marks
      -- are repainted from a wrapper around the panel redraw instead; this hook
      -- just installs it when a view is opened directly with `:DiffviewOpen`.
      hooks = {
        view_opened = function()
          vim.schedule(function()
            require("util.review").install()
          end)
        end,
      },
    },
  },

  -- One keyword; the kind is a prefix inside the note (`REVIEW: issue: …`).
  {
    "folke/todo-comments.nvim",
    opts = {
      keywords = {
        REVIEW = { icon = " ", color = "warning" },
      },
    },
  },

  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>r", group = "review", icon = { icon = "󰈈 ", color = "yellow" } },
      },
    },
  },

  {
    "folke/snacks.nvim",
    init = function()
      require("util.review").setup()
    end,
  },
}
