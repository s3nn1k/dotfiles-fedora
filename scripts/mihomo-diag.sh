#!/usr/bin/env bash
# Сбор диагностики mihomo в один файл с маскировкой секретов; результат в stdout и /tmp/mihomo-diag.txt.
set -uo pipefail

output="${1:-/tmp/mihomo-diag.txt}"

section(){ printf '\n===== %s =====\n' "$1"; }

collect(){
    section "service status"
    systemctl is-active mihomo; systemctl show mihomo -p MainPID,ExecStart --no-pager
    section "version"
    /usr/local/bin/mihomo -v 2>&1 | head -3
    section "tun interface"
    ip -br addr show Meta; ip link show Meta 2>/dev/null | head -3
    section "route to fake-ip"
    ip route get 198.18.0.9
    section "policy rules"
    ip rule
    section "routes mentioning tun or fake range"
    ip route show table all | grep -iE 'meta|mihomo|198\.18' || echo none
    section "nftables"
    sudo nft list ruleset 2>&1 | head -60
    section "journal tail"
    journalctl -u mihomo --no-pager | tail -40
    section "dns"
    resolvectl query google.com 2>&1 | head -5
    section "curl via mixed-port"
    curl -x http://127.0.0.1:7890 -s -m 8 -o /dev/null -w '%{http_code}\n' https://www.google.com
    section "curl via tun"
    curl -s -m 8 -o /dev/null -w '%{http_code}\n' https://www.google.com
    section "config tun block"
    sed -n '/^tun:/,/^[a-z]/p' /etc/mihomo/config.yaml | head -12
    section "providers summary"
    curl -s http://127.0.0.1:9090/providers/proxies | head -c 400; echo
}

# Маскировка: подписочные токены и query-секреты, hwid, MAC, IPv4 кроме 198.18.* и 127.0.0.*
mask(){
    python3 -c 'import re,sys
text = sys.stdin.read()
for pattern, repl in [
    (r"([?&](?:hwid|token|key|id|password|auth)=)[^&\s]+", r"\1MASKED"),
    (r"https://[^\s]+/s/[^\s?]+", "https://MASKED-SUB/s/MASKED"),
    (r"\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b", "MAC:MASKED"),
    (r"\b(?!198\.18\.|127\.0\.0\.)(?:\d{1,3}\.){3}\d{1,3}\b", "IP:MASKED"),
]:
    text = re.sub(pattern, repl, text)
print(text)'
}

collect 2>&1 | mask | tee "$output"
printf '\nДиагностика сохранена: %s\nПеред публикацией просмотри глазами.\n' "$output"
