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
  init            создать отсутствующие профили из ~/credentials/firefox через firefox -CreateProfile, линковать user.js и chrome, зарегистрировать их в панели Firefox
  push            скопировать places.sqlite (закладки; история вырезается) из профилей в ~/credentials/firefox
  pull            развернуть places.sqlite (закладки) из ~/credentials/firefox в профили и зарегистрировать их в панели (затирает локальные изменения - сначала push; Firefox получателя не старее источника)
  reset           полный вайп всех профилей Firefox: ini-блоки, строки панели, каталоги, installs.ini и Profile Groups; credentials остаются; порядок развёртывания: init, первый запуск firefox -P <слаг>, init, pull
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

link_profile_entry() {
    local source="$1" target="$2" name="$3"
    if [[ -L "$target" ]]; then
        ln -sfn "$source" "$target"
        return
    fi
    if [[ -e "$target" ]]; then
        echo "firefox-profiles: $name: $target уже существует и не симлинк - не тронут"
        return
    fi
    ln -s "$source" "$target"
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
        link_profile_entry "$SCRIPT_DIR/../firefox/user.js" "$PROFILES_ROOT/$name/user.js" "$name"
        link_profile_entry "$SCRIPT_DIR/../firefox/chrome" "$PROFILES_ROOT/$name/chrome" "$name"
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
    local name profile credentials_dir strip_output
    for name in "${PROFILE_NAMES[@]}"; do
        profile="$PROFILES_ROOT/$name"
        credentials_dir="$CREDENTIALS_FIREFOX/$name"
        if [[ ! -d "$profile" ]]; then
            echo "firefox-profiles: $name: профиль отсутствует: $profile" >&2
            failed=1
            continue
        fi
        mkdir -p "$credentials_dir"
        if [[ ! -f "$profile/places.sqlite" ]]; then
            echo "firefox-profiles: $name: нет places.sqlite в профиле" >&2
            failed=1
            continue
        fi
        ensure_clean_sqlite "$profile/places.sqlite"
        if is_git_crypt_locked "$credentials_dir/places.sqlite"; then
            fail "credentials заперт: запусти scripts/setup-secrets.sh unlock"
        fi
        if ! cp "$profile/places.sqlite" "$credentials_dir/places.sqlite.tmp"; then
            rm -f "$credentials_dir/places.sqlite.tmp"
            fail "не скопирован places.sqlite: $profile"
        fi
        strip_output=""
        if ! strip_output=$("$SCRIPT_DIR/firefox-strip.py" "$name" "$credentials_dir/places.sqlite.tmp" 2>&1); then
            echo "firefox-profiles: $name: история не вырезана: $strip_output" >&2
            rm -f "$credentials_dir/places.sqlite.tmp"
            failed=1
            continue
        fi
        echo "$strip_output"
        chmod 600 "$credentials_dir/places.sqlite.tmp"
        mv "$credentials_dir/places.sqlite.tmp" "$credentials_dir/places.sqlite" || {
            rm -f "$credentials_dir/places.sqlite.tmp"
            fail "не заменён places.sqlite: $credentials_dir"
        }
    done
    [[ $failed -eq 0 ]] || exit 1
    echo "firefox-profiles: изменения в ~/credentials - закоммить и запушь"
}

