source "$HOME/.zprofile"
export PATH="$HOME/go/bin:$PATH"
export NKP_VAULT="$HOME/credentials/nkp"
[ -f "$HOME/credentials/ssh/wrapper.zsh" ] && source "$HOME/credentials/ssh/wrapper.zsh"
eval "$(oh-my-posh init zsh --config "${XDG_CONFIG_HOME:-$HOME/.config}/zenwritten_dark/zenwritten_dark.omp.json")"
autoload -Uz compinit
compinit
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

alias kb-nova='sudo systemctl start keyd'
alias kb-std='sudo systemctl stop keyd'
