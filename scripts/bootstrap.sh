#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/lib.sh"

STEP_ORDER=(packages hardening desktop-links desktop-themes mihomo media docker cli-tools work librewolf cleanup)

for step_file in "$(dirname "${BASH_SOURCE[0]}")"/../bootstrap/steps/*.sh; do
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
        "Дальше: открой nkp, достань ключи и запусти scripts/setup-secrets.sh unlock." \
        "LibreWolf-профили: после unlock запусти scripts/librewolf/profiles.sh reset, затем init (регистрация) и pull (закладки из ~/credentials/librewolf, профили появятся в панели LibreWolf)." \
        "VPN: смена подписки - ~/.config/mihomo/subscription-url + scripts/mihomo-apply.sh, панель http://127.0.0.1:9090/ui."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
