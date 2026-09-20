-- Explorer: start with dotfiles and gitignored paths already visible.
-- `H` / `I` toggle them per-session; `<a-h>` / `<a-i>` in other pickers.
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            hidden = true,
            ignored = true,
          },
        },
      },
    },
  },
}
