#!/usr/bin/env bash
set -euo pipefail

names="$(bluetoothctl devices Connected 2>/dev/null | sed 's/^Device [0-9A-F:]* //' || true)"

if [[ -z "$names" ]]; then
    jq -nc '{text: "\uf0c1", tooltip: "bluetooth: нет подключений", class: "off"}'
else
    first="$(printf '%s' "$names" | head -n1 | cut -c1-16)"
    tooltip="bluetooth: $(printf '%s' "$names" | tr '\n' ' ')"
    jq -nc --arg text "\uf0c1 $first" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip, class: "on"}'
fi
