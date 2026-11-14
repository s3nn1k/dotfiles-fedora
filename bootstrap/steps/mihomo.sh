install_mihomo() {
    local subscription_file="$HOME/.config/mihomo/subscription-url" subscription_url

    download https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-linux-amd64-v1.19.33.gz \
        132f6f3edf9a65e62f04853aed3358472e0b2b7666daa8419edfa2ddf5bb6323 "$CACHE/mihomo.gz"
    gunzip -c "$CACHE/mihomo.gz" > "$CACHE/mihomo"
    sudo install -m 755 "$CACHE/mihomo" /usr/local/bin/mihomo
    sudo install -d -m 755 /etc/mihomo/ui /etc/mihomo/providers
    mkdir -p "$(dirname "$subscription_file")"

    if [[ ! -s "$subscription_file" ]]; then
        if ! read -r -s -p "Подписка VPN (https-ссылка): " subscription_url; then
            echo
            echo "bootstrap: подписка обязательна для продолжения" >&2
            return 1
        fi
        echo
        [[ -n "$subscription_url" ]] || {
            echo "bootstrap: подписка обязательна для продолжения" >&2
            return 1
        }
        [[ "$subscription_url" == https://* ]] || {
            echo "bootstrap: подписка должна начинаться с https://" >&2
            return 1
        }
        printf '%s\n' "$subscription_url" > "$subscription_file"
    fi

    chmod 600 "$subscription_file"
}

install_metacubexd() {
    download https://github.com/MetaCubeX/metacubexd/releases/download/v1.273.1/compressed-dist.tgz \
        a178e00b67acabcda2dcef00afa90be6a7bb261e466a67dad58c8478d9553603 "$CACHE/metacubexd.tgz"
    sudo tar -xzf "$CACHE/metacubexd.tgz" -C /etc/mihomo/ui
}

mihomo_die() {
    echo "mihomo-apply: $1" >&2
    exit 1
}

apply_mihomo_subscription() {
    TEMPLATE="$REPOSITORY/mihomo/config.yaml.tmpl"
    SUBSCRIPTION_FILE="$HOME/.config/mihomo/subscription-url"

    [[ -x /usr/local/bin/mihomo ]] || { echo "mihomo: нет подписки - сервис поднимется после setup-secrets unlock" >&2; return 0; }
    [[ -f "$SUBSCRIPTION_FILE" ]] || { echo "mihomo: нет подписки - сервис поднимется после setup-secrets unlock" >&2; return 0; }

    subscription="$(head -n 1 "$SUBSCRIPTION_FILE")"
    subscription="${subscription//[[:space:]]/}"
    [[ -n "$subscription" ]] || mihomo_die "$SUBSCRIPTION_FILE пуст"
    [[ "$subscription" == https://* ]] || mihomo_die "подписка должна начинаться с https://"
    
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
    # Кэш провайдера чистим: смена подписки применяется сразу
    sudo rm -f /etc/mihomo/providers/subscription.yaml
    sudo systemctl restart mihomo
}

run_mihomo() {
    install_mihomo
    install_metacubexd
    apply_mihomo_subscription
    sudo systemctl is-active --quiet mihomo || {
        echo "bootstrap: служба mihomo неактивна" >&2
        return 1
    }
}
