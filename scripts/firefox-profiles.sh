#!/usr/bin/env bash
set -euo pipefail

CREDENTIALS_FIREFOX="$HOME/credentials/firefox"
DEFAULT_PROFILES_ROOT="$HOME/.mozilla/firefox"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
    echo "firefox-profiles: $*" >&2
    exit 1
}

usage() {
    cat >&2 <<'EOF'
usage: firefox-profiles.sh init|push|pull|reset
  init            создать отсутствующие профили из ~/credentials/firefox через firefox -CreateProfile и зарегистрировать их в панели Firefox
  push            скопировать places.sqlite (закладки; история вырезается) и cookies.sqlite из профилей в ~/credentials/firefox
  pull            развернуть places.sqlite (закладки) и cookies.sqlite из ~/credentials/firefox в профили и зарегистрировать их в панели (затирает локальные изменения - сначала push; Firefox получателя не старее источника)
  reset           удалить профили: ini-блоки, строки панели и каталоги; данные в ~/credentials/firefox остаются; на свежей машине панель инициализируется первым запуском Firefox - повтори init
EOF
    exit 1
}

require_firefox_closed() {
    if pgrep -x firefox >/dev/null; then
        fail "Firefox запущен, закрой и повтори"
    fi
}

profiles_root() {
    local candidate
    for candidate in "$DEFAULT_PROFILES_ROOT" "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox" "$HOME/Library/Application Support/Firefox"; do
        if [[ -f "$candidate/profiles.ini" ]]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    printf '%s\n' "$DEFAULT_PROFILES_ROOT"
}

ensure_clean_sqlite() {
    local database="$1"
    if [[ -s "$database-wal" || -s "$database-journal" ]]; then
        fail "база не закрыта чисто: $(basename "$database"); запусти и закрой Firefox (checkpoint) или устрани sidecar вручную"
    fi
}

is_git_crypt_locked() {
    [[ -f "$1" ]] || return 1
    printf '\000GITCRYPT' | cmp -s - <(head -c 9 "$1")
}

sqlite_user_version() {
    python3 - "$1" <<'PY'
import sqlite3
import sys

try:
    connection = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    print(connection.execute("PRAGMA user_version").fetchone()[0])
    connection.close()
except sqlite3.Error as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
PY
}

PROFILES_ROOT="$(profiles_root)"

PROFILE_NAMES=()

