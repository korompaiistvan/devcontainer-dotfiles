# devcontainer-dotfiles

Portable dotfiles for macOS, Linux, and devcontainers: zsh (Oh My Zsh + Powerlevel10k), Neovim (LazyVim), Ghostty.

## Quick start

```sh
git clone https://github.com/korompaiistvan/devcontainer-dotfiles ~/devcontainer-dotfiles
cd ~/devcontainer-dotfiles
./install.sh            # full setup (packages + symlinks)
./install.sh --dry-run  # preview without changing anything
./install.sh --no-packages  # symlinks only
```

`install.sh` is POSIX `sh`, idempotent, and safe to re-run. It symlinks (never copies):

| Repo | Target |
| --- | --- |
| `.zshrc` | `~/.zshrc` |
| `.zprofile` | `~/.zprofile` |
| `.p10k.zsh` | `~/.p10k.zsh` |
| `.config/nvim` | `~/.config/nvim` |
| `.config/ghostty/config` | `~/.config/ghostty/config` |

Existing files are moved to `~/.dotfiles-backup/<timestamp>/`. Because targets are symlinks, `git pull` updates every machine and local edits show up as repo diffs.

## Per OS

- **macOS**: needs Homebrew (`https://brew.sh`). Packages come from `Brewfile` (`brew bundle`).
- **Linux (Debian/Ubuntu)**: needs root or passwordless sudo. Packages come from `packages.linux.txt` (`fd` ships as `fd-find`/`fdfind`; lazygit is skipped with a pointer to upstream installs).
- **Devcontainers**: full OMZ + p10k stack everywhere (no minimal prompt). `install.sh` detects containers (`$DEVCONTAINER`, `$REMOTE_CONTAINERS`, `/.dockerenv`) and skips `chsh`. Wire into `devcontainer.json`:
  ```json
  { "dotfiles.repository": "https://github.com/korompaiistvan/devcontainer-dotfiles" }
  ```

## Host-specific config (not committed)

`~/.zshrc.local` is sourced last by `.zshrc` and listed in `.gitignore`. `install.sh` creates it from `.zshrc.local.example` once and never overwrites it. Put work-only or machine-only things there:

```sh
export PATH="$HOME/.optimus/bin:$PATH"
```

## Fonts

Powerlevel10k needs a Nerd Font (otherwise icons break). Recommended: MesloLGS NF (`p10k configure` offers the install, or `cask "font-meslo-lg-nerd-font"` in the Brewfile comments).

## Layout

- `install.sh` — portable installer (`sh`, `--dry-run`, `--no-packages`)
- `.zshrc` / `.zprofile` — portable shell setup (Homebrew mac+Linux paths, guarded `$HOME`-based PATHs, eager-but-guarded nvm, bun, opencode)
- `.p10k.zsh` — Powerlevel10k config (edit via `p10k configure`)
- `.config/nvim` — LazyVim config (catppuccin-mocha, explorer shows hidden/ignored, `:Review` Diffview workflow)
- `.config/ghostty/config` — Ghostty keybinds + `Catppuccin Mocha` theme
- `Brewfile` / `packages.linux.txt` — package manifests
