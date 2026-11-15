run_shell() {
    sudo dnf install -y zsh zsh-autosuggestions zsh-syntax-highlighting

    download https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v31.9.1/posh-linux-amd64 \
        574074a4e84797180e0bda0d133da5f01fbda89ecdb450134c7e566b9a389212 "$CACHE/oh-my-posh"
    install -m 755 "$CACHE/oh-my-posh" "$HOME/.local/bin/oh-my-posh"

    local shell
    shell="$(command -v zsh)"
    if [[ "$(getent passwd "$(id -un)" | cut -d: -f7)" != "$shell" ]]; then
        chsh -s "$shell"
    fi
}
