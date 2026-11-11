#!/usr/bin/env bash
set -euo pipefail

active_layout_name() {
    swaymsg -t get_inputs | jq -r '[.[] | select(.type == "keyboard")][0].xkb_active_layout_name // ""'
}

layout_short() {
    case "$1" in
        "English (US)") echo "us" ;;
        "Russian") echo "ru" ;;
        *) echo "$1" ;;
    esac
}

long_name="$(active_layout_name)"
short_name="$(layout_short "$long_name")"
jq -nc --arg text "$short_name" --arg tooltip "$long_name" \
    '{text: $text, tooltip: $tooltip, class: ("lang-" + $text)}'
