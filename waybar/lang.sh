#!/usr/bin/env bash
set -euo pipefail

layout_state() {
    swaymsg -t get_inputs | jq -c '
        [.[] | select(.type == "keyboard")] as $keyboards
        | (($keyboards | map(select((.identifier | test("keyd|xremap|virtual")) | not)) | .[0]) // $keyboards[0])
        | (.xkb_active_layout_name // "") as $long
        | ({"English (US)": "us", "Russian": "ru"}[$long] // $long) as $short
        | {text: $short, tooltip: $long, class: ("lang-" + $short)}
    '
}

layout_state
swaymsg -m -t subscribe '["input"]' | while read -r _event; do
    layout_state
done
