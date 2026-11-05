#!/usr/bin/env python3
import os
import shutil
import sqlite3
import sys
from typing import NamedTuple

FOUND_STORE = "found"
MISSING_STORE = "missing"
MULTIPLE_STORES = "multiple"
REGISTERED = "registered"
ALREADY_REGISTERED = "already"


class Store(NamedTuple):
    store_id: str
    path: str


class RegistrationProblem(Exception):
    pass


def warn(message):
    print(f"firefox-profiles: {message}", file=sys.stderr)


def usage():
    print("usage: firefox-register.py <profiles-root> register <имя...> | unregister <имя...>", file=sys.stderr)
    sys.exit(1)


def panel_ini_path(profiles_root):
    return os.path.join(profiles_root, "profiles.ini")


def ini_sections(ini_path):
    with open(ini_path, encoding="utf-8", errors="surrogateescape") as handle:
        lines = handle.read().splitlines()
    sections = []
    header = None
    body = []
    for line in lines:
        if line.startswith("["):
            if header is not None:
                sections.append((header, body))
            header = line
            body = []
        else:
            body.append(line)
    if header is not None:
        sections.append((header, body))
    return sections


def is_profile_header(header):
    return header.startswith("[Profile") and header.endswith("]") and header[8:-1].isdigit()


def ini_install_default_path(ini_path):
    for header, body in ini_sections(ini_path):
        if not header.startswith("[Install"):
            continue
        for line in body:
            key, _, value = line.partition("=")
            if key == "Default":
                return value
    return ""


def ini_store_id_for_path(ini_path, path):
    for header, body in ini_sections(ini_path):
        if not is_profile_header(header):
            continue
        block_path = ""
        store_id = ""
        for line in body:
            key, _, value = line.partition("=")
            if key == "Path":
                block_path = value
            elif key == "StoreID":
                store_id = value
        if block_path == path and store_id:
            return store_id
    return ""


def store_is_populated(store_path):
    try:
        connection = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
        rows = connection.execute("SELECT COUNT(*) FROM Profiles").fetchone()[0]
        connection.close()
    except sqlite3.Error:
        return False
    return rows >= 1


def populated_stores(groups_dir):
    stores = []
    if not os.path.isdir(groups_dir):
        return stores
    for entry in sorted(os.listdir(groups_dir)):
        if entry.startswith(".") or not entry.endswith(".sqlite"):
            continue
        candidate = os.path.join(groups_dir, entry)
        if os.path.isfile(candidate) and store_is_populated(candidate):
            stores.append(candidate)
    return stores


def find_store(profiles_root):
    groups_dir = os.path.join(profiles_root, "Profile Groups")
    ini_path = panel_ini_path(profiles_root)
    if os.path.isfile(ini_path):
        install_default = ini_install_default_path(ini_path)
        if install_default:
            store_id = ini_store_id_for_path(ini_path, install_default)
            default_store = os.path.join(groups_dir, store_id + ".sqlite") if store_id else ""
            if default_store and os.path.isfile(default_store) and store_is_populated(default_store):
                return FOUND_STORE, Store(store_id=store_id, path=default_store)
    candidates = populated_stores(groups_dir)
    if len(candidates) == 1:
        store_path = candidates[0]
        return FOUND_STORE, Store(
            store_id=os.path.basename(store_path).removesuffix(".sqlite"),
            path=store_path,
        )
    if len(candidates) > 1:
        return MULTIPLE_STORES, None
    return MISSING_STORE, None


def store_schema_ok(store_path):
    required = {"path", "name", "avatar", "themeId", "themeFg", "themeBg"}
    try:
        connection = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
        columns = {row[1] for row in connection.execute("PRAGMA table_info(Profiles)")}
        connection.close()
    except sqlite3.Error:
        return False
    return required <= columns


