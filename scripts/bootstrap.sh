#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/lib.sh"

STEP_ORDER=(base mihomo hardening keyboard git nkp configs themes shell credentials obsidian projects neovim pi-agent herdr media docker librewolf cleanup)

for step_file in "$(dirname "${BASH_SOURCE[0]}")"/../bootstrap/steps/*.sh; do
    # shellcheck source=/dev/null
    source "$step_file"
done

main() {
    local arg step_name full_run=false
    local -a selected=() forwarded=()
    if (( $# == 0 )); then
        full_run=true
        selected=("${STEP_ORDER[@]}")
    elif [[ "$1" == "--list" && $# -eq 1 ]]; then
        for step_name in "${STEP_ORDER[@]}"; do
            printf '%s\n' "$step_name"
        done
        return 0
    else
        for arg in "$@"; do
            if [[ " ${STEP_ORDER[*]} " == *" $arg "* ]]; then
                if [[ ${#forwarded[@]} -gt 0 ]]; then
                    echo "bootstrap: неизвестный шаг: $arg (см. --list)" >&2
                    exit 2
                fi
                selected+=("$arg")
            elif [[ ${#selected[@]} -eq 1 ]]; then
                forwarded+=("$arg")
            else
                echo "bootstrap: неизвестный шаг: $arg (см. --list)" >&2
                exit 2
            fi
        done
    fi

    require_fedora
    sudo -v
    mkdir -p "$CACHE" "$LOCAL_BIN"

    for step_name in "${selected[@]}"; do
        "run_$step_name" "${forwarded[@]}"
    done
    if [[ "$full_run" != true ]]; then
        return 0
    fi
    printf '%s\n' "Готово. Выйди из сессии и войди снова для zsh и группы docker." \
        "Секреты: nkp unlock main, затем scripts/unlock-gitcrypt.sh (ключ credentials) - раскладка, mihomo и права сами." \
        "LibreWolf: профили создай в панели браузера и перезапусти scripts/bootstrap.sh librewolf (user.js, тема и политики лягут в каждый профиль); закладки - Ctrl+Shift+O -> Export Bookmarks to HTML в ~/credentials/librewolf/bookmarks.<профиль>.html, на другой машине - Import Bookmarks from HTML того же файла." \
        "VPN: смена подписки - ~/credentials/mihomo/subscription-url + scripts/bootstrap.sh mihomo, панель http://127.0.0.1:9090/ui."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
