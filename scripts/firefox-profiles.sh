#!/usr/bin/env bash
set -euo pipefail

CREDENTIALS_FIREFOX="$HOME/credentials/firefox"
PROFILES_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox"

fail() {
    echo "firefox-profiles: $*" >&2
    exit 1
}

usage() {
    cat >&2 <<'EOF'
usage: firefox-profiles.sh init|push|pull|restore <имя профиля>
  init            создать отсутствующие профили из ~/credentials/firefox через firefox -CreateProfile
  push            скопировать cookies и свежий бэкап закладок из профилей в ~/credentials/firefox
  pull            развернуть cookies и закладки из ~/credentials/firefox в профили
  restore <имя>   поднять закладки из ~/credentials/firefox/<имя> в профиль (с сохранением places.sqlite)
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
    command -v firefox >/dev/null || fail "firefox не найден в PATH"
    profile_names
    local name
    for name in "${PROFILE_NAMES[@]}"; do
        [[ -d "$PROFILES_ROOT/$name" ]] && continue
        firefox -CreateProfile "$name $PROFILES_ROOT/$name" >/dev/null 2>&1 || fail "не создан профиль: $name"
        echo "firefox-profiles: создан профиль: $PROFILES_ROOT/$name"
    done
}

cmd_push() {
    require_firefox_closed
    profile_names
    local failed=0
    local name profile credentials_dir newest candidate backup
    for name in "${PROFILE_NAMES[@]}"; do
        profile="$PROFILES_ROOT/$name"
        credentials_dir="$CREDENTIALS_FIREFOX/$name"
        if [[ ! -d "$profile" ]]; then
            echo "firefox-profiles: $name: профиль отсутствует: $profile" >&2
            failed=1
            continue
        fi
        if [[ ! -f "$profile/cookies.sqlite" ]]; then
            echo "firefox-profiles: $name: нет cookies.sqlite в профиле" >&2
            failed=1
            continue
        fi
        ensure_clean_sqlite "$profile/cookies.sqlite"
        mkdir -p "$credentials_dir"
        cp "$profile/cookies.sqlite" "$credentials_dir/cookies.sqlite"
        chmod 600 "$credentials_dir/cookies.sqlite"
        newest=""
        for candidate in "$profile/bookmarkbackups"/bookmarks-*.jsonlz4; do
            [[ -e "$candidate" && ( -z "$newest" || "$candidate" > "$newest" ) ]] && newest="$candidate"
        done
        if [[ -z "$newest" ]]; then
            echo "firefox-profiles: $name: нет бэкапа закладок - открой и закрой Firefox (бэкап пишется раз в сутки) или сделай Backup в UI закладок" >&2
            failed=1
            continue
        fi
        rm -f "$credentials_dir"/bookmarks-*.jsonlz4
        backup="$credentials_dir/$(basename "$newest")"
        cp "$newest" "$backup"
        chmod 600 "$backup"
    done
    echo "firefox-profiles: изменения в ~/credentials - закоммить и запушь"
    [[ $failed -eq 0 ]] || exit 1
}

cmd_pull() {
    require_firefox_closed
    profile_names
    local failed=0
    local name profile credentials_dir backup
    for name in "${PROFILE_NAMES[@]}"; do
        profile="$PROFILES_ROOT/$name"
        credentials_dir="$CREDENTIALS_FIREFOX/$name"
        if [[ ! -d "$profile" ]]; then
            echo "firefox-profiles: $name: профиль не создан: сначала init ($profile)" >&2
            failed=1
            continue
        fi
        if [[ ! -f "$credentials_dir/cookies.sqlite" ]]; then
            echo "firefox-profiles: $name: нет cookies.sqlite в $credentials_dir" >&2
            failed=1
            continue
        fi
        if is_git_crypt_locked "$credentials_dir/cookies.sqlite"; then
            fail "credentials заперт: запусти scripts/setup-secrets.sh unlock"
        fi
        ensure_clean_sqlite "$profile/cookies.sqlite"
        cp "$credentials_dir/cookies.sqlite" "$profile/cookies.sqlite"
        chmod 600 "$profile/cookies.sqlite"
        for backup in "$credentials_dir"/bookmarks-*.jsonlz4; do
            [[ -e "$backup" ]] || continue
            mkdir -p "$profile/bookmarkbackups"
            cp "$backup" "$profile/bookmarkbackups/"
            chmod 600 "$profile/bookmarkbackups/$(basename "$backup")"
        done
        if [[ -f "$profile/places.sqlite" ]]; then
            echo "firefox-profiles: $name: places.sqlite не пустая, закладки сами не поднимутся - Restore в UI закладок или firefox-profiles.sh restore $name" >&2
        fi
    done
    [[ $failed -eq 0 ]] || exit 1
}

cmd_restore() {
    local name="$1"
    require_firefox_closed
    local profile="$PROFILES_ROOT/$name"
    local credentials_dir="$CREDENTIALS_FIREFOX/$name"
    [[ -d "$profile" ]] || fail "$name: профиль не создан: сначала init ($profile)"
    local stored=("$credentials_dir"/bookmarks-*.jsonlz4)
    [[ -e "${stored[0]}" ]] || fail "$name: нет bookmarks-*.jsonlz4 в $credentials_dir"
    if is_git_crypt_locked "${stored[0]}"; then
        fail "credentials заперт: запусти scripts/setup-secrets.sh unlock"
    fi
    mkdir -p "$profile/bookmarkbackups"
    local backup
    for backup in "${stored[@]}"; do
        cp "$backup" "$profile/bookmarkbackups/"
        chmod 600 "$profile/bookmarkbackups/$(basename "$backup")"
    done
    if [[ -f "$profile/places.sqlite" ]]; then
        if [[ -e "$profile/places.sqlite.pre-restore" ]]; then
            fail "уже есть $profile/places.sqlite.pre-restore, разберись вручную"
        fi
        mv "$profile/places.sqlite" "$profile/places.sqlite.pre-restore"
        rm -f "$profile/places.sqlite-wal" "$profile/places.sqlite-shm"
    fi
    echo "firefox-profiles: $name: следующий старт Firefox поднимет закладки из бэкапа; откат - вернуть places.sqlite.pre-restore на место при закрытом браузере"
}

case "${1:-}" in
    init) cmd_init ;;
    push) cmd_push ;;
    pull) cmd_pull ;;
    restore)
        [[ -n "${2:-}" ]] || usage
        cmd_restore "$2"
        ;;
    *) usage ;;
esac
