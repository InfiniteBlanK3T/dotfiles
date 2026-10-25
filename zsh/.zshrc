# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ~/.zshrc — managed by ~/.dotfiles
# Symlinked: ln -sf ~/.dotfiles/zsh/.zshrc ~/.zshrc

# This file is for zsh only — fail clearly if it is sourced from bash/sh.
if [ -z "${ZSH_VERSION:-}" ]; then
  echo "~/.zshrc is a zsh config, not bash. Start zsh instead: exec zsh" >&2
  return 1 2>/dev/null || exit 1
fi

export DOTFILES="$HOME/.dotfiles"

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# Load in order: platform first (sets OS_TYPE + brew), then path/env, then shell behaviour
source "$DOTFILES/zsh/platform.zsh"
source "$DOTFILES/zsh/path.zsh"
source "$DOTFILES/zsh/env.zsh"
source "$DOTFILES/zsh/options.zsh"
source "$DOTFILES/zsh/history.zsh"
source "$DOTFILES/zsh/plugins.zsh"

# Machine-local config and secrets — not tracked in git
[[ -f "$DOTFILES/zsh/local.zsh" ]] && source "$DOTFILES/zsh/local.zsh"

# Powerlevel10k config
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
