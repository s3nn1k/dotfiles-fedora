gh_auth_login() {
    local temporary_git_config login_status
    temporary_git_config="$(mktemp "${TMPDIR:-/tmp}/dotfiles-fedora-gh.XXXXXX")"
    if GIT_CONFIG_GLOBAL="$temporary_git_config" gh auth login --git-protocol https; then
        rm -f "$temporary_git_config"
        return 0
    else
        login_status=$?
        rm -f "$temporary_git_config" || return 1
        return "$login_status"
    fi
}

run_cli-tools() {
    install_command "$REPOSITORY/bin/swayidle_laptop.py" swayidle-laptop

    install_command "$REPOSITORY/bin/credentials-setup.sh" credentials-setup
    install_command "$REPOSITORY/bin/git-crypt-repo.sh" git-crypt-repo
    install_command "$REPOSITORY/bin/git-crypt-repo.sh" git-crypt-textconv
    install_command "$REPOSITORY/bin/git-cred-read.sh" git-cred-read
    install_command "$REPOSITORY/bin/herdr-ws.sh" herdr-ws
    link_config "$LOCAL_BIN/git-crypt-repo" "$HOME/.local/share/git-crypt/hooks/pre-commit"
    link_config "$REPOSITORY/systemd/user/ssh-agent.service" "$CONFIGURATION_HOME/systemd/user/ssh-agent.service"
    systemctl --user daemon-reload
    systemctl --user enable --now ssh-agent.service

    if gh auth token --hostname github.com >/dev/null 2>&1; then
        echo "GitHub авторизация уже настроена"
    else
        echo "gh: не авторизован — вход через HTTPS"
        gh_auth_login
    fi

    download https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v31.9.1/posh-linux-amd64 \
        574074a4e84797180e0bda0d133da5f01fbda89ecdb450134c7e566b9a389212 "$CACHE/oh-my-posh"
    install -m 755 "$CACHE/oh-my-posh" "$HOME/.local/bin/oh-my-posh"

    local shell
    shell="$(command -v zsh)"
    if [[ "$(getent passwd "$(id -un)" | cut -d: -f7)" != "$shell" ]]; then
        chsh -s "$shell"
    fi

    install_command "$REPOSITORY/bin/wt" wt
}