cmd_pull() {
    require_firefox_closed
    profile_names
    local failed=0
    local name profile credentials_dir local_version credentials_version
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
        if [[ -f "$profile/places.sqlite" ]]; then
            cp "$profile/places.sqlite" "$profile/places.sqlite.pre-pull" || fail "не сохранён pre-pull бэкап: $profile/places.sqlite"
            local_version="$(sqlite_user_version "$profile/places.sqlite")" || fail "не прочитан user_version: $profile/places.sqlite"
            credentials_version="$(sqlite_user_version "$credentials_dir/places.sqlite")" || fail "не прочитан user_version: $credentials_dir/places.sqlite"
            if (( credentials_version > local_version )); then
                echo "firefox-profiles: $name: источник новее Firefox получателя - база может быть отброшена; обнови Firefox и повтори pull"
            fi
        fi
        if ! cp "$credentials_dir/places.sqlite" "$profile/places.sqlite.tmp"; then
            rm -f "$profile/places.sqlite.tmp"
            fail "не скопирован places.sqlite: $credentials_dir"
        fi
        chmod 600 "$profile/places.sqlite.tmp"
        mv "$profile/places.sqlite.tmp" "$profile/places.sqlite" || {
            rm -f "$profile/places.sqlite.tmp"
            fail "не заменён places.sqlite: $profile"
        }
        echo "firefox-profiles: $name: скопирован places.sqlite"
        pulled+=("$name")
    done
    if [[ ${#pulled[@]} -gt 0 ]]; then
        "$SCRIPT_DIR/firefox-register.py" "$PROFILES_ROOT" register "${pulled[@]}" || failed=1
    fi
    [[ $failed -eq 0 ]] || exit 1
}

remove_profile_dir() {
    local root="$1" path="$2" dir
    if [[ "/$path/" == *"/../"* ]]; then
        echo "firefox-profiles: $path: путь содержит '..' - каталог не тронут" >&2
        return 1
    fi
    if [[ "$path" == /* ]]; then
        if [[ "$path" != "$HOME"/* ]]; then
            echo "firefox-profiles: $path: нестандартный путь вне домашнего каталога - удали вручную: $path" >&2
            return 1
        fi
        dir="$path"
    else
        dir="$root/$path"
    fi
    if [[ -z "$path" || "$path" == "." || "$dir" == "$root" || "$dir" == "$HOME" || "$dir" == "/" ]]; then
        echo "firefox-profiles: $dir: цель совпадает с защищаемым каталогом - не тронут" >&2
        return 1
    fi
    rm -rf "$dir"
}

cmd_reset() {
    require_firefox_closed
    local ini="$PROFILES_ROOT/profiles.ini"
    local -a unregister_names=() profile_dirs=()
    local name path dir skipped=0
    if [[ -f "$ini" ]]; then
        while IFS=$'\t' read -r name path; do
            unregister_names+=("$name")
            profile_dirs+=("$path")
        done < <(awk '
            /^\[/ {
                if (in_profile) {
                    if (name != "" && path != "") {
                        print name "\t" path
                    } else {
                        incomplete++
                    }
                }
                in_profile = ($0 ~ /^\[Profile[0-9]+\]$/)
                name = ""
                path = ""
                next
            }
            in_profile && /=/ {
                eq = index($0, "=")
                key = substr($0, 1, eq - 1)
                value = substr($0, eq + 1)
                if (key == "Name") {
                    name = value
                } else if (key == "Path") {
                    path = value
                }
            }
            END {
                if (in_profile) {
                    if (name != "" && path != "") {
                        print name "\t" path
                    } else {
                        incomplete++
                    }
                }
                if (incomplete > 0) {
                    print "firefox-profiles: " incomplete " [Profile]-блоков без Name/Path - их каталоги не тронуты" > "/dev/stderr"
                }
            }
        ' "$ini")
        if [[ ${#unregister_names[@]} -gt 0 ]]; then
            if ! "$SCRIPT_DIR/firefox-register.py" "$PROFILES_ROOT" unregister "${unregister_names[@]}"; then
                fail "регистратор не справился - профили не удалены"
            fi
        fi
    fi
    if [[ ${#profile_dirs[@]} -gt 0 ]]; then
        for path in "${profile_dirs[@]}"; do
            if ! remove_profile_dir "$PROFILES_ROOT" "$path"; then
                skipped=$((skipped + 1))
            fi
        done
    fi
    rm -f "$PROFILES_ROOT/profiles.ini" "$PROFILES_ROOT/installs.ini"
    rm -rf "$PROFILES_ROOT/Profile Groups"
    find "$PROFILES_ROOT" -mindepth 1 -type d -empty -delete || echo "firefox-profiles: не удалось удалить пустые каталоги в $PROFILES_ROOT" >&2
    echo "firefox-profiles: Firefox пуст; порядок развёртывания: init, первый запуск firefox -P <слаг>, повторный init, pull"
    if (( skipped > 0 )); then
        echo "firefox-profiles: пропущено каталогов: $skipped - удали вручную (см. предупреждения выше)"
    fi
}

case "${1:-}" in
    init) cmd_init ;;
    push) cmd_push ;;
    pull) cmd_pull ;;
    reset) cmd_reset ;;
    *) usage ;;
esac
