#!/usr/bin/env bash
set -euo pipefail

if version="$(curl -sf --max-time 2 http://127.0.0.1:9090/version | jq -r '.version // empty')" && [[ -n "$version" ]]; then
    jq -nc --arg version "$version" '{text: " mihomo", tooltip: ("mihomo " + $version), class: "up"}'
else
    jq -nc '{text: " mihomo", tooltip: "mihomo недоступен", class: "down"}'
fi
