# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Default devcontainer zshrc file
export ZSH=$HOME/.oh-my-zsh

plugins=(git)
source $ZSH/oh-my-zsh.sh

DISABLE_UPDATE_PROMPT=true
DISABLE_AUTO_UPDATE=true

# Install Powerlevel10k
P10K_LOCATION="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/powerlevel10k"
if [[ ! -d ${P10K_LOCATION}/powerlevel10k ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${P10K_LOCATION}/powerlevel10k
  echo "source ${P10K_LOCATION}/powerlevel10k/powerlevel10k.zsh-theme" >> ~/.zshrc
fi
source /home/node/.oh-my-zsh/custom/powerlevel10k/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
