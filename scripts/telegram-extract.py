#!/usr/bin/env python3
import posixpath
import sys
import tarfile

archive_path, extraction_directory = sys.argv[1:]


def fail(message):
    raise SystemExit(f"bootstrap: {message}")


with tarfile.open(archive_path, "r:*") as archive:
    members = archive.getmembers()
    seen_paths = set()
    root_member = None
    binary_member = None

    for member in members:
        name = member.name
        if not name or "\x00" in name or "\\" in name or name.startswith("/"):
            fail("архив содержит небезопасный путь")
        normalized_name = posixpath.normpath(name)
        if normalized_name != name.rstrip("/") or normalized_name == "..":
            fail("архив содержит путь с обходом каталогов")
        if normalized_name != "Telegram" and not normalized_name.startswith("Telegram/"):
            fail("архив содержит путь вне Telegram/")
        if normalized_name in seen_paths:
            fail("архив содержит повторяющийся путь")
        seen_paths.add(normalized_name)

        if member.issym() or member.islnk() or member.isdev():
            fail("архив содержит ссылку или специальный файл")
        if not (member.isdir() or member.isreg()):
            fail("архив содержит неподдерживаемый тип файла")

        if normalized_name == "Telegram":
            if root_member is not None or not member.isdir():
                fail("архив не содержит ожидаемый корень Telegram/")
            root_member = member
        if normalized_name == "Telegram/Telegram":
            if binary_member is not None or not member.isreg() or not member.mode & 0o111:
                fail("архив не содержит исполняемый файл Telegram")
            binary_member = member

    if root_member is None or binary_member is None:
        fail("архив не содержит ожидаемую установку Telegram")

    try:
        archive.extractall(extraction_directory, filter="data")
    except TypeError:
        archive.extractall(extraction_directory)
