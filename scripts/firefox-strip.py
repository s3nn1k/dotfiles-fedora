#!/usr/bin/env python3
import os
import sqlite3
import sys


def usage():
    print("usage: firefox-strip.py <имя-профиля> <путь-к-places-копии>", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 3:
        usage()
    name, database = sys.argv[1:3]
    try:
        connection = sqlite3.connect(database)
        before = os.path.getsize(database)
        connection.execute("DELETE FROM moz_inputhistory")
        connection.execute("DELETE FROM moz_historyvisits")
        connection.execute(
            "DELETE FROM moz_places WHERE id NOT IN (SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL)"
        )
        connection.commit()
        connection.execute("VACUUM")
        connection.close()
        for suffix in ("-wal", "-shm"):
            if os.path.exists(database + suffix):
                os.remove(database + suffix)
        after = os.path.getsize(database)
    except (OSError, sqlite3.Error) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    print(
        f"firefox-profiles: {name}: places.sqlite без истории:"
        f" {before / 1048576:.2f}МБ -> {after / 1048576:.2f}МБ"
    )


if __name__ == "__main__":
    main()
