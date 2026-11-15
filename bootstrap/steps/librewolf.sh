# shellcheck shell=bash
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

install_librewolf_prefs() {
    local source="$HOME/projects/personal/librewolf-config/user.js" profiles profile

    profiles="$(find_librewolf_profiles)"
    [[ -n "$profiles" ]] || {
        echo "bootstrap: не найден ни один профиль LibreWolf; восстанови через scripts/librewolf/profiles.sh и перезапусти" >&2
        return 1
    }

    while IFS= read -r profile; do
        link_config "$source" "$profile/user.js"
    done <<< "$profiles"
}

install_librewolf_chrome() {
    local source="$HOME/projects/personal/librewolf-config/chrome" profiles profile

    profiles="$(find_librewolf_profiles)"
    [[ -n "$profiles" ]] || { echo "bootstrap: не найден ни один профиль LibreWolf" >&2; return 1; }

    local resolved
    resolved="$(readlink -f "$source")"
    while IFS= read -r profile; do
        if [[ -L "$profile/chrome" ]]; then
            [[ "$(readlink -f "$profile/chrome")" == "$resolved" ]] && continue
            echo "bootstrap: $profile/chrome чужой симлинк; перенеси вручную и повтори" >&2
            return 1
        fi
        if [[ -e "$profile/chrome" ]]; then
            echo "bootstrap: $profile/chrome существует; перенеси вручную и повтори" >&2
            return 1
        fi
        ln -s "$resolved" "$profile/chrome"
    done <<< "$profiles"
}

install_librewolf_policies() {
    local source="$HOME/projects/personal/librewolf-config/policies.json"

    local merged
    merged="$(mktemp)"
    local config_home="$HOME/projects/personal/librewolf-config"
    python3 "$config_home/scripts/merge-policies.py" \
        "$source" \
        "$config_home/chrome/sidebery-sidebar.css" \
        /usr/share/librewolf/distribution/policies.json > "$merged"
    sudo install -D -m 644 "$merged" /usr/share/librewolf/distribution/policies.json
    rm -f "$merged"
}

install_librewolf_autoconfig() {
    local config_home="$HOME/projects/personal/librewolf-config"

    sudo python3 "$config_home/scripts/install-autoconfig.py" --files
    python3 "$config_home/scripts/install-autoconfig.py" --cache
}

run_librewolf() {
    install_librewolf
    install_librewolf_prefs
    install_librewolf_chrome
    install_librewolf_policies
    install_librewolf_autoconfig
}
