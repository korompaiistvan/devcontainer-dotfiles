#!/bin/zsh
cp ${0:a:h}/.zshrc "$HOME/.zshrc"
cp ${0:a:h}/.p10k.zsh "$HOME/.p10k.zsh"

mkdir -p "$HOME/.config"
cp -r ${0:a:h}/.config/nvim "$HOME/.config/nvim"
