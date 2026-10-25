plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  echo "plugins.zsh: Oh My Zsh not found at $ZSH — run ~/.dotfiles/bootstrap.sh" >&2
fi

# Tools (portable, guarded — safe if not installed)
command -v fzf &>/dev/null && eval "$(fzf --zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"