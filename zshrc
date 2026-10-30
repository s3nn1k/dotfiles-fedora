source "$HOME/.zprofile"
eval "$(oh-my-posh init zsh --config "${XDG_CONFIG_HOME:-$HOME/.config}/zenwritten_dark/zenwritten_dark.omp.json")"
autoload -Uz compinit
compinit
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

