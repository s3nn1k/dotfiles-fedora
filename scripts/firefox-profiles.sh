#!/usr/bin/env bash
set -euo pipefail

CREDENTIALS_FIREFOX="$HOME/credentials/firefox"
PROFILES_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
    echo "firefox-profiles: $*" >&2
    exit 1
}

usage() {
    cat >&2 <<'EOF'
usage: firefox-profiles.sh init|push|pull|reset
  init            создать отсутствующие профили из ~/credentials/firefox через firefox -CreateProfile и зарегистрировать профили в панели
  push            скопировать places.sqlite (закладки; история вырезается) из профилей в ~/credentials/firefox
  pull            развернуть places.sqlite (закладки, как выгружено push) из ~/credentials/firefox в профили и зарегистрировать их в панели
  reset           удалить профили: блоки profiles.ini, каталоги, строки стора панели; данные в ~/credentials/firefox остаются
EOF
    exit 1
}

require_firefox_closed() {
    if pgrep -x firefox >/dev/null; then
        fail "Firefox запущен, закрой и повтори"
    fi
}

ensure_clean_sqlite() {
    local database="$1"
    if [[ -e "$database-wal" || -e "$database-journal" ]]; then
        fail "база не закрыта чисто: $(basename "$database"); закрой Firefox и повтори"
    fi
}

is_git_crypt_locked() {
    [[ -f "$1" ]] || return 1
    printf '\000GITCRYPT' | cmp -s - <(head -c 9 "$1")
}

PROFILE_NAMES=()

profile_names() {
    [[ -d "$CREDENTIALS_FIREFOX" ]] || fail "нет ~/credentials/firefox - нечего разворачивать"
    PROFILE_NAMES=()
    local entry
    for entry in "$CREDENTIALS_FIREFOX"/*; do
        [[ -d "$entry" ]] && PROFILE_NAMES+=("${entry##*/}")
    done
    [[ ${#PROFILE_NAMES[@]} -gt 0 ]] || fail "нет ~/credentials/firefox - нечего разворачивать"
}

cmd_init() {
    require_firefox_closed
    command -v firefox >/dev/null || fail "firefox не найден в PATH"
    profile_names
    local name
    for name in "${PROFILE_NAMES[@]}"; do
        if [[ ! -d "$PROFILES_ROOT/$name" ]]; then
            firefox -CreateProfile "$name $PROFILES_ROOT/$name" >/dev/null 2>&1 || fail "не создан профиль: $name"
            echo "firefox-profiles: создан профиль: $PROFILES_ROOT/$name"
        fi
    done
    "$SCRIPT_DIR/firefox-register.py" register "${PROFILE_NAMES[@]}"
}

cmd_push() {
    require_firefox_closed
    profile_names
    local failed=0
    local name profile credentials_dir
    for name in "${PROFILE_NAMES[@]}"; do
        profile="$PROFILES_ROOT/$name"
        credentials_dir="$CREDENTIALS_FIREFOX/$name"
        if [[ ! -d "$profile" ]]; then
            echo "firefox-profiles: $name: профиль отсутствует: $profile" >&2
            failed=1
            continue
        fi
        if [[ ! -f "$profile/places.sqlite" ]]; then
            echo "firefox-profiles: $name: нет places.sqlite в профиле" >&2
            failed=1
            continue
        fi
        ensure_clean_sqlite "$profile/places.sqlite"
        mkdir -p "$credentials_dir"
        cp "$profile/places.sqlite" "$credentials_dir/places.sqlite"
        chmod 600 "$credentials_dir/places.sqlite"
        local strip_output=""
        if ! strip_output=$("$SCRIPT_DIR/firefox-strip.py" "$name" "$credentials_dir/places.sqlite" 2>&1); then
            echo "firefox-profiles: $name: история не вырезана: $strip_output" >&2
            failed=1
            continue
        fi
        echo "$strip_output"
    done
    echo "firefox-profiles: изменения в ~/credentials - закоммить и запушь"
    [[ $failed -eq 0 ]] || exit 1
}

cmd_pull() {
    require_firefox_closed
    profile_names
    local failed=0
    local name profile credentials_dir
    local -a pulled=()
    for name in "${PROFILE_NAMES[@]}"; do
        profile="$PROFILES_ROOT/$name"
        credentials_dir="$CREDENTIALS_FIREFOX/$name"
        if [[ ! -d "$profile" ]]; then
            echo "firefox-profiles: $name: профиль не создан: сначала init ($profile)" >&2
            failed=1
            continue
        fi
        if [[ ! -f "$credentials_dir/places.sqlite" ]]; then
            echo "firefox-profiles: $name: нет places.sqlite в $credentials_dir" >&2
            failed=1
            continue
        fi
        if is_git_crypt_locked "$credentials_dir/places.sqlite"; then
            fail "credentials заперт: запусти scripts/setup-secrets.sh unlock"
        fi
        ensure_clean_sqlite "$profile/places.sqlite"
        cp "$credentials_dir/places.sqlite" "$profile/places.sqlite"
        chmod 600 "$profile/places.sqlite"
        echo "firefox-profiles: $name: скопирован places.sqlite"
        pulled+=("$name")
    done
    if [[ ${#pulled[@]} -gt 0 ]]; then
        "$SCRIPT_DIR/firefox-register.py" register "${pulled[@]}"
    fi
    [[ $failed -eq 0 ]] || exit 1
}

cmd_reset() {
    require_firefox_closed
    profile_names
    "$SCRIPT_DIR/firefox-register.py" unregister "${PROFILE_NAMES[@]}"
    local name
    for name in "${PROFILE_NAMES[@]}"; do
        rm -rf "$PROFILES_ROOT/$name"
    done
    echo "firefox-profiles: удалены профили: ${PROFILE_NAMES[*]} и артефакты регистрации; повтори init (+pull)"
}

case "${1:-}" in
    init) cmd_init ;;
    push) cmd_push ;;
    pull) cmd_pull ;;
    reset) cmd_reset ;;
    *) usage ;;
esac
