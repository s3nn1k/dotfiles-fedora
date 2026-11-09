#!/usr/bin/env python3
"""Собирает policies.json для LibreWolf: пакетная база + оверлей репо + стили Sidebery.

Managed storage (политика 3rdparty) приоритетнее локального хранилища расширения,
поэтому sidebarCSS из репо всегда побеждает правки в Settings -> Styles editor.
Вызов: merge-policies.py <overlay.json> <sidebery.css> <base.json> > merged.json
"""
import json
import pathlib
import sys


def deep_merge(base, extra):
    result = dict(base)
    for key, value in extra.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def main():
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 1
    overlay = json.loads(pathlib.Path(sys.argv[1]).read_text())
    css = pathlib.Path(sys.argv[2]).read_text()
    base = json.loads(pathlib.Path(sys.argv[3]).read_text()) if pathlib.Path(sys.argv[3]).exists() else {"policies": {}}

    policies = deep_merge(base["policies"], overlay["policies"])
    third_party = policies.setdefault("3rdparty", {}).setdefault("Extensions", {})
    for extension_id in overlay.get("policies", {}).get("3rdparty", {}).get("Extensions", {}):
        third_party[extension_id] = {"sidebarCSS": css}

    json.dump({"policies": policies}, sys.stdout, indent=4)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