profile_names() {
    [[ -d "$CREDENTIALS_FIREFOX" ]] || fail "нет ~/credentials/firefox - нечего разворачивать"
    PROFILE_NAMES=()
    local entry
    for entry in "$CREDENTIALS_FIREFOX"/*; do
        [[ -d "$entry" ]] || continue
        if [[ "${entry##*/}" == *[[:space:]]* ]]; then
            fail "имя профиля содержит пробел - firefox -CreateProfile парсит 'name path' по первому пробелу: ${entry##*/}"
        fi
        PROFILE_NAMES+=("${entry##*/}")
    done
    [[ ${#PROFILE_NAMES[@]} -gt 0 ]] || fail "нет ~/credentials/firefox - нечего разворачивать"
}

ini_has_profile_block() {
    local ini="$1" name="$2"
    [[ -f "$ini" ]] || return 1
    MATCH_PROFILE_NAME="$name" awk '
        /^\[/ {
            in_profile_block = ($0 ~ /^\[Profile[0-9]+\]$/)
        }
        in_profile_block && /^Name=/ && substr($0, 6) == ENVIRON["MATCH_PROFILE_NAME"] {
            found = 1
            exit
        }
        in_profile_block && /^Path=/ {
            path = substr($0, 6)
            sub(/.*\//, "", path)
            if (path == ENVIRON["MATCH_PROFILE_NAME"]) {
                found = 1
                exit
            }
        }
        END {
            exit !found
        }
    ' "$ini"
}

cmd_init() {
    require_firefox_closed
    command -v firefox >/dev/null || fail "firefox не найден в PATH"
    profile_names
    local ini="$PROFILES_ROOT/profiles.ini"
    local failed=0
    local name
    for name in "${PROFILE_NAMES[@]}"; do
        if [[ ! -d "$PROFILES_ROOT/$name" ]] || ! ini_has_profile_block "$ini" "$name"; then
            firefox -CreateProfile "$name $PROFILES_ROOT/$name" >/dev/null 2>&1 || fail "не создан профиль: $name"
            echo "firefox-profiles: создан профиль: $PROFILES_ROOT/$name"
        fi
    done
    "$SCRIPT_DIR/firefox-register.py" "$PROFILES_ROOT" register "${PROFILE_NAMES[@]}" || failed=1
    [[ $failed -eq 0 ]] || exit 1
}

cmd_push() {
    require_firefox_closed
    if is_git_crypt_locked "$HOME/credentials/git/git-credentials"; then
        fail "credentials заперт: запусти scripts/setup-secrets.sh unlock"
    fi
    profile_names
    local failed=0
    local name profile credentials_dir database strip_output
    for name in "${PROFILE_NAMES[@]}"; do
        profile="$PROFILES_ROOT/$name"
        credentials_dir="$CREDENTIALS_FIREFOX/$name"
        if [[ ! -d "$profile" ]]; then
            echo "firefox-profiles: $name: профиль отсутствует: $profile" >&2
            failed=1
            continue
        fi
        mkdir -p "$credentials_dir"
        for database in places.sqlite cookies.sqlite; do
            if [[ ! -f "$profile/$database" ]]; then
                echo "firefox-profiles: $name: нет $database в профиле" >&2
                failed=1
                continue
            fi
            ensure_clean_sqlite "$profile/$database"
            if is_git_crypt_locked "$credentials_dir/$database"; then
                fail "credentials заперт: запусти scripts/setup-secrets.sh unlock"
            fi
            if ! cp "$profile/$database" "$credentials_dir/$database.tmp"; then
                rm -f "$credentials_dir/$database.tmp"
                fail "не скопирован $database: $profile/$database"
            fi
            if [[ "$database" == places.sqlite ]]; then
                strip_output=""
                if ! strip_output=$("$SCRIPT_DIR/firefox-strip.py" "$name" "$credentials_dir/places.sqlite.tmp" 2>&1); then
                    echo "firefox-profiles: $name: история не вырезана: $strip_output" >&2
                    rm -f "$credentials_dir/places.sqlite.tmp"
                    failed=1
                    continue
                fi
                echo "$strip_output"
            fi
            chmod 600 "$credentials_dir/$database.tmp"
            mv "$credentials_dir/$database.tmp" "$credentials_dir/$database" || {
                rm -f "$credentials_dir/$database.tmp"
                fail "не заменён $database: $credentials_dir/$database"
            }
        done
    done
    [[ $failed -eq 0 ]] || exit 1
    echo "firefox-profiles: изменения в ~/credentials - закоммить и запушь"
}

cmd_pull() {
    require_firefox_closed
    profile_names
    local failed=0
    local name profile credentials_dir database local_version credentials_version slug_copied
    local -a pulled=()
    for name in "${PROFILE_NAMES[@]}"; do
        profile="$PROFILES_ROOT/$name"
        credentials_dir="$CREDENTIALS_FIREFOX/$name"
        slug_copied=0
        if [[ ! -d "$profile" ]]; then
            echo "firefox-profiles: $name: профиль не создан: сначала init ($profile)" >&2
            failed=1
            continue
        fi
        for database in places.sqlite cookies.sqlite; do
            if [[ ! -f "$credentials_dir/$database" ]]; then
                echo "firefox-profiles: $name: нет $database в $credentials_dir" >&2
                failed=1
                continue
            fi
            if is_git_crypt_locked "$credentials_dir/$database"; then
                fail "credentials заперт: запусти scripts/setup-secrets.sh unlock"
            fi
            ensure_clean_sqlite "$profile/$database"
            if [[ -f "$profile/$database" ]]; then
                cp "$profile/$database" "$profile/$database.pre-pull" || fail "не сохранён pre-pull бэкап: $profile/$database"
                local_version="$(sqlite_user_version "$profile/$database")" || fail "не прочитан user_version: $profile/$database"
                credentials_version="$(sqlite_user_version "$credentials_dir/$database")" || fail "не прочитан user_version: $credentials_dir/$database"
                if (( credentials_version > local_version )); then
                    echo "firefox-profiles: $name: $database: источник новее Firefox получателя - база может быть отброшена; обнови Firefox и повтори pull"
                fi
            fi
            if ! cp "$credentials_dir/$database" "$profile/$database.tmp"; then
                rm -f "$profile/$database.tmp"
                fail "не скопирован $database: $credentials_dir/$database"
            fi
            chmod 600 "$profile/$database.tmp"
            mv "$profile/$database.tmp" "$profile/$database" || {
                rm -f "$profile/$database.tmp"
                fail "не заменён $database: $profile/$database"
            }
            slug_copied=1
            echo "firefox-profiles: $name: скопирован $database"
        done
        if (( slug_copied )); then
            pulled+=("$name")
        fi
    done
    if [[ ${#pulled[@]} -gt 0 ]]; then
        "$SCRIPT_DIR/firefox-register.py" "$PROFILES_ROOT" register "${pulled[@]}" || failed=1
    fi
    [[ $failed -eq 0 ]] || exit 1
}

cmd_reset() {
    require_firefox_closed
    profile_names
    if ! "$SCRIPT_DIR/firefox-register.py" "$PROFILES_ROOT" unregister "${PROFILE_NAMES[@]}"; then
        fail "регистратор не справился - профили не удалены"
    fi
    local name
    for name in "${PROFILE_NAMES[@]}"; do
        rm -rf "$PROFILES_ROOT/$name"
    done
    echo "firefox-profiles: удалены профили: ${PROFILE_NAMES[*]}; повтори init (+pull)"
    echo "firefox-profiles: секции [Install] в profiles.ini остаются с Default= на удалённый каталог: Firefox при следующем старте создаст новый пустой дефолтный профиль"
}

case "${1:-}" in
    init) cmd_init ;;
    push) cmd_push ;;
    pull) cmd_pull ;;
    reset) cmd_reset ;;
    *) usage ;;
esac
