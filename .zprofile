# Portable login-shell setup: Homebrew on macOS and Linuxbrew on Linux.
# Interactive config lives in ~/.zshrc; this only ensures `brew` is on PATH
# for login shells (macOS Terminal/Ghostty, SSH, devcontainers).
if ! command -v brew >/dev/null 2>&1; then
  for _brew in /opt/homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$_brew" ]; then
      eval "$("$_brew" shellenv)"
      break
    fi
  done
  unset _brew
fi