def ini_block_ranges(lines):
    starts = [i for i, line in enumerate(lines) if line.startswith("[")]
    for block_start in starts:
        if not is_profile_header(lines[block_start]):
            continue
        block_end = next((i for i in starts if i > block_start), len(lines))
        yield block_start, block_end


def ini_block(lines, wanted_name):
    for block_start, block_end in ini_block_ranges(lines):
        block_name = ""
        block_path_component = ""
        for line in lines[block_start + 1:block_end]:
            key, _, value = line.partition("=")
            if key == "Name":
                block_name = value
            elif key == "Path":
                block_path_component = path_last_component(value)
        if block_name == wanted_name or block_path_component == wanted_name:
            return block_start, block_end
    return None


def ini_profile_path(lines, wanted_name):
    block = ini_block(lines, wanted_name)
    if block is None:
        return None
    block_start, block_end = block
    for line in lines[block_start + 1:block_end]:
        key, _, value = line.partition("=")
        if key == "Path":
            return value
    return None


def register_one(name, store, profiles_root, backups_done):
    ini_path = panel_ini_path(profiles_root)
    store_id = store.store_id
    store_path = store.path
    with open(ini_path, encoding="utf-8", errors="surrogateescape") as handle:
        ini_lines = handle.read().splitlines()
    profile_block = ini_block(ini_lines, name)
    if profile_block is None:
        raise RegistrationProblem(f"в profiles.ini нет блока профиля {name}")
    block_start, block_end = profile_block
    profile_path = ini_profile_path(ini_lines, name)
    if profile_path is None:
        raise RegistrationProblem(f"в profiles.ini нет Path у профиля {name}")
    prefs_path = os.path.join(profiles_root, profile_path, "prefs.js")
    block_store_lines = [
        line for line in ini_lines[block_start + 1:block_end] if line.startswith("StoreID=")
    ]
    ini_needed = block_store_lines != [f"StoreID={store_id}"]

    store_pref = f'user_pref("toolkit.profiles.storeID", "{store_id}");'
    created_pref = 'user_pref("browser.profiles.created", true);'
    if os.path.isfile(prefs_path):
        with open(prefs_path, encoding="utf-8", errors="surrogateescape") as handle:
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
            "SELECT name FROM Profiles WHERE path = ?", (profile_path,)
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
            shutil.copy2(ini_path, ini_path + ".pre-register")
            shutil.copy2(store_path, store_path + ".pre-register")

        if ini_needed:
            new_block = [f"StoreID={store_id}"] + [
                line for line in ini_lines[block_start + 1:block_end] if not line.startswith("StoreID=")
            ]
            ini_lines = ini_lines[:block_start + 1] + new_block + ini_lines[block_end:]
            with open(ini_path, "w", encoding="utf-8", errors="surrogateescape") as handle:
                handle.write("\n".join(ini_lines) + "\n")

        if prefs_needed:
            with open(prefs_path, "w", encoding="utf-8", errors="surrogateescape") as handle:
                for line in kept_prefs + [store_pref, created_pref]:
                    handle.write(line + "\n")

        if sqlite_needed:
            if existing_row is None:
                connection.execute(
                    "INSERT INTO Profiles (path, name, avatar, themeId, themeFg, themeBg)"
                    " VALUES (?, ?, ?, ?, ?, ?)",
                    (profile_path, name, *sample_row),
                )
            else:
                connection.execute(
                    "UPDATE Profiles SET name = ? WHERE path = ?", (name, profile_path)
                )
            connection.commit()
    finally:
        connection.close()
    return REGISTERED


