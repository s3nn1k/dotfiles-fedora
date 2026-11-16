# shellcheck shell=bash
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

run_git() {
    sudo dnf install -y git git-crypt gh glab

    link_config "$REPOSITORY/systemd/user/ssh-agent.service" "$CONFIGURATION_HOME/systemd/user/ssh-agent.service"
    systemctl --user daemon-reload
    systemctl --user enable --now ssh-agent.service

    if gh auth token --hostname github.com >/dev/null 2>&1; then
        echo "GitHub авторизация уже настроена"
    else
        echo "gh: не авторизован — вход через HTTPS"
        gh_auth_login
    fi
}
