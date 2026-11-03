#!/usr/bin/env python3
import os
import shutil
import sqlite3
import sys

PROFILES_ROOT = os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config"),
    "mozilla",
    "firefox",
)
FOUND_STORE = "found"
MISSING_STORE = "missing"
MULTIPLE_STORES = "multiple"
REGISTERED = "registered"
ALREADY_REGISTERED = "already"


class RegistrationProblem(Exception):
    pass


def warn(message):
    print(f"firefox-profiles: {message}", file=sys.stderr)


def usage():
    print("usage: firefox-register.py register <имя...> | unregister <имя...>", file=sys.stderr)
    sys.exit(1)


def panel_ini_path():
    return os.path.join(PROFILES_ROOT, "profiles.ini")


def ini_default_store_id(ini_path):
    store_id = ""
    default = False
    with open(ini_path, encoding="utf-8") as handle:
        for line in handle.read().splitlines():
            if line.startswith("["):
                if default and store_id:
                    return store_id
                default = False
                store_id = ""
                continue
            key, _, value = line.partition("=")
            if key == "StoreID":
                store_id = value
            elif key == "Default" and value == "1":
                default = True
    return store_id if default else ""


def find_store():
    groups_dir = os.path.join(PROFILES_ROOT, "Profile Groups")
    ini_path = panel_ini_path()
    store_id = ini_default_store_id(ini_path) if os.path.isfile(ini_path) else ""
    default_store = os.path.join(groups_dir, store_id + ".sqlite") if store_id else ""
    if default_store and os.path.isfile(default_store):
        return FOUND_STORE, store_id, default_store
    stores = []
    if os.path.isdir(groups_dir):
        for entry in sorted(os.listdir(groups_dir)):
            if entry.startswith(".") or not entry.endswith(".sqlite"):
                continue
            candidate = os.path.join(groups_dir, entry)
            if os.path.isfile(candidate):
                stores.append(candidate)
    if len(stores) == 1:
        store_path = stores[0]
        return FOUND_STORE, os.path.basename(store_path).removesuffix(".sqlite"), store_path
    if len(stores) > 1:
        return MULTIPLE_STORES, "", ""
    return MISSING_STORE, "", ""


def store_schema_ok(store_path):
    required = {"path", "name", "avatar", "themeId", "themeFg", "themeBg"}
    try:
        connection = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
        columns = {row[1] for row in connection.execute("PRAGMA table_info(Profiles)")}
        connection.close()
    except sqlite3.Error:
        return False
    return required <= columns


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


def register_one(name, store_id, store_path, backups_done):
    ini_path = panel_ini_path()
    prefs_path = os.path.join(PROFILES_ROOT, name, "prefs.js")
    with open(ini_path, encoding="utf-8") as handle:
        ini_lines = handle.read().splitlines()
    profile_block = ini_block(ini_lines, name)
    if profile_block is None:
        raise RegistrationProblem(f"в profiles.ini нет блока профиля {name}")
    block_start, block_end = profile_block
    block_store_lines = [
        line for line in ini_lines[block_start + 1:block_end] if line.startswith("StoreID=")
    ]
    ini_needed = block_store_lines != [f"StoreID={store_id}"]

    store_pref = f'user_pref("toolkit.profiles.storeID", "{store_id}");'
    created_pref = 'user_pref("browser.profiles.created", true);'
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

    connection = sqlite3.connect(store_path)
    try:
        existing_row = connection.execute(
            "SELECT name FROM Profiles WHERE path = ?", (name,)
        ).fetchone()
        sqlite_needed = existing_row is None or existing_row[0] != name
        sample_row = None
        if existing_row is None:
            sample_row = connection.execute(
                "SELECT avatar, themeId, themeFg, themeBg FROM Profiles LIMIT 1"
            ).fetchone()
            if sample_row is None:
                raise RegistrationProblem("стор пуст - профиль не добавлен в панель")

        if not ini_needed and not sqlite_needed and not prefs_needed:
            return ALREADY_REGISTERED

        if not backups_done:
            for target in (ini_path, store_path):
                backup = target + ".pre-register"
                if os.path.exists(backup):
                    raise RegistrationProblem(f"уже есть {backup}, разберись вручную")
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
            if existing_row is None:
                connection.execute(
                    "INSERT INTO Profiles (path, name, avatar, themeId, themeFg, themeBg)"
                    " VALUES (?, ?, ?, ?, ?, ?)",
                    (name, name, *sample_row),
                )
            else:
                connection.execute(
                    "UPDATE Profiles SET name = ? WHERE path = ?", (name, name)
                )
            connection.commit()
    finally:
        connection.close()
    return REGISTERED


def register(names):
    try:
        state, store_id, store_path = find_store()
        schema_ok = state == FOUND_STORE and store_schema_ok(store_path)
    except (OSError, sqlite3.Error) as error:
        warn(str(error))
        return
    if state == MULTIPLE_STORES:
        for name in names:
            warn(f"{name}: в Profile Groups несколько сторов - разберись вручную")
        return
    if state == MISSING_STORE:
        for name in names:
            warn(f"{name}: панель профилей появится после первого запуска Firefox; повтори init/pull позже")
        return
    if not schema_ok:
        for name in names:
            warn(f"{name}: стор несовместим (нужна таблица Profiles с колонками path,name,avatar,themeId,themeFg,themeBg) - пропущен")
        return
    backups_done = False
    for name in names:
        try:
            outcome = register_one(name, store_id, store_path, backups_done)
        except (RegistrationProblem, OSError, sqlite3.Error) as error:
            warn(f"{name}: {error}")
            continue
        if outcome == REGISTERED:
            backups_done = True
            print(f"firefox-profiles: {name}: зарегистрирован в панели (StoreID={store_id})")
        else:
            print(f"firefox-profiles: {name}: уже зарегистрирован в панели")


def drop_ini_blocks(ini_path, names):
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


def unregister(names):
    state, _, store_path = find_store()
    store_backup_path = ""
    rows_deletable = False
    if state == MULTIPLE_STORES:
        warn("в Profile Groups несколько сторов - строки панели не удалены, разберись вручную")
    elif state == FOUND_STORE:
        store_backup_path = store_path
        if store_schema_ok(store_path):
            rows_deletable = True
            if not os.path.exists(store_path + ".pre-register"):
                shutil.copy2(store_path, store_path + ".pre-register")
        else:
            warn("стор несовместим (нужна таблица Profiles с колонками path,name,avatar,themeId,themeFg,themeBg) - строки панели не удалены")
    ini_path = panel_ini_path()
    if os.path.isfile(ini_path):
        drop_ini_blocks(ini_path, names)
    if rows_deletable:
        connection = sqlite3.connect(store_path)
        try:
            placeholders = ",".join("?" * len(names))
            connection.execute(f"DELETE FROM Profiles WHERE path IN ({placeholders})", names)
            connection.commit()
        finally:
            connection.close()
    backups = [ini_path + ".pre-register"]
    if store_backup_path:
        backups.append(store_backup_path + ".pre-register")
    for backup in backups:
        if os.path.exists(backup):
            try:
                os.remove(backup)
            except OSError:
                warn(f"не удалён {backup} - разберись вручную")


def main():
    if len(sys.argv) < 3:
        usage()
    command, names = sys.argv[1], sys.argv[2:]
    if command == "register":
        register(names)
    elif command == "unregister":
        unregister(names)
    else:
        usage()


if __name__ == "__main__":
    main()