def register(names, profiles_root):
    try:
        state, store = find_store(profiles_root)
        schema_ok = state == FOUND_STORE and store_schema_ok(store.path)
    except (OSError, sqlite3.Error) as error:
        warn(str(error))
        sys.exit(1)
    if state == MULTIPLE_STORES:
        for name in names:
            warn(f"{name}: в Profile Groups несколько сторов - разберись вручную")
        sys.exit(1)
    if state == MISSING_STORE:
        for name in names:
            warn(f"{name}: панель профилей не инициализирована - запусти Firefox и повтори init/pull позже")
        sys.exit(1)
    if not schema_ok:
        for name in names:
            warn(f"{name}: стор несовместим (нужна таблица Profiles с колонками path,name,avatar,themeId,themeFg,themeBg) - пропущен")
        sys.exit(1)
    failed = False
    backups_done = False
    for name in names:
        try:
            outcome = register_one(name, store, profiles_root, backups_done)
        except (RegistrationProblem, OSError, sqlite3.Error) as error:
            warn(f"{name}: {error}")
            failed = True
            continue
        if outcome == REGISTERED:
            backups_done = True
            print(f"firefox-profiles: {name}: зарегистрирован в панели (StoreID={store.store_id})")
        else:
            print(f"firefox-profiles: {name}: уже зарегистрирован в панели")
    if failed:
        sys.exit(1)


def path_last_component(path):
    return path.rsplit("/", 1)[-1]


def drop_ini_blocks(ini_path, names):
    with open(ini_path, encoding="utf-8", errors="surrogateescape") as handle:
        lines = handle.read().splitlines()
    wanted = set(names)
    drop = set()
    for block_start, block_end in ini_block_ranges(lines):
        block_name = ""
        block_path_component = ""
        for line in lines[block_start + 1:block_end]:
            key, _, value = line.partition("=")
            if key == "Name":
                block_name = value
            elif key == "Path":
                block_path_component = path_last_component(value)
        if block_name in wanted or block_path_component in wanted:
            drop.update(range(block_start, block_end))
    result = [line for i, line in enumerate(lines) if i not in drop]
    if result != lines:
        with open(ini_path, "w", encoding="utf-8", errors="surrogateescape") as handle:
            handle.write("\n".join(result) + "\n")


def unregister(names, profiles_root):
    state, store = find_store(profiles_root)
    store_path = store.path if store else ""
    store_backup_path = ""
    rows_deletable = False
    if state == MULTIPLE_STORES:
        warn("в Profile Groups несколько сторов - строки панели не удалены, разберись вручную")
        sys.exit(1)
    elif state == FOUND_STORE:
        store_backup_path = store_path
        if store_schema_ok(store_path):
            rows_deletable = True
            if not os.path.exists(store_path + ".pre-register"):
                shutil.copy2(store_path, store_path + ".pre-register")
        else:
            warn("стор несовместим (нужна таблица Profiles с колонками path,name,avatar,themeId,themeFg,themeBg) - строки панели не удалены")
            sys.exit(1)
    ini_path = panel_ini_path(profiles_root)
    store_row_paths = []
    if rows_deletable:
        if not os.path.isfile(ini_path):
            warn("profiles.ini отсутствует - стор-строки не резолвятся и не удалены")
        else:
            with open(ini_path, encoding="utf-8", errors="surrogateescape") as handle:
                ini_lines = handle.read().splitlines()
            for name in names:
                profile_path = ini_profile_path(ini_lines, name)
                if profile_path is None:
                    warn(f"{name}: в profiles.ini нет блока или Path - стор-строка не удалена")
                    sys.exit(1)
                store_row_paths.append(profile_path)
    if os.path.isfile(ini_path):
        drop_ini_blocks(ini_path, names)
    if rows_deletable and store_row_paths:
        connection = sqlite3.connect(store_path)
        try:
            placeholders = ",".join("?" * len(store_row_paths))
            connection.execute(f"DELETE FROM Profiles WHERE path IN ({placeholders})", store_row_paths)
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
    if len(sys.argv) < 4:
        usage()
    profiles_root, command, names = sys.argv[1], sys.argv[2], sys.argv[3:]
    if command == "register":
        register(names, profiles_root)
    elif command == "unregister":
        unregister(names, profiles_root)
    else:
        usage()


if __name__ == "__main__":
    main()
