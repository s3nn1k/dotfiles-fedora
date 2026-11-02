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
usage: firefox-profiles.sh init|push|pull|reset
  init            создать отсутствующие профили из ~/credentials/firefox через firefox -CreateProfile и зарегистрировать профили в панели
  push            скопировать cookies.sqlite и places.sqlite из профилей в ~/credentials/firefox
  pull            развернуть cookies.sqlite и places.sqlite из ~/credentials/firefox в профили и зарегистрировать их в панели
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

find_store() {
    STORE_ID=""
    STORE_FILE=""
    local ini="$PROFILES_ROOT/profiles.ini"
    local groups_dir="$PROFILES_ROOT/Profile Groups"
    local id=""
    if [[ -f "$ini" ]]; then
        id=$(awk '
            BEGIN { FS = "=" }
            /^\[/ {
                if (want && sid != "") { print sid; exit }
                want = 0
                sid = ""
            }
            $1 == "StoreID" { sid = $2 }
            $1 == "Default" && $2 == "1" { want = 1 }
            END { if (want && sid != "") print sid }
        ' "$ini")
    fi
    if [[ -n "$id" && -f "$groups_dir/$id.sqlite" ]]; then
        STORE_ID="$id"
        STORE_FILE="$groups_dir/$id.sqlite"
        return 0
    fi
    local -a stores=()
    local candidate
    for candidate in "$groups_dir"/*.sqlite; do
        if [[ -f "$candidate" ]]; then
            stores+=("$candidate")
        fi
    done
    if (( ${#stores[@]} == 1 )); then
        STORE_FILE="${stores[0]}"
        STORE_ID="${STORE_FILE##*/}"
        STORE_ID="${STORE_ID%.sqlite}"
        return 0
    fi
    if (( ${#stores[@]} > 1 )); then
        return 2
    fi
    return 1
}

store_schema_ok() {
    python3 - "$1" <<'PYEOF'
import sqlite3
import sys

required = {"path", "name", "avatar", "themeId", "themeFg", "themeBg"}
try:
    conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    columns = {row[1] for row in conn.execute("PRAGMA table_info(Profiles)")}
except sqlite3.Error:
    sys.exit(1)
sys.exit(0 if required <= columns else 1)
PYEOF
}

register_profile() {
    local name="$1"
    local status=0
    find_store || status=$?
    if (( status == 2 )); then
        echo "firefox-profiles: $name: в Profile Groups несколько сторов - разберись вручную" >&2
        return 0
    fi
    if (( status != 0 )); then
        echo "firefox-profiles: $name: панель профилей появится после первого запуска Firefox; повтори init/pull позже" >&2
        return 0
    fi
    if ! store_schema_ok "$STORE_FILE"; then
        echo "firefox-profiles: $name: стор несовместим (нужна таблица Profiles с колонками path,name,avatar,themeId,themeFg,themeBg) - пропущен" >&2
        return 0
    fi
    python3 - "$name" "$STORE_FILE" "$PROFILES_ROOT/profiles.ini" "$PROFILES_ROOT/$name/prefs.js" "$STORE_ID" <<'PYEOF' || return 0
import os
import shutil
import sqlite3
import sys

name, store_path, ini_path, prefs_path, store_id = sys.argv[1:6]

store_pref = f'user_pref("toolkit.profiles.storeID", "{store_id}");'
created_pref = 'user_pref("browser.profiles.created", true);'


def problem(message):
    print(f"firefox-profiles: {name}: {message}", file=sys.stderr)
    sys.exit(1)


def ini_block(lines, wanted_name):
    try:
        name_index = lines.index(f"Name={wanted_name}")
    except ValueError:
        return None
    starts = [i for i, line in enumerate(lines) if line.startswith("[") and i < name_index]
    if not starts:
        return None
    block_start = starts[-1]
    block_end = next(
        (i for i, line in enumerate(lines) if line.startswith("[") and i > block_start),
        len(lines),
    )
    return block_start, block_end


try:
    with open(ini_path, encoding="utf-8") as handle:
        ini_lines = handle.read().splitlines()
    block = ini_block(ini_lines, name)
    if block is None:
        problem(f"в profiles.ini нет блока профиля {name}")
    block_start, block_end = block
    block_store_lines = [
        line for line in ini_lines[block_start + 1:block_end] if line.startswith("StoreID=")
    ]
    ini_needed = block_store_lines != [f"StoreID={store_id}"]

    if os.path.isfile(prefs_path):
        with open(prefs_path, encoding="utf-8") as handle:
            prefs_lines = handle.read().splitlines()
    else:
        prefs_lines = []
    store_hits = [
        line for line in prefs_lines if line.startswith('user_pref("toolkit.profiles.storeID"')
    ]
    created_hits = [
        line for line in prefs_lines if line.startswith('user_pref("browser.profiles.created"')
    ]
    prefs_needed = store_hits != [store_pref] or created_hits != [created_pref]
    kept_prefs = [
        line
        for line in prefs_lines
        if not line.startswith('user_pref("toolkit.profiles.storeID"')
        and not line.startswith('user_pref("browser.profiles.created"')
    ]

    conn = sqlite3.connect(store_path)
    row = conn.execute("SELECT name FROM Profiles WHERE path = ?", (name,)).fetchone()
    sqlite_needed = row is None or row[0] != name
    sample = None
    if row is None:
        sample = conn.execute(
            "SELECT avatar, themeId, themeFg, themeBg FROM Profiles LIMIT 1"
        ).fetchone()
        if sample is None:
            problem("стор пуст - профиль не добавлен в панель")

    if not ini_needed and not sqlite_needed and not prefs_needed:
        sys.exit(0)

    for target in (ini_path, store_path):
        backup = target + ".pre-register"
        if os.path.exists(backup):
            problem(f"уже есть {backup}, разберись вручную")
    shutil.copy2(ini_path, ini_path + ".pre-register")
    shutil.copy2(store_path, store_path + ".pre-register")

    if ini_needed:
        new_block = [f"StoreID={store_id}"] + [
            line for line in ini_lines[block_start + 1:block_end] if not line.startswith("StoreID=")
        ]
        ini_lines = ini_lines[:block_start + 1] + new_block + ini_lines[block_end:]
        with open(ini_path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(ini_lines) + "\n")

    if prefs_needed:
        with open(prefs_path, "w", encoding="utf-8") as handle:
            for line in kept_prefs + [store_pref, created_pref]:
                handle.write(line + "\n")

    if sqlite_needed:
        if row is None:
            conn.execute(
                "INSERT INTO Profiles (path, name, avatar, themeId, themeFg, themeBg)"
                " VALUES (?, ?, ?, ?, ?, ?)",
                (name, name, *sample),
            )
        else:
            conn.execute("UPDATE Profiles SET name = ? WHERE path = ?", (name, name))
        conn.commit()
    conn.close()
except (OSError, sqlite3.Error) as error:
    problem(str(error))
PYEOF
    echo "firefox-profiles: $name: зарегистрирован в панели (StoreID=$STORE_ID)"
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
        register_profile "$name"
    done
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
        if [[ ! -f "$profile/cookies.sqlite" ]]; then
            echo "firefox-profiles: $name: нет cookies.sqlite в профиле" >&2
            failed=1
            continue
        fi
        if [[ ! -f "$profile/places.sqlite" ]]; then
            echo "firefox-profiles: $name: нет places.sqlite в профиле" >&2
            failed=1
            continue
        fi
        ensure_clean_sqlite "$profile/cookies.sqlite"
        ensure_clean_sqlite "$profile/places.sqlite"
        mkdir -p "$credentials_dir"
        cp "$profile/cookies.sqlite" "$credentials_dir/cookies.sqlite"
        chmod 600 "$credentials_dir/cookies.sqlite"
        cp "$profile/places.sqlite" "$credentials_dir/places.sqlite"
        chmod 600 "$credentials_dir/places.sqlite"
    done
    echo "firefox-profiles: изменения в ~/credentials - закоммить и запушь"
    [[ $failed -eq 0 ]] || exit 1
}

cmd_pull() {
    require_firefox_closed
    profile_names
    local failed=0
    local name profile credentials_dir
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
        if [[ ! -f "$credentials_dir/places.sqlite" ]]; then
            echo "firefox-profiles: $name: нет places.sqlite в $credentials_dir" >&2
            failed=1
            continue
        fi
        if is_git_crypt_locked "$credentials_dir/cookies.sqlite" || is_git_crypt_locked "$credentials_dir/places.sqlite"; then
            fail "credentials заперт: запусти scripts/setup-secrets.sh unlock"
        fi
        ensure_clean_sqlite "$profile/cookies.sqlite"
        ensure_clean_sqlite "$profile/places.sqlite"
        cp "$credentials_dir/cookies.sqlite" "$profile/cookies.sqlite"
        chmod 600 "$profile/cookies.sqlite"
        cp "$credentials_dir/places.sqlite" "$profile/places.sqlite"
        chmod 600 "$profile/places.sqlite"
        echo "firefox-profiles: $name: скопированы cookies.sqlite, places.sqlite"
        register_profile "$name"
    done
    [[ $failed -eq 0 ]] || exit 1
}

cmd_reset() {
    require_firefox_closed
    profile_names
    local ini="$PROFILES_ROOT/profiles.ini"
    local status=0
    find_store || status=$?
    local store_path=""
    if (( status == 0 )); then
        store_path="$STORE_FILE"
    elif (( status == 2 )); then
        echo "firefox-profiles: в Profile Groups несколько сторов - строки панели не удалены, разберись вручную" >&2
    fi
    local store_ok=""
    if [[ -n "$store_path" ]]; then
        if store_schema_ok "$store_path"; then
            store_ok=1
        else
            echo "firefox-profiles: стор несовместим (нужна таблица Profiles с колонками path,name,avatar,themeId,themeFg,themeBg) - строки панели не удалены" >&2
        fi
    fi
    if [[ -n "$store_ok" && ! -e "$store_path.pre-register" ]]; then
        cp "$store_path" "$store_path.pre-register"
    fi
    if [[ -f "$ini" ]]; then
        python3 - "$ini" "${PROFILE_NAMES[@]}" <<'PYEOF'
import sys

ini_path = sys.argv[1]
names = sys.argv[2:]

with open(ini_path, encoding="utf-8") as handle:
    lines = handle.read().splitlines()

headers = [i for i, line in enumerate(lines) if line.startswith("[")]
drop = set()
for wanted in names:
    try:
        name_index = lines.index(f"Name={wanted}")
    except ValueError:
        continue
    starts = [i for i in headers if i < name_index]
    if not starts:
        continue
    block_start = starts[-1]
    block_end = next((i for i in headers if i > block_start), len(lines))
    drop.update(range(block_start, block_end))

result = [line for i, line in enumerate(lines) if i not in drop]
if result != lines:
    with open(ini_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(result) + "\n")
PYEOF
    fi
    local name
    for name in "${PROFILE_NAMES[@]}"; do
        rm -rf "$PROFILES_ROOT/$name"
    done
    if [[ -n "$store_ok" ]]; then
        python3 - "$store_path" "${PROFILE_NAMES[@]}" <<'PYEOF'
import sqlite3
import sys

store_path = sys.argv[1]
names = sys.argv[2:]

conn = sqlite3.connect(store_path)
for wanted in names:
    conn.execute("DELETE FROM Profiles WHERE path = ?", (wanted,))
conn.commit()
conn.close()
PYEOF
    fi
    local -a backups=("$ini.pre-register")
    if [[ -n "$store_path" ]]; then
        backups+=("$store_path.pre-register")
    fi
    local backup
    for backup in "${backups[@]}"; do
        if [[ -e "$backup" ]]; then
            rm -f "$backup" 2>/dev/null || echo "firefox-profiles: не удалён $backup - разберись вручную" >&2
        fi
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
