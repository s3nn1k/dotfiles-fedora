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

last_state=""
last_ns=0

print_state() {
    local state now_ns
    now_ns="$(date +%s%N)"
    (( now_ns - last_ns < 150000000 )) && return 0
    last_ns="$now_ns"
    state="$(layout_state)"
    if [[ "$state" != "$last_state" ]]; then
        last_state="$state"
        printf '%s\n' "$state"
    fi
}

print_state
swaymsg -m -t subscribe '["input"]' | while read -r _event; do
    print_state
done
