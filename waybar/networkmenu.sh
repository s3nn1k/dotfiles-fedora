#!/usr/bin/env bash
set -euo pipefail

lock=/run/user/$(id -u)/networkmanager-dmenu.lock

if [[ -f "$lock" ]] && kill -0 "$(cat "$lock")" 2>/dev/null; then
    exit 0
fi

printf '%s\n' $$ > "$lock"
exec "$HOME/.local/bin/networkmanager_dmenu"
