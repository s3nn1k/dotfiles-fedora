#!/usr/bin/env bash
set -euo pipefail

focused_window_title() {
    swaymsg -t get_tree | jq -r 'first([.. | select(.type? == "con" and .focused? == true) | .name] | .[0] // "")'
}

title="$(focused_window_title)"
printf '%.80s\n' "$title"
