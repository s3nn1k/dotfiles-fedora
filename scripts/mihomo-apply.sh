#!/usr/bin/env bash
# Рендер шаблона mihomo с подпиской, установка конфига и systemd-юнита, запуск службы.
set -euo pipefail

REPOSITORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPOSITORY/mihomo/config.yaml.tmpl"
SUBSCRIPTION_FILE="$HOME/.config/mihomo/subscription-url"

die() {
    echo "mihomo-apply: $1" >&2
    exit 1
}

[[ -x /usr/local/bin/mihomo ]] || die "нет /usr/local/bin/mihomo - поставь через scripts/bootstrap.sh"
[[ -f "$SUBSCRIPTION_FILE" ]] || die "нет $SUBSCRIPTION_FILE - положи туда https-ссылку подписки"

subscription="$(head -n 1 "$SUBSCRIPTION_FILE")"
subscription="${subscription//[[:space:]]/}"
[[ -n "$subscription" ]] || die "$SUBSCRIPTION_FILE пуст"
[[ "$subscription" == https://* ]] || die "подписка должна начинаться с https://"

# Экранирование спецсимволов replacement-а sed: обратный слеш, &, |
subscription="${subscription//\\/\\\\}"
subscription="${subscription//&/\\&}"
subscription="${subscription//|/\\|}"

sudo install -d -m 755 /etc/mihomo
temporary_config="$(mktemp)"
chmod 600 "$temporary_config"
trap 'rm -f "$temporary_config"' EXIT
sed "s|__SUBSCRIPTION_URL__|$subscription|" "$TEMPLATE" > "$temporary_config"
sudo install -m 600 "$temporary_config" /etc/mihomo/config.yaml
rm -f "$temporary_config"
trap - EXIT
sudo install -m 644 "$REPOSITORY/mihomo/mihomo.service" /etc/systemd/system/mihomo.service
sudo systemctl daemon-reload
sudo systemctl enable --now mihomo
sudo systemctl restart mihomo
