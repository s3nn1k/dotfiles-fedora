#!/usr/bin/env bash
# Рендер keyd-раскладки с id клавиатуры, установка конфига и перезапуск службы.
set -euo pipefail

REPOSITORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPOSITORY/keyd/nova.conf"
IDS_FILE="$HOME/.config/keyd/ids"

die() {
    echo "keyd-apply: $1" >&2
    exit 1
}

command -v keyd >/dev/null || die "нет keyd - поставь через scripts/bootstrap.sh"
[[ -f "$IDS_FILE" ]] || die "нет $IDS_FILE - положи туда строку вида k0123:abcd из sudo keyd monitor"

ids="$(awk 'NF { print; exit }' "$IDS_FILE")"
ids="${ids//[[:space:]]/}"
[[ -n "$ids" ]] || die "$IDS_FILE пуст"
[[ "$ids" == *:* ]] || die "$IDS_FILE: ожидался id вида k0123:abcd"

sudo install -d -m 755 /etc/keyd
temporary_config="$(mktemp)"
chmod 600 "$temporary_config"
trap 'rm -f "$temporary_config"' EXIT
sed "s|__KEYBOARD_IDS__|$ids|" "$TEMPLATE" > "$temporary_config"
sudo install -m 644 "$temporary_config" /etc/keyd/default.conf
rm -f "$temporary_config"
trap - EXIT
sudo keyd reload || sudo systemctl restart keyd
