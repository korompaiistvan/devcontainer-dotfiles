#!/bin/sh
# Portable dotfiles installer: macOS, Linux, and devcontainers.
#
# Usage:
#   ./install.sh [--dry-run] [--no-packages]
#
# What it does (idempotent, safe to re-run):
#   - installs OS packages (Homebrew bundle on macOS, apt on Debian/Ubuntu)
#   - clones Oh My Zsh + Powerlevel10k if missing (no interactive prompts)
#   - symlinks ~/.zshrc, ~/.zprofile, ~/.p10k.zsh, ~/.config/nvim,
#     ~/.config/ghostty/config to this repo (backs up existing files)
#   - creates an empty ~/.zshrc.local from the example if none exists
#
# Symlinks (not copies) so `git pull` updates every machine and local edits
# show up as repo diffs. Never commits ~/.zshrc.local (host-specific).

set -eu

DRY_RUN=0
INSTALL_PACKAGES=1
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-packages) INSTALL_PACKAGES=0 ;;
    -h|--help)
      echo "Usage: ./install.sh [--dry-run] [--no-packages]"
      exit 0
      ;;
    *) echo "install.sh: unknown option: $arg" >&2; exit 1 ;;
  esac
done

REPO="$(cd "$(dirname "$0")" && pwd -P)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
# DOTFILES_OS override exists for testing the Linux branch on macOS.
OS="${DOTFILES_OS:-$(uname -s)}"
ARCH="$(uname -m)"

log() { printf '%s\n' "install.sh: $*"; }
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "install.sh [dry-run]: $*"
  else
    "$@"
  fi
}

is_container() {
  [ -n "${DEVCONTAINER:-}" ] || [ -n "${REMOTE_CONTAINERS:-}" ] || [ -f "/.dockerenv" ]
}

have() { command -v "$1" >/dev/null 2>&1; }

install_packages() {
  if [ "$INSTALL_PACKAGES" -eq 0 ]; then
    log "skipping package install (--no-packages)"
    return
  fi
  case "$OS" in
    Darwin)
      if ! have brew; then
        log "Homebrew not found; install it first: https://brew.sh (skipping packages)"
        return
      fi
      if [ -f "$REPO/Brewfile" ]; then
        log "brew bundle --file=$REPO/Brewfile"
        if [ "$DRY_RUN" -eq 0 ]; then
          brew bundle "--file=$REPO/Brewfile" || log "warning: brew bundle had errors"
        fi
      fi
      ;;
    Linux)
      if have apt-get; then
        # Debian/Ubuntu. Needs root or passwordless sudo; never prompt.
        SUDO=""
        if [ "$(id -u)" -ne 0 ]; then
          if have sudo && sudo -n true 2>/dev/null; then
            SUDO="sudo"
          else
            log "no root / passwordless sudo; skipping apt install (re-run with sudo or --no-packages)"
            return
          fi
        fi
        log "apt-get install (zsh, git, curl, neovim, ripgrep, fd, lazygit if available)"
        if [ "$DRY_RUN" -eq 0 ]; then
          $SUDO apt-get update -y || log "warning: apt-get update failed"
          # fd package is `fd-find` on Debian/Ubuntu (binary `fdfind`).
          # lazygit is not in default apt repos; install.sh links config only.
          $SUDO apt-get install -y zsh git curl neovim ripgrep fd-find \
            || log "warning: apt-get install had errors"
          if ! have lazygit; then
            log "lazygit not installed (not in default apt repos); optional: https://github.com/jesseduffield/lazygit#installation"
          fi
        fi
      else
        log "no supported package manager (need apt-get); skipping package install"
      fi
      ;;
    *) log "unknown OS $OS; skipping package install" ;;
  esac
}

# Symlink $dest -> $src, backing up any existing file/dir/symlink elsewhere.
link() {
  src="$1"; dest="$2"
  if [ ! -e "$src" ]; then
    log "warning: source missing, skipping: $src"
    return
  fi
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    log "ok (already linked): $dest"
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    log "backing up $dest -> $BACKUP_DIR/"
    if [ "$DRY_RUN" -eq 0 ]; then
      mkdir -p "$BACKUP_DIR"
      mv "$dest" "$BACKUP_DIR/"
    fi
  fi
  log "linking $dest -> $src"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
  fi
}

bootstrap_shell() {
  # Clone (never run the interactive installer) so ~/.zshrc is never clobbered.
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    if have git; then
      log "cloning oh-my-zsh -> ~/.oh-my-zsh"
      run git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" || log "warning: oh-my-zsh clone failed (offline?)"
    else
      log "git not found; cannot bootstrap oh-my-zsh"
    fi
  else
    log "ok (oh-my-zsh present)"
  fi
  if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
    if have git; then
      log "cloning powerlevel10k"
      if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes"
      fi
      run git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
        "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" \
        || log "warning: powerlevel10k clone failed (offline?)"
    fi
  else
    log "ok (powerlevel10k present)"
  fi
}

maybe_chsh() {
  if have zsh && [ "${SHELL:-}" != "$(command -v zsh)" ]; then
    if is_container; then
      log "container detected; leaving SHELL=${SHELL:-unset} (devcontainers set their own shell)"
    else
      log "trying chsh -s $(command -v zsh) (may prompt; failure is non-fatal)"
      if [ "$DRY_RUN" -eq 0 ]; then
        chsh -s "$(command -v zsh)" || log "chsh failed; set your login shell to zsh manually"
      fi
    fi
  fi
}

main() {
  log "repo: $REPO ($OS/$ARCH)"
  install_packages
  bootstrap_shell
  link "$REPO/.zshrc" "$HOME/.zshrc"
  link "$REPO/.zprofile" "$HOME/.zprofile"
  link "$REPO/.p10k.zsh" "$HOME/.p10k.zsh"
  link "$REPO/.config/nvim" "$HOME/.config/nvim"
  link "$REPO/.config/ghostty/config" "$HOME/.config/ghostty/config"
  if [ ! -f "$HOME/.zshrc.local" ]; then
    log "creating empty ~/.zshrc.local from example"
    if [ "$DRY_RUN" -eq 0 ]; then
      cp "$REPO/.zshrc.local.example" "$HOME/.zshrc.local"
    fi
  else
    log "ok (~/.zshrc.local present, untouched)"
  fi
  maybe_chsh
  # Debian/Ubuntu `fd` binary is `fdfind`; warn if neither is usable.
  if [ "$OS" = "Linux" ] && ! have fd && ! have fdfind; then
    log "warning: neither fd nor fdfind on PATH (telescope/snacks may be slower)"
  fi
  log "done. Restart your shell. p10k needs a Nerd Font: https://github.com/romkatv/powerlevel10k#fonts"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: nothing was changed"
  elif [ -d "$BACKUP_DIR" ]; then
    log "backups in $BACKUP_DIR"
  fi
}

main
