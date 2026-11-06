#!/usr/bin/env python3
import json
import os
import re
import secrets
import shutil
import sqlite3
import stat
import sys
from typing import NamedTuple

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from firefox_cityhash import install_hash
from firefox_ini import (
    drop_ini_blocks,
    ini_block,
    ini_install_default_path,
    ini_profile_path,
    ini_resolve_path,
    ini_store_id_for_path,
    read_lines,
)

FOUND_STORE = "found"
MISSING_STORE = "missing"
MULTIPLE_STORES = "multiple"
REGISTERED = "registered"
ALREADY_REGISTERED = "already"


class Store(NamedTuple):
    store_id: str
    path: str


class RegistrationContext(NamedTuple):
    profiles_root: str
    panel_config_dir: str


class RegistrationProblem(Exception):
    pass


class PanelDefaults(NamedTuple):
    avatar: str
    theme_id: str
    theme_fg: str
    theme_bg: str


PANEL_DEFAULTS = PanelDefaults(
    avatar="book",
    theme_id="default-theme@mozilla.org",
    theme_fg="rgb(255,255,255)",
    theme_bg="rgb(28,27,34)",
)

PANEL_AVATARS = ("book", "briefcase", "flower", "heart", "shopping", "star")

DEFAULT_PANEL_CONFIG_DIR = "~/credentials/firefox"

STORE_ID_ATTEMPTS = 5

PANEL_JSON_MAX_BYTES = 64 * 1024

INSTALL_HEADER_RE = re.compile(r"^\[Install([0-9A-F]{1,16})\]$")

HASH_HEADER_RE = re.compile(r"^\[([0-9A-F]{1,16})\]$")


def panel_defaults(name, panel_config_dir):
    panel_path = os.path.join(panel_config_dir, name, "panel.json")
    try:
        panel_stat = os.stat(panel_path)
    except FileNotFoundError:
        return PANEL_DEFAULTS
    except OSError:
        warn(f"{panel_path}: panel.json не читается - аватар по умолчанию")
        return PANEL_DEFAULTS
    if not stat.S_ISREG(panel_stat.st_mode) or panel_stat.st_size > PANEL_JSON_MAX_BYTES:
        warn(f"{panel_path}: panel.json не читается - аватар по умолчанию")
        return PANEL_DEFAULTS
    try:
        with open(panel_path, encoding="utf-8") as handle:
            panel = json.load(handle)
    except FileNotFoundError:
        return PANEL_DEFAULTS
    except (OSError, ValueError):
        warn(f"{panel_path}: panel.json не читается - аватар по умолчанию")
        return PANEL_DEFAULTS
    if not isinstance(panel, dict):
        warn(f"{panel_path}: panel.json не JSON-объект - аватар по умолчанию")
        return PANEL_DEFAULTS
    avatar = panel.get("avatar", PANEL_DEFAULTS.avatar)
    if avatar not in PANEL_AVATARS:
        warn(f"{panel_path}: неизвестный аватар {avatar} - аватар по умолчанию")
        avatar = PANEL_DEFAULTS.avatar
    return PANEL_DEFAULTS._replace(avatar=avatar)


def warn(message):
    print(f"firefox-profiles: {message}", file=sys.stderr)


def usage():
    print("usage: firefox-register.py [--panel-config-dir <dir>] <profiles-root> register <имя...> | unregister <имя...>", file=sys.stderr)
    sys.exit(1)


def panel_ini_path(profiles_root):
    return os.path.join(profiles_root, "profiles.ini")


def valid_stores(groups_dir):
    stores = []
    if not os.path.isdir(groups_dir):
        return stores
    for entry in sorted(os.listdir(groups_dir)):
        if entry.startswith(".") or not entry.endswith(".sqlite"):
            continue
        candidate = os.path.join(groups_dir, entry)
        if os.path.isfile(candidate) and store_schema_ok(candidate):
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
            if default_store and os.path.isfile(default_store) and store_schema_ok(default_store):
                return FOUND_STORE, Store(store_id=store_id, path=default_store)
    candidates = valid_stores(groups_dir)
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
    except sqlite3.OperationalError as error:
        if "locked" in str(error):
            raise RegistrationProblem(f"стор занят другим процессом ({store_path}) - закрой держателя")
        return False
    except sqlite3.Error:
        return False
    return required <= columns


