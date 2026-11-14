#!/usr/bin/env bash
set -euo pipefail

if version="$(curl -sf --max-time 2 http://127.0.0.1:9090/version | jq -r '.version // empty')" && [[ -n "$version" ]]; then
    node="$(curl -sf --max-time 2 http://127.0.0.1:9090/proxies | jq -r '.proxies.PROXY.now // ""')"
    jq -nc --arg version "$version" --arg node "$node" '{text: "\uf132", tooltip: ("mihomo " + $version + " · сервер: " + $node), class: "up"}'
else
    jq -nc '{text: "\uf132", tooltip: "mihomo недоступен", class: "down"}'
fi
