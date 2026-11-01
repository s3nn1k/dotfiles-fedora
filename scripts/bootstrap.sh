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
        if [[ "$resolved_destination" == "$REPOSITORY"/* ]]; then
            rm "$destination"
        else
            echo "bootstrap: $destination не наш симлинк; перенеси вручную и повтори" >&2
            return 1
        fi
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

    [[ -s "$subscription_file" ]] || {
        echo "bootstrap: подписка обязательна для продолжения" >&2
        return 1
    }
    chmod 600 "$subscription_file"
    "$REPOSITORY/scripts/mihomo-apply.sh"
    sudo systemctl is-active --quiet mihomo || {
        echo "bootstrap: служба mihomo неактивна" >&2
        return 1
    }
}

install_telegram() (
    local local_prefix="$HOME/.local/opt/telegram-desktop"
    local telegram_binary="$local_prefix/Telegram"
    local telegram_link="$LOCAL_BIN/telegram"
    local desktop_entry="$HOME/.local/share/applications/telegram-desktop.desktop"
    local desktop_exec desktop_content staging_directory archive_path cleanup_command
    local expected_installation=false

    [[ "$HOME" == /* ]] || {
        echo "bootstrap: HOME должен быть абсолютным путём" >&2
        return 1
    }
    case "$HOME" in
        *'%'*|*'$'*|*'`'*|*'\'*|*[[:cntrl:]]*)
            echo "bootstrap: HOME содержит неподдерживаемые символы для ярлыка Telegram" >&2
            return 1
            ;;
    esac

    desktop_exec="${telegram_binary//\\/\\\\}"
    desktop_exec="${desktop_exec//\"/\\\"}"
    desktop_exec="\"$desktop_exec\""
    desktop_content="[Desktop Entry]
Type=Application
Name=Telegram
Exec=$desktop_exec
Terminal=false
Categories=Network;InstantMessaging;
"

    if [[ -L "$local_prefix" ]]; then
        echo "bootstrap: $local_prefix является чужой ссылкой; перенеси вручную и повтори" >&2
        return 1
    elif [[ -e "$local_prefix" ]]; then
        [[ -d "$local_prefix" && ! -L "$local_prefix" &&
            -f "$telegram_binary" && ! -L "$telegram_binary" && -x "$telegram_binary" ]] || {
            echo "bootstrap: $local_prefix не похож на ожидаемую установку; перенеси вручную и повтори" >&2
            return 1
        }
        expected_installation=true
    fi

    if [[ -L "$telegram_link" ]]; then
        [[ "$expected_installation" == true && "$(readlink "$telegram_link")" == "$telegram_binary" ]] || {
            echo "bootstrap: $telegram_link уже занят; перенеси вручную и повтори" >&2
            return 1
        }
    elif [[ -e "$telegram_link" ]]; then
        echo "bootstrap: $telegram_link уже занят; перенеси вручную и повтори" >&2
        return 1
    fi

    if [[ -e "$desktop_entry" || -L "$desktop_entry" ]]; then
        [[ -f "$desktop_entry" && ! -L "$desktop_entry" ]] || {
            echo "bootstrap: $desktop_entry уже занят; перенеси вручную и повтори" >&2
            return 1
        }
        cmp -s "$desktop_entry" <(printf '%s' "$desktop_content") || {
            echo "bootstrap: $desktop_entry уже занят; перенеси вручную и повтори" >&2
            return 1
        }
    fi

    if [[ "$expected_installation" != true ]]; then
        staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-fedora-telegram.XXXXXX")" || {
            echo "bootstrap: не удалось создать временный каталог Telegram" >&2
            return 1
        }
        printf -v cleanup_command 'rm -rf -- %q' "$staging_directory"
        trap "$cleanup_command" EXIT
        archive_path="$staging_directory/telegram.tar.xz"

        curl --fail --location --show-error --retry 2 --retry-max-time 600 \
            --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' \
            --tlsv1.2 --output "$archive_path" https://telegram.org/dl/desktop/linux || {
            echo "bootstrap: не удалось скачать официальный Telegram" >&2
            return 1
        }

        python3 - "$archive_path" "$staging_directory" <<'PY'
import posixpath
import sys
import tarfile

archive_path, extraction_directory = sys.argv[1:]


def fail(message):
    raise SystemExit(f"bootstrap: {message}")


with tarfile.open(archive_path, "r:*") as archive:
    members = archive.getmembers()
    seen_paths = set()
    root_member = None
    binary_member = None

    for member in members:
        name = member.name
        if not name or "\x00" in name or "\\" in name or name.startswith("/"):
            fail("архив содержит небезопасный путь")
        normalized_name = posixpath.normpath(name)
        if normalized_name != name.rstrip("/") or normalized_name == "..":
            fail("архив содержит путь с обходом каталогов")
        if normalized_name != "Telegram" and not normalized_name.startswith("Telegram/"):
            fail("архив содержит путь вне Telegram/")
        if normalized_name in seen_paths:
            fail("архив содержит повторяющийся путь")
        seen_paths.add(normalized_name)

        if member.issym() or member.islnk() or member.isdev():
            fail("архив содержит ссылку или специальный файл")
        if not (member.isdir() or member.isreg()):
            fail("архив содержит неподдерживаемый тип файла")

        if normalized_name == "Telegram":
            if root_member is not None or not member.isdir():
                fail("архив не содержит ожидаемый корень Telegram/")
            root_member = member
        if normalized_name == "Telegram/Telegram":
            if binary_member is not None or not member.isreg() or not member.mode & 0o111:
                fail("архив не содержит исполняемый файл Telegram")
            binary_member = member

    if root_member is None or binary_member is None:
        fail("архив не содержит ожидаемую установку Telegram")

    try:
        archive.extractall(extraction_directory, filter="data")
    except TypeError:
        archive.extractall(extraction_directory)
PY

        [[ -d "$staging_directory/Telegram" && ! -L "$staging_directory/Telegram" &&
            -f "$staging_directory/Telegram/Telegram" &&
            ! -L "$staging_directory/Telegram/Telegram" &&
            -x "$staging_directory/Telegram/Telegram" ]] || {
            echo "bootstrap: распакованный архив не содержит исполняемый Telegram" >&2
            return 1
        }
        [[ ! -e "$local_prefix" && ! -L "$local_prefix" ]] || {
            echo "bootstrap: путь установки изменился во время скачивания; повтори" >&2
            return 1
        }
        mkdir -p "$(dirname "$local_prefix")"
        mv "$staging_directory/Telegram" "$local_prefix"
    fi

    if [[ ! -L "$telegram_link" && ! -e "$telegram_link" ]]; then
        mkdir -p "$(dirname "$telegram_link")"
        ln -s "$telegram_binary" "$telegram_link"
    fi

    if [[ ! -e "$desktop_entry" && ! -L "$desktop_entry" ]]; then
        mkdir -p "$(dirname "$desktop_entry")"
        printf '%s' "$desktop_content" > "$desktop_entry"
    fi
)

install_metacubexd() {
    download https://github.com/MetaCubeX/metacubexd/releases/download/v1.273.1/compressed-dist.tgz \
        a178e00b67acabcda2dcef00afa90be6a7bb261e466a67dad58c8478d9553603 "$CACHE/metacubexd.tgz"
    sudo tar -xzf "$CACHE/metacubexd.tgz" -C /etc/mihomo/ui
}

# Эквивалентность https-URL клона независимо от суффикса .git и хвостового /
normalize_git_url() {
    local url="$1"
    url="${url%/}"
    url="${url%.git}"
    printf '%s
' "$url"
}

# Существующий клон: git pull --ff-only; расхождение с origin - громкий стоп
update_repository() {
    local destination="$1" pull_output attempt
    for attempt in 1 2 3; do
        if pull_output="$(LC_ALL=C git -C "$destination" pull --ff-only 2>&1)"; then
            echo "updated:  $destination"
            return 0
        fi
        if printf '%s\n' "$pull_output" | grep -q 'would be overwritten by merge\|cannot pull with rebase\|Please commit your changes'; then
            echo "bootstrap: pull пропущен, локальные изменения не тронуты: $destination" >&2
            return 0
        fi
        if printf '%s\n' "$pull_output" | grep -qi 'not possible to fast-forward\|divergent branches'; then
            echo "bootstrap: $destination разошёлся с origin; разрули вручную и перезапусти" >&2
            return 1
        fi
        echo "bootstrap: pull не прошёл (попытка $attempt): $destination" >&2
        [[ "$attempt" == 3 ]] && break
        sleep 3
    done
    echo "bootstrap: pull не прошёл после повторов; продолжаю с текущим состоянием: $destination" >&2
    return 0
}

clone_repository() {
    local url="$1" destination="$2" origin
    if [[ -e "$destination" || -L "$destination" ]]; then
        [[ -d "$destination/.git" ]] || {
            echo "bootstrap: unexpected directory: $destination" >&2
            return 1
        }
        origin="$(git -C "$destination" remote get-url origin)" || {
            echo "bootstrap: cannot read origin: $destination" >&2
            return 1
        }
        [[ "$(normalize_git_url "$origin")" == "$(normalize_git_url "$url")" ]] || {
            echo "bootstrap: unexpected origin for $destination: $origin" >&2
            return 1
        }
        update_repository "$destination"
    else
        mkdir -p "$(dirname "$destination")"
        local attempt
        for attempt in 1 2 3; do
            if git clone "$url" "$destination"; then
                echo "cloned:  $destination"
                return 0
            fi
            rm -rf -- "$destination"
            echo "bootstrap: клон не прошёл (попытка $attempt): $url" >&2
            [[ "$attempt" == 3 ]] && return 1
            sleep 3
        done
    fi
}

main() {
    # Проверки окружения и sudo-сессия на весь запуск
    require_fedora
    sudo -v

    # Системные пакеты Fedora: git, shell, редактор, языки, утилиты, шрифты
    sudo dnf install -y git git-crypt gh curl jq make gcc gcc-c++ golang \
        python3 pipx uv neovim ripgrep fd-find wl-clipboard acl \
        zsh zsh-autosuggestions zsh-syntax-highlighting util-linux-user \
        fontconfig google-noto-sans-fonts unzip
    sudo dnf install -y --allowerasing nodejs24 nodejs24-npm nodejs24-bin nodejs24-npm-bin

    mkdir -p "$CACHE" "$HOME/.local/bin"

    # Имя встроенного экрана (масштаб 2.25 применяется к нему)
    local output
    output="$(swaymsg -r -t get_outputs | jq -re '
        [.[] | select(.active == true and (.name | test("^eDP-[0-9]+$"))) | .name]
        | if length == 1 then .[0] else error("expected one active eDP output") end
    ')" || { echo "bootstrap: нужен один активный eDP-экран; запусти из Sway" >&2; return 1; }

    # Конфиги репозитория -> симлинки; имя экрана -> sway/output.conf
    set_output_name "$REPOSITORY" "$output"
    local name
    for name in sway/config sway/desktop.conf sway/output.conf \
        sway/background.conf swaylock/config foot/foot.ini \
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
    install_command "$REPOSITORY/bin/credentials-setup.sh" credentials-setup
    install_command "$REPOSITORY/bin/git-crypt-repo.sh" git-crypt-repo
    install_command "$REPOSITORY/bin/git-crypt-repo.sh" git-crypt-textconv
    install_command "$REPOSITORY/bin/git-cred-read.sh" git-cred-read
    link_config "$LOCAL_BIN/git-crypt-repo" "$HOME/.local/share/git-crypt/hooks/pre-commit"
    link_config "$REPOSITORY/systemd/ssh-agent.service" "$CONFIGURATION_HOME/systemd/user/ssh-agent.service"
    systemctl --user daemon-reload
    systemctl --user enable --now ssh-agent.service

    install_mihomo
    install_telegram
    install_metacubexd

    if gh auth token --hostname github.com >/dev/null 2>&1; then
        echo "GitHub авторизация уже настроена"
    else
        echo "gh: не авторизован — вход через HTTPS"
        gh_auth_login
    fi

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

    # pi: runtime в ~/.local, конфиг в ~/.pi/agent
    clone_repository https://github.com/s3nn1k/pi-agent.git "$HOME/.pi/agent"
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 19)) process.exit(1)'
    npm install --global --prefix "$HOME/.local" --ignore-scripts @earendil-works/pi-coding-agent@1.3.0
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
    "$HOME/projects/personal/keyd-cfqv8/scripts/xremap-apply.sh"

    clone_repository https://github.com/s3nn1k/obsidian-config.git "$CONFIGURATION_HOME/obsidian"
    for vault_name in personal work; do
        VAULT="$HOME/vaults/$vault_name"
        mkdir -p "$(dirname "$VAULT")"
        clone_repository "https://github.com/s3nn1k/obsidian-$vault_name.git" "$VAULT"
    done
    "$REPOSITORY/scripts/setup-secrets.sh" link
    # Регистрация vault выполняется через GUI Flatpak-версии Obsidian.

    printf '%s\n' "Готово. Выйди из сессии и войди снова для zsh." \
        "Дальше: открой nkp, достань ключи и запусти scripts/setup-secrets.sh unlock." \
        "VPN: смена подписки - ~/.config/mihomo/subscription-url + scripts/mihomo-apply.sh, панель http://127.0.0.1:9090/ui."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
