# shellcheck shell=bash
LIBREWOLF_CONFIG_HOME="$REPOSITORY/librewolf"

librewolf_installed() {
    command -v librewolf >/dev/null 2>&1
}

install_librewolf() {
    if librewolf_installed; then
        echo "librewolf уже установлен"
        return 0
    fi
    download https://repo.librewolf.net/librewolf.repo \
        0706a3f9295f538e3f590fa738fc254884eb58182c93e9ed0bdf4a20d395a392 "$CACHE/librewolf.repo"
    if [[ ! -f /etc/yum.repos.d/librewolf.repo ]]; then
        sudo install -D -m 644 "$CACHE/librewolf.repo" /etc/yum.repos.d/librewolf.repo
    fi
    sudo dnf install -y librewolf
}

find_librewolf_profiles() {
    local profile_root profile_directory
    for profile_root in "$CONFIGURATION_HOME/librewolf/librewolf" "$HOME/.librewolf"; do
        [[ -d "$profile_root" ]] || continue
        for profile_directory in "$profile_root"/*/; do
            [[ -f "$profile_directory/times.json" ]] || continue
            printf '%s\n' "${profile_directory%/}"
        done
    done
}

install_librewolf_configs() {
    local profiles profile
    profiles="$(find_librewolf_profiles)"
    [[ -n "$profiles" ]] || {
        echo "bootstrap: профилей LibreWolf нет; создай их в панели браузера и перезапусти шаг" >&2
        return 0
    }
    while IFS= read -r profile; do
        link_config "$LIBREWOLF_CONFIG_HOME/user.js" "$profile/user.js" '*/librewolf-config/*' || return 1
        link_config "$LIBREWOLF_CONFIG_HOME/chrome" "$profile/chrome" '*/librewolf-config/*' || return 1
    done <<< "$profiles"
}

install_librewolf_policies() {
    jq -e '.policies | type == "object"' "$LIBREWOLF_CONFIG_HOME/policies.json" >/dev/null || {
        echo "bootstrap: librewolf/policies.json невалиден" >&2
        return 1
    }
    sudo install -D -m 644 "$LIBREWOLF_CONFIG_HOME/policies.json" /usr/share/librewolf/distribution/policies.json
}

warn_orphaned_autoconfig() {
    [[ -f /usr/share/librewolf/config.js || -f /usr/share/librewolf/defaults/pref/config-prefs.js ]] || return 0
    echo "bootstrap: осиротевший autoconfig - выполни: sudo rm /usr/share/librewolf/config.js /usr/share/librewolf/defaults/pref/config-prefs.js" >&2
}

run_librewolf() {
    install_librewolf
    install_librewolf_configs
    install_librewolf_policies
    warn_orphaned_autoconfig
}
