#!/usr/bin/env python3
import sys


def read_lines(ini_path):
    try:
        with open(ini_path, encoding="utf-8", errors="surrogateescape") as handle:
            return handle.read().splitlines()
    except FileNotFoundError:
        return []


def is_profile_header(header):
    return header.startswith("[Profile") and header.endswith("]") and header[8:-1].isdigit()


def path_last_component(path):
    return path.rsplit("/", 1)[-1]


def ini_sections(ini_path):
    sections = []
    header = None
    body = []
    for line in read_lines(ini_path):
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


def ini_has_profile_block(ini_path, wanted_name):
    return ini_block(read_lines(ini_path), wanted_name) is not None


def ini_resolve_path(ini_path, wanted_name):
    return ini_profile_path(read_lines(ini_path), wanted_name)


def drop_ini_blocks(ini_path, names):
    lines = read_lines(ini_path)
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


def emit_blocks(ini_path):
    incomplete = 0
    for header, body in ini_sections(ini_path):
        if not is_profile_header(header):
            continue
        block_name = ""
        block_path = ""
        for line in body:
            key, _, value = line.partition("=")
            if key == "Name":
                block_name = value
            elif key == "Path":
                block_path = value
        if block_name and block_path:
            print(f"{block_name}\t{block_path}")
        else:
            incomplete += 1
    if incomplete:
        print(f"firefox-ini: {incomplete} [Profile]-блоков без Name/Path - их каталоги не тронуты", file=sys.stderr)


def usage():
    print("usage: firefox_ini.py resolve <ini> <name> | has <ini> <name> | blocks <ini>", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) < 3:
        usage()
    command, ini_path = sys.argv[1], sys.argv[2]
    if command == "resolve" and len(sys.argv) == 4:
        print(ini_resolve_path(ini_path, sys.argv[3]) or "")
    elif command == "has" and len(sys.argv) == 4:
        sys.exit(0 if ini_has_profile_block(ini_path, sys.argv[3]) else 1)
    elif command == "blocks" and len(sys.argv) == 3:
        emit_blocks(ini_path)
    else:
        usage()


if __name__ == "__main__":
    main()
