# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- Homebrew (portable: macOS + Linuxbrew) ---
# ~/.zprofile normally handles login shells; keep this as a fallback for
# non-login interactive shells and devcontainers.
if ! command -v brew >/dev/null 2>&1; then
  for _brew in /opt/homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew /usr/local/bin/brew; do
    if [[ -x $_brew ]]; then
      eval "$("$_brew" shellenv)"
      break
    fi
  done
  unset _brew
fi

export ZSH="$HOME/.oh-my-zsh"

# Install Oh My Zsh if not already installed (non-interactive; safe offline).
if [[ ! -d $ZSH ]]; then
  if command -v curl >/dev/null 2>&1 && command -v sh >/dev/null 2>&1; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
  fi
fi

typeset -g ZSH_CUSTOM=${ZSH_CUSTOM:-$ZSH/custom}

# Install Powerlevel10k if not already installed.
if [[ ! -d ${ZSH_CUSTOM}/themes/powerlevel10k ]]; then
  if command -v git >/dev/null 2>&1; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM}/themes/powerlevel10k" || true
  fi
fi

# OMZ update settings must be set BEFORE sourcing oh-my-zsh.sh.
DISABLE_UPDATE_PROMPT=true
DISABLE_AUTO_UPDATE=true
zstyle ':omz:update' mode disabled 2>/dev/null || true

# Theme and plugins (must be set before sourcing oh-my-zsh.sh)
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git)

[[ -f $ZSH/oh-my-zsh.sh ]] && source "$ZSH/oh-my-zsh.sh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# --- Portable PATH additions (all guarded, all $HOME-based) ---
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"

# bun
export BUN_INSTALL="$HOME/.bun"
[[ -d "$BUN_INSTALL/bin" ]] && export PATH="$BUN_INSTALL/bin:$PATH"
# bun completions: prefer the custom dir, fall back to legacy locations
for _bun_completion in \
  "$ZSH_CUSTOM/completions/_bun" \
  "$ZSH/completions/_bun" \
  "$HOME/.bun/_bun"; do
  [[ -s "$_bun_completion" ]] && source "$_bun_completion" && break
done
unset _bun_completion

# nvm (guarded; creates $NVM_DIR if a tool expects it, but never fails the shell)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# --- Host-specific overrides (gitignored, never committed) ---
# Put work-only or machine-only config here, e.g.:
#   export PATH="$HOME/.optimus/bin:$PATH"
if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi
