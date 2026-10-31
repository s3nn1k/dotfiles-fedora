#!/usr/bin/env bash
# Настройка ноутбука Fedora Sway: пакеты, инструменты, конфиги-симлинки, GRUB.
set -euo pipefail

# Расположение этого репозитория и общие пути
REPOSITORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
export GOBIN="$HOME/.local/bin"
CACHE="$HOME/.cache/dotfiles-fedora"
CONFIGURATION_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"

# Проверки: Fedora Sway x86_64, обычный пользователь, GRUB
require_fedora() {
    [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
        echo "bootstrap: требуется Fedora Sway x86_64, не macOS" >&2
        return 1
    }
    [[ "$EUID" != 0 ]] || { echo "bootstrap: запускай без sudo" >&2; return 1; }
    [[ -f /etc/os-release ]] || return 1
    . /etc/os-release
    [[ "$ID" == fedora && "$CONFIGURATION_HOME" == /* && -f /etc/sway/config && -f /etc/default/grub ]] || {
        echo "bootstrap: требуется установленная Fedora Sway с GRUB" >&2
        return 1
    }
}

# Скачивание файла с проверкой sha256; повторный запуск использует кэш
download() {
    local url="$1" checksum="$2" destination="$3"
    if [[ -f "$destination" ]] && printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check --status; then
        return
    fi
    curl --fail --location --show-error --retry 2 --connect-timeout 15 --max-time 300 \
        --proto '=https' --tlsv1.2 --output "$destination.part" "$url"
    printf '%s  %s\n' "$checksum" "$destination.part" | sha256sum --check
    mv "$destination.part" "$destination"
}

# Симлинк из репозитория в $HOME; чужой существующий путь не трогаем
link_config() {
    local source="$1" destination="$2" resolved_source resolved_destination
    [[ -f "$source" ]] || { echo "bootstrap: нет источника $source" >&2; return 1; }
    resolved_source="$(readlink -f "$source")" || {
        echo "bootstrap: не удалось разрешить источник $source" >&2
        return 1
    }
    if [[ -L "$destination" ]]; then
        resolved_destination="$(readlink -f "$destination")" || {
            echo "bootstrap: $destination неразрешимая ссылка; перенеси вручную и повтори" >&2
            return 1
        }
        [[ "$resolved_destination" == "$resolved_source" ]] && return
        echo "bootstrap: $destination не наш симлинк; перенеси вручную и повтори" >&2
        return 1
    elif [[ -e "$destination" ]]; then
        echo "bootstrap: $destination существует; перенеси вручную и повтори" >&2
        return 1
    fi
    mkdir -p "$(dirname "$destination")"
    ln -s "$resolved_source" "$destination"
}

install_command() {
    local source="$1" name="$2"
    link_config "$source" "$LOCAL_BIN/$name" || return 1
    echo "command: $LOCAL_BIN/$name -> $source"
}

# Записать фактическое имя встроенного экрана в sway/output.conf
set_output_name() {
    sed -i.bak -E "s/^output [^ ]+ scale /output $2 scale /" "$1/sway/output.conf"
    rm -f "$1/sway/output.conf.bak"
}

# GRUB: скрыть меню, ждать 1 секунду (Esc показывает меню)
configure_grub() {
    local path="${1:-/etc/default/grub}"
    sudo sed -i.bak -E 's/^[[:space:]]*GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' "$path"
    sudo rm -f "$path.bak"
    sudo grep -qE '^GRUB_TIMEOUT_STYLE=' "$path" || echo 'GRUB_TIMEOUT_STYLE=hidden' | sudo tee -a "$path" >/dev/null
    sudo sed -i.bak -E 's/^[[:space:]]*GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "$path"
    sudo rm -f "$path.bak"
    sudo grep -qE '^GRUB_TIMEOUT=' "$path" || echo 'GRUB_TIMEOUT=1' | sudo tee -a "$path" >/dev/null
}

gh_auth_login() {
    local temporary_git_config login_status
    temporary_git_config="$(mktemp "${TMPDIR:-/tmp}/dotfiles-fedora-gh.XXXXXX")"
    if GIT_CONFIG_GLOBAL="$temporary_git_config" gh auth login --git-protocol https; then
        rm -f "$temporary_git_config"
        return 0
    else
        login_status=$?
        rm -f "$temporary_git_config" || return 1
        return "$login_status"
    fi
}

clone_repository() {
    local url="$1" destination="$2" origin working_tree_status
    if [[ -e "$destination" || -L "$destination" ]]; then
        [[ -d "$destination/.git" ]] || {
            echo "bootstrap: unexpected directory: $destination" >&2
            return 1
        }
        origin="$(git -C "$destination" remote get-url origin)" || {
            echo "bootstrap: cannot read origin: $destination" >&2
            return 1
        }
        [[ "$origin" == "$url" ]] || {
            echo "bootstrap: unexpected origin for $destination: $origin" >&2
            return 1
        }
        working_tree_status="$(git -C "$destination" status --porcelain)" || {
            echo "bootstrap: cannot read status: $destination" >&2
            return 1
        }
        if [[ -n "$working_tree_status" ]]; then
            echo "bootstrap: existing repository has local changes; skipped: $destination" >&2
        else
            echo "bootstrap: existing repository; skipped: $destination"
        fi
    else
        mkdir -p "$(dirname "$destination")"
        git clone "$url" "$destination"
        echo "cloned:  $destination"
    fi
}

main() {
    # Проверки окружения и sudo-сессия на весь запуск
    require_fedora
    sudo -v

    # Системные пакеты Fedora: git, shell, редактор, языки, утилиты, шрифты
    sudo dnf install -y git git-crypt gh curl jq make gcc gcc-c++ golang nodejs npm \
        python3 pipx uv neovim ripgrep fd-find wl-clipboard \
        zsh zsh-autosuggestions zsh-syntax-highlighting util-linux-user \
        fontconfig google-noto-sans-fonts unzip

    if ! gh auth status >/dev/null 2>&1; then
        echo "gh: не авторизован — вход через HTTPS"
        gh_auth_login
    fi

    # Каталоги для ручных установок; Node 22.19+ нужен pi
    mkdir -p "$CACHE" "$HOME/.local/bin"
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 19)) process.exit(1)'

    # Имя встроенного экрана (масштаб 2.25 применяется к нему)
    local output
    output="$(swaymsg -r -t get_outputs | jq -re '
        [.[] | select(.active == true and (.name | test("^eDP-[0-9]+$"))) | .name]
        | if length == 1 then .[0] else error("expected one active eDP output") end
    ')" || { echo "bootstrap: нужен один активный eDP-экран; запусти из Sway" >&2; return 1; }

    # Конфиги репозитория -> симлинки; имя экрана -> sway/output.conf
    set_output_name "$REPOSITORY" "$output"
    local name
    for name in sway/config sway/desktop.conf sway/output.conf foot/foot.ini \
        gtk-3.0/settings.ini gtk-4.0/settings.ini; do
        link_config "$REPOSITORY/$name" "$CONFIGURATION_HOME/$name"
    done
    link_config "$REPOSITORY/zshrc" "$HOME/.zshrc"
    link_config "$REPOSITORY/zprofile" "$HOME/.zprofile"
    link_config "$REPOSITORY/gitconfig" "$HOME/.gitconfig"

    # Валидация и применение: рабочий стол оживает до загрузок
    sway -C -c "$CONFIGURATION_HOME/sway/config"
    foot --check-config --config="$CONFIGURATION_HOME/foot/foot.ini"
    swaymsg reload

    mkdir -p "$LOCAL_BIN"
    install_command "$REPOSITORY/scripts/credentials-setup.sh" credentials-setup
    install_command "$REPOSITORY/scripts/git-crypt-repo.sh" git-crypt-repo
    install_command "$REPOSITORY/scripts/git-crypt-repo.sh" git-crypt-textconv
    install_command "$REPOSITORY/scripts/git-cred-read.sh" git-cred-read
    link_config "$LOCAL_BIN/git-crypt-repo" "$HOME/.local/share/git-crypt/hooks/pre-commit"
    link_config "$REPOSITORY/systemd/ssh-agent.service" "$CONFIGURATION_HOME/systemd/user/ssh-agent.service"
    systemctl --user daemon-reload
    systemctl --user enable --now ssh-agent.service

    CREDENTIALS="$HOME/credentials"
    clone_repository https://github.com/s3nn1k/credentials.git "$CREDENTIALS"

    mkdir -p "$HOME/projects/work"
    local repository_entry repository_url destination
    PERSONAL_REPOSITORIES=(
        "https://github.com/s3nn1k/nova-42|$HOME/projects/personal/nova-42"
        "https://github.com/s3nn1k/ci-cd.git|$HOME/projects/personal/ci-cd"
        "https://github.com/s3nn1k/go-service-template.git|$HOME/projects/personal/go-service-template"
        "https://github.com/s3nn1k/nkp.git|$HOME/projects/personal/nkp"
        "https://github.com/s3nn1k/keyd-cfqv8.git|$HOME/projects/personal/keyd-cfqv8"
    )
    for repository_entry in "${PERSONAL_REPOSITORIES[@]}"; do
        repository_url="${repository_entry%%|*}"
        destination="${repository_entry#*|}"
        clone_repository "$repository_url" "$destination"
    done
    NKP="$HOME/projects/personal/nkp"
    make -C "$NKP" install

    # Промпт: oh-my-posh
    download https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v31.9.1/posh-linux-amd64 \
        574074a4e84797180e0bda0d133da5f01fbda89ecdb450134c7e566b9a389212 "$CACHE/oh-my-posh"
    install -m 755 "$CACHE/oh-my-posh" "$HOME/.local/bin/oh-my-posh"

    # Шрифт Hack Nerd Font для терминала и Neovim
    download https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Hack.zip \
        fa24da7de7cefe7766614d27762570b20453c852fc1d5b657111666df9a5e449 "$CACHE/Hack.zip"
    mkdir -p "$HOME/.local/share/fonts/Hack"
    unzip -oq "$CACHE/Hack.zip" -d "$HOME/.local/share/fonts/Hack"
    fc-cache -f "$HOME/.local/share/fonts/Hack"

    # mihomo: headless-прокси с TUN; подписка запрашивается интерактивно
    download https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-linux-amd64-v1.19.33.gz \
        132f6f3edf9a65e62f04853aed3358472e0b2b7666daa8419edfa2ddf5bb6323 "$CACHE/mihomo.gz"
    gunzip -c "$CACHE/mihomo.gz" > "$CACHE/mihomo"
    sudo install -m 755 "$CACHE/mihomo" /usr/local/bin/mihomo
    download https://github.com/MetaCubeX/metacubexd/releases/download/v1.273.1/compressed-dist.tgz \
        a178e00b67acabcda2dcef00afa90be6a7bb261e466a67dad58c8478d9553603 "$CACHE/metacubexd.tgz"
    sudo install -d -m 755 /etc/mihomo/ui /etc/mihomo/providers
    sudo tar -xzf "$CACHE/metacubexd.tgz" -C /etc/mihomo/ui
    mkdir -p "$HOME/.config/mihomo"
    local subscription_url
    if [[ ! -s "$HOME/.config/mihomo/subscription-url" ]]; then
        read -r -s -p "Подписка VPN (https-ссылка, Enter - пропустить): " subscription_url
        echo
        if [[ -n "$subscription_url" ]]; then
            [[ "$subscription_url" == https://* ]] || { echo "bootstrap: подписка должна начинаться с https://" >&2; return 1; }
            printf '%s\n' "$subscription_url" > "$HOME/.config/mihomo/subscription-url"
            chmod 600 "$HOME/.config/mihomo/subscription-url"
        fi
    fi
    if [[ -s "$HOME/.config/mihomo/subscription-url" ]]; then
        "$REPOSITORY/scripts/mihomo-apply.sh"
    else
        echo "bootstrap: подписки нет - позже запусти ~/dotfiles-fedora/scripts/mihomo-apply.sh" >&2
    fi

    # pi: runtime в ~/.local, конфиг в ~/.pi/agent
    npm install --global --prefix "$HOME/.local" --ignore-scripts @earendil-works/pi-coding-agent@1.3.0
    clone_repository https://github.com/s3nn1k/pi-agent.git "$HOME/.pi/agent"
    make -C "$HOME/.pi/agent" init
    "$HOME/.local/bin/pi" update --extensions

    # Мои конфиг-репозитории: Neovim и тема промпта
    clone_repository https://github.com/s3nn1k/nvim.git "$CONFIGURATION_HOME/nvim"
    clone_repository https://github.com/s3nn1k/zenwritten_dark.git "$CONFIGURATION_HOME/zenwritten_dark"
    # Инициализация Neovim: зависимости и плагины
    "$CONFIGURATION_HOME/nvim/init.sh"

    # GRUB: скрытое меню + пересборка конфига загрузчика
    configure_grub
    sudo restorecon /etc/default/grub
    sudo grub2-editenv - list | grep -q menu_auto_hide && sudo grub2-editenv - unset menu_auto_hide
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg

    # Zsh как shell по умолчанию
    local shell
    shell="$(command -v zsh)"
    if [[ "$(getent passwd "$(id -un)" | cut -d: -f7)" != "$shell" ]]; then
        chsh -s "$shell"
    fi

    sudo dnf -y copr enable alternateved/keyd
    sudo dnf install -y keyd

    sudo "$HOME/projects/personal/keyd-cfqv8/apply.sh"

    clone_repository https://github.com/s3nn1k/obsidian-config.git "$CONFIGURATION_HOME/obsidian"
    for vault_name in personal work; do
        VAULT="$HOME/vaults/$vault_name"
        mkdir -p "$(dirname "$VAULT")"
        clone_repository "https://github.com/s3nn1k/obsidian-$vault_name.git" "$VAULT"
    done
    # Регистрация vault выполняется через GUI Flatpak-версии Obsidian.

    printf '%s\n' "Готово. Выйди из сессии и войди снова для zsh." \
        "manual steps:" \
        "  1. после ручной работы с nkp: ~/dotfiles-fedora/scripts/setup-secrets.sh (подключит auth.json и mcp.json из ~/credentials/pi при наличии)" \
        "  2. токены агента: ~/credentials/agents-credentials/git-credentials (подключи нужные токены)" \
        "  3. VPN: смена подписки - ~/.config/mihomo/subscription-url + scripts/mihomo-apply.sh, панель http://127.0.0.1:9090/ui."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
