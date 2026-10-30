#!/usr/bin/env bash
# Настройка ноутбука Fedora Sway: пакеты, инструменты, конфиги-симлинки, GRUB.
set -euo pipefail

# Расположение этого репозитория и общие пути
REPOSITORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
export GOBIN="$HOME/.local/bin"
CACHE="$HOME/.cache/dotfiles-fedora"
CONFIGURATION_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

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

# Симлинк из репозитория в $HOME; чужой существующий файл не трогаем
link_config() {
    local source="$1" destination="$2"
    [[ -f "$source" ]] || { echo "bootstrap: нет источника $source" >&2; return 1; }
    if [[ -L "$destination" ]]; then
        [[ "$(readlink -f "$destination")" == "$(readlink -f "$source")" ]] && return
        rm "$destination"
    elif [[ -e "$destination" ]]; then
        echo "bootstrap: $destination существует и не наш симлинк - разреши вручную" >&2
        return 1
    fi
    mkdir -p "$(dirname "$destination")"
    ln -s "$(readlink -f "$source")" "$destination"
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

# Клонировать мой репозиторий; существующий с тем же origin не трогаем
clone_repository() {
    local url="$1" destination="$2"
    if [[ -e "$destination" || -L "$destination" ]]; then
        [[ -d "$destination/.git" && "$(git -C "$destination" remote get-url origin)" == "$url" ]] || {
            echo "bootstrap: неожиданный каталог или origin: $destination" >&2
            return 1
        }
    else
        mkdir -p "$(dirname "$destination")"
        git clone "$url" "$destination"
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

    # Каталоги для ручных установок; Node 22.19+ нужен pi
    mkdir -p "$CACHE" "$HOME/.local/bin"
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 19)) process.exit(1)'

    # Имя встроенного экрана (масштаб 2.25 применяется к нему)
    local output
    output="$(swaymsg -r -t get_outputs | jq -re '
        [.[] | select(.active == true and (.name | test("^eDP-[0-9]+$"))) | .name]
        | if length == 1 then .[0] else error("expected one active eDP output") end
    ')" || { echo "bootstrap: нужен один активный eDP-экран; запусти из Sway" >&2; return 1; }

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

    # Throne: VPN-клиент (без подписки, TUN и автозапуска)
    download https://github.com/throneproj/Throne/releases/download/1.3.2/Throne-1.3.2-fedora-amd64-system-qt.rpm \
        2cb6d5bb0febd95a17063183e0d9bc999f68b8f8bcda255fcdd6936911fcaf22 "$CACHE/Throne.rpm"
    sudo dnf install -y "$CACHE/Throne.rpm"

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

    # Валидация: конфиги Sway и foot
    sway -C -c "$CONFIGURATION_HOME/sway/config"
    foot --check-config --config="$CONFIGURATION_HOME/foot/foot.ini"

    # GRUB: скрытое меню + пересборка конфига загрузчика
    configure_grub
    sudo restorecon /etc/default/grub
    sudo grub2-editenv - list | grep -q menu_auto_hide && sudo grub2-editenv - unset menu_auto_hide
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg

    # Zsh как shell по умолчанию и перезагрузка Sway
    local shell
    shell="$(command -v zsh)"
    if [[ "$(getent passwd "$(id -un)" | cut -d: -f7)" != "$shell" ]]; then
        chsh -s "$shell"
    fi
    swaymsg reload

    # Что осталось сделать руками
    printf '%s\n' "Готово. Выйди из сессии и войди снова для zsh." \
        "Throne установлен без подписки, TUN и автозапуска." \
        "Pi запускается на хосте командой pi; контейнер не настраивается." \
        "Авторизацию pi и внешние репозитории из его settings.json подключи отдельно."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