def create_store(profiles_root):
    groups_dir = os.path.join(profiles_root, "Profile Groups")
    os.makedirs(groups_dir, exist_ok=True)
    for _ in range(STORE_ID_ATTEMPTS):
        store_id = secrets.token_hex(4)
        store_path = os.path.join(groups_dir, store_id + ".sqlite")
        try:
            os.close(os.open(store_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
        except FileExistsError:
            continue
        break
    else:
        raise RegistrationProblem(
            f"в {groups_dir} не найдено свободного имени стора после {STORE_ID_ATTEMPTS} попыток"
        )
    try:
        connection = sqlite3.connect(store_path)
        try:
            connection.execute(
                "CREATE TABLE Profiles ("
                "id INTEGER NOT NULL PRIMARY KEY, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL,"
                " avatar TEXT NOT NULL, themeId TEXT NOT NULL, themeFg TEXT NOT NULL, themeBg TEXT NOT NULL)"
            )
            connection.commit()
        finally:
            connection.close()
    except (OSError, sqlite3.Error):
        for leftover in (store_path, store_path + ".pre-register"):
            try:
                os.remove(leftover)
            except OSError:
                pass
        raise
    os.chmod(store_path, 0o600)
    print(f"firefox-profiles: создан стор панели (StoreID={store_id})")
    return Store(store_id=store_id, path=store_path)


def backup_store(store_path, backup_path):
    source = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
    try:
        destination = sqlite3.connect(backup_path)
        try:
            source.backup(destination)
        finally:
            destination.close()
    finally:
        source.close()


def prepare_backups(ini_path, store_path):
    if not os.path.exists(ini_path + ".pre-register"):
        shutil.copy2(ini_path, ini_path + ".pre-register")
    if not os.path.exists(store_path + ".pre-register"):
        backup_store(store_path, store_path + ".pre-register")


def install_directory():
    executable = shutil.which("firefox")
    if not executable:
        return ""
    install_dir = os.path.dirname(os.path.realpath(executable))
    if install_dir in ("/usr/bin", "/bin", "/usr/sbin"):
        install_dir = ""
        for lib_dir in ("/usr/lib64", "/usr/lib"):
            if os.path.isfile(os.path.join(lib_dir, "firefox", "firefox")):
                install_dir = os.path.join(lib_dir, "firefox")
                break
    if not install_dir or not os.path.isfile(os.path.join(install_dir, "application.ini")):
        return ""
    return install_dir


def ini_section_hashes(ini_path, header_re):
    hashes = set()
    for line in read_lines(ini_path):
        match = header_re.match(line)
        if match:
            hashes.add(match.group(1))
    return hashes


def ini_section_body(ini_path, header):
    try:
        with open(ini_path, encoding="utf-8", errors="surrogateescape") as handle:
            lines = handle.read().splitlines()
    except FileNotFoundError:
        return []
    starts = [i for i, line in enumerate(lines) if line.startswith("[")]
    for i in starts:
        if lines[i] == header:
            return lines[i + 1:next((j for j in starts if j > i), len(lines))]
    return None


def ini_entry_value(ini_path, header, key):
    body = ini_section_body(ini_path, header)
    if body is None:
        return None
    for line in body:
        line_key, _, value = line.partition("=")
        if line_key == key:
            return value
    return None


def ensure_ini_section(ini_path, header, entries):
    try:
        with open(ini_path, encoding="utf-8", errors="surrogateescape") as handle:
            lines = handle.read().splitlines()
    except FileNotFoundError:
        lines = []
    entry_keys = {entry.split("=", 1)[0] for entry in entries}
    starts = [i for i, line in enumerate(lines) if line.startswith("[")]
    for i in starts:
        if lines[i] != header:
            continue
        block_end = next((j for j in starts if j > i), len(lines))
        block = lines[i + 1:block_end]
        if all(entry in block for entry in entries):
            return False
        kept = [line for line in block if line.split("=", 1)[0] not in entry_keys]
        lines[i + 1:block_end] = kept + entries
        break
    else:
        if lines:
            lines.append("")
        lines.extend([header] + entries)
    with open(ini_path, encoding="utf-8", errors="surrogateescape", mode="w") as handle:
        handle.write("\n".join(lines) + "\n")
    return True


def ensure_install_binding(names, profiles_root, store):
    ini_path = panel_ini_path(profiles_root)
    first_path = ini_resolve_path(ini_path, names[0])
    if not first_path:
        warn(f"{names[0]}: в profiles.ini нет Path - install-привязка не записана")
        return False
    connection = sqlite3.connect(f"file:{store.path}?mode=ro", uri=True)
    try:
        registered_paths = {row[0] for row in connection.execute("SELECT path FROM Profiles")}
    finally:
        connection.close()

    def section_entries(path, header):
        current = ini_entry_value(path, header, "Default")
        if current is not None and current in registered_paths:
            return ["Locked=1"]
        return [f"Default={first_path}", "Locked=1"]

    install_dir = install_directory()
    hash_value = install_hash(install_dir) if install_dir else ""
    if hash_value:
        changed = ensure_ini_section(ini_path, f"[Install{hash_value}]", section_entries(ini_path, f"[Install{hash_value}]"))
        installs_path = os.path.join(profiles_root, "installs.ini")
        if ensure_ini_section(installs_path, f"[{hash_value}]", section_entries(installs_path, f"[{hash_value}]")):
            changed = True
        if changed:
            print(f"firefox-profiles: install-привязка {first_path} записана (Install{hash_value})")
        return True
    ini_hashes = ini_section_hashes(ini_path, INSTALL_HEADER_RE)
    installs_hashes = ini_section_hashes(os.path.join(profiles_root, "installs.ini"), HASH_HEADER_RE)
    known = ini_hashes | installs_hashes
    if len(known) != 1:
        return False
    hash_value = next(iter(known))
    changed = False
    if hash_value in ini_hashes and ensure_ini_section(ini_path, f"[Install{hash_value}]", section_entries(ini_path, f"[Install{hash_value}]")):
        changed = True
    installs_path = os.path.join(profiles_root, "installs.ini")
    if hash_value in installs_hashes and ensure_ini_section(
        installs_path, f"[{hash_value}]", section_entries(installs_path, f"[{hash_value}]")
    ):
        changed = True
    if changed:
        print(f"firefox-profiles: install-привязка {first_path} записана в секцию {hash_value}")
    return True


def register_one(name, store, context):
    profiles_root = context.profiles_root
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

        if not ini_needed and not sqlite_needed and not prefs_needed:
            return ALREADY_REGISTERED

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
                    (profile_path, name, *panel_defaults(name, context.panel_config_dir)),
                )
            else:
                connection.execute(
                    "UPDATE Profiles SET name = ? WHERE path = ?", (name, profile_path)
                )
            connection.commit()
    finally:
        connection.close()
    return REGISTERED


def register(names, profiles_root, panel_config_dir):
    try:
        state, store = find_store(profiles_root)
        while state == MISSING_STORE:
            ours = create_store(profiles_root)
            state, store = find_store(profiles_root)
            if store is not None and store.path == ours.path:
                break
            os.remove(ours.path)
            state, store = find_store(profiles_root)
        if state == MULTIPLE_STORES:
            for name in names:
                warn(f"{name}: в Profile Groups несколько сторов - разберись вручную")
            sys.exit(1)
        prepare_backups(panel_ini_path(profiles_root), store.path)
    except (RegistrationProblem, OSError, sqlite3.Error) as error:
        warn(str(error))
        sys.exit(1)
    failed = False
    context = RegistrationContext(profiles_root=profiles_root, panel_config_dir=panel_config_dir)
    for name in names:
        try:
            outcome = register_one(name, store, context)
        except (RegistrationProblem, OSError, sqlite3.Error) as error:
            warn(f"{name}: {error}")
            failed = True
            continue
        if outcome == REGISTERED:
            print(f"firefox-profiles: {name}: зарегистрирован в панели (StoreID={store.store_id})")
        else:
            print(f"firefox-profiles: {name}: уже зарегистрирован в панели")
    if failed:
        sys.exit(1)
    try:
        bound = ensure_install_binding(names, profiles_root, store)
    except (RegistrationProblem, OSError) as error:
        warn(str(error))
        bound = False
    if not bound:
        first_slug = names[0]
        warn(
            f"install-привязка не обеспечена - запусти и штатно закрой Firefox (firefox -P {first_slug}), "
            "затем повтори init - Firefox сам запишет привязку"
        )


def unregister(names, profiles_root):
    try:
        state, store = find_store(profiles_root)
    except RegistrationProblem as error:
        warn(str(error))
        sys.exit(1)
    store_path = store.path if store else ""
    store_backup_path = ""
    rows_deletable = False
    if state == MULTIPLE_STORES:
        warn("в Profile Groups несколько сторов - строки панели не удалены, разберись вручную")
        sys.exit(1)
    elif state == FOUND_STORE:
        store_backup_path = store_path
        try:
            schema_ok = store_schema_ok(store_path)
        except RegistrationProblem as error:
            warn(str(error))
            sys.exit(1)
        if schema_ok:
            rows_deletable = True
            if not os.path.exists(store_path + ".pre-register"):
                backup_store(store_path, store_path + ".pre-register")
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
    args = sys.argv[1:]
    panel_config_dir = os.path.expanduser(DEFAULT_PANEL_CONFIG_DIR)
    if args[:1] == ["--panel-config-dir"]:
        if len(args) < 2:
            usage()
        panel_config_dir = args[1]
        args = args[2:]
    if len(args) < 3:
        usage()
    profiles_root, command, names = args[0], args[1], args[2:]
    if command == "register":
        register(names, profiles_root, panel_config_dir)
    elif command == "unregister":
        unregister(names, profiles_root)
    else:
        usage()


if __name__ == "__main__":
    main()
