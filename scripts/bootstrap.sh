#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
export GOBIN="$HOME/.local/bin"
CACHE="$HOME/.cache/dotfiles-fedora"
CONFIGURATION_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"

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

checksum_matches() {
    printf '%s  %s\n' "$1" "$2" | sha256sum --check --status
}

verify_checksum() {
    printf '%s  %s\n' "$1" "$2" | sha256sum --check
}

RETRY_STOP=255

retry() {
    local description="$1" target="$2" action="$3" attempt action_status
    shift 3
    for attempt in 1 2 3; do
        action_status=0
        "$action" "$@" || action_status=$?
        [[ "$action_status" == 0 || "$action_status" == "$RETRY_STOP" ]] && return "$action_status"
        echo "bootstrap: $description (попытка $attempt): $target" >&2
        [[ "$attempt" == 3 ]] && return 1
        sleep 3
    done
}

download() {
    local url="$1" checksum="$2" destination="$3"
    if [[ -f "$destination" ]] && checksum_matches "$checksum" "$destination"; then
        return
    fi
    curl --fail --location --show-error --retry 2 --connect-timeout 15 --max-time 300 \
        --proto '=https' --tlsv1.2 --output "$destination.part" "$url"
    verify_checksum "$checksum" "$destination.part"
    mv "$destination.part" "$destination"
}

download_model() {
    local url="$1" checksum="$2" destination="$3"
    if [[ -f "$destination" ]] && checksum_matches "$checksum" "$destination"; then
        return
    fi
    if [[ -f "$destination.part" ]] && checksum_matches "$checksum" "$destination.part"; then
        mv "$destination.part" "$destination"
        return
    fi
    retry "загрузка модели не удалась" "$url" curl --fail --http1.1 --location --show-error \
        --continue-at - --connect-timeout 15 --max-time 1800 \
        --proto '=https' --tlsv1.2 --output "$destination.part" "$url"
    verify_checksum "$checksum" "$destination.part"
    mv "$destination.part" "$destination"
}

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
    [[ -f "$source" ]] || { echo "bootstrap: нет источника $source" >&2; return 1; }
    [[ -x "$source" ]] || { echo "bootstrap: $source не исполняемый; chmod +x и повтори" >&2; return 1; }
    link_config "$source" "$LOCAL_BIN/$name" || return 1
    echo "command: $LOCAL_BIN/$name -> $source"
}

install_system_file() {
    local source="$1" destination="$2"
    [[ -f "$source" ]] || { echo "bootstrap: нет источника $source" >&2; return 1; }
    if sudo test -e "$destination" || sudo test -L "$destination"; then
        if sudo test -f "$destination" && ! sudo test -L "$destination" &&
            sudo cmp -s "$source" "$destination"; then
            return
        fi
        echo "bootstrap: $destination занят чужим содержимым; перенеси вручную и повтори" >&2
        return 1
    fi
    sudo install -D -m 644 "$source" "$destination"
}

set_output_name() {
    sed -i.bak -E "s/^output [^ ]+ scale /output $2 scale /" "$1/sway/output.conf"
    rm -f "$1/sway/output.conf.bak"
}

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

    chmod 600 "$subscription_file"
    "$REPOSITORY/scripts/mihomo-apply.sh"
    sudo systemctl is-active --quiet mihomo || {
        echo "bootstrap: служба mihomo неактивна" >&2
        return 1
    }
}

install_metacubexd() {
    download https://github.com/MetaCubeX/metacubexd/releases/download/v1.273.1/compressed-dist.tgz \
        a178e00b67acabcda2dcef00afa90be6a7bb261e466a67dad58c8478d9553603 "$CACHE/metacubexd.tgz"
    sudo tar -xzf "$CACHE/metacubexd.tgz" -C /etc/mihomo/ui
}

install_whisper() {
    local model="$HOME/.local/share/whisper/models/ggml-large-v3-turbo.bin"
    local source_directory="$CACHE/whisper.cpp-1.9.5" version_file="$LOCAL_BIN/whisper-cli.version"
    local installed_version=""

    download https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.5.tar.gz \
        ff1a9053feb509ff9d7729703355541ae9690073a6b1c40eb692c962e0dc1720 \
        "$CACHE/whisper.cpp-v1.9.5.tar.gz"

    [[ -f "$version_file" ]] && installed_version="$(cat "$version_file")"
    if [[ ! -x "$LOCAL_BIN/whisper-cli" || "$installed_version" != "v1.9.5" ]]; then
        rm -rf "$source_directory"
        tar -xzf "$CACHE/whisper.cpp-v1.9.5.tar.gz" -C "$CACHE"
        cmake -S "$source_directory" -B "$source_directory/build" -DBUILD_SHARED_LIBS=OFF
        cmake --build "$source_directory/build" --config Release -j"$(nproc)"
        install -m 755 "$source_directory/build/bin/whisper-cli" "$LOCAL_BIN/whisper-cli"
        printf 'v1.9.5\n' > "$version_file"
    fi

    mkdir -p "$(dirname "$model")"
    download_model https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin \
        1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69 "$model"
}

install_herdr() {
    download https://github.com/herdrdev/herdr/releases/download/v0.9.5/herdr-linux-x86_64 \
        14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d "$CACHE/herdr"
    install -m 755 "$CACHE/herdr" "$LOCAL_BIN/herdr"
    herdr --version

    mkdir -p "$CONFIGURATION_HOME/herdr"
    link_config "$REPOSITORY/herdr/config.toml" "$CONFIGURATION_HOME/herdr/config.toml"

    herdr integration install pi >/dev/null 2>&1 || true
}

librewolf_installed() {
    command -v librewolf >/dev/null 2>&1
}

install_librewolf() {
    if librewolf_installed; then
        echo "librewolf уже установлен"
        return 0
    fi
    download https://repo.librewolf.net/librewolf.repo \
        0706a3f9295f538e3f590fa738fc254884eb58182c93e9ed0bdf4a20d395a392 "$CACHE/librewolf.repo"
    if [[ ! -f /etc/yum.repos.d/librewolf.repo ]]; then
        sudo install -D -m 644 "$CACHE/librewolf.repo" /etc/yum.repos.d/librewolf.repo
    fi
    sudo dnf install -y librewolf
}

find_librewolf_profiles() {
    local profile_root profile_directory
    for profile_root in "$CONFIGURATION_HOME/librewolf/librewolf" "$HOME/.librewolf"; do
        [[ -d "$profile_root" ]] || continue
        for profile_directory in "$profile_root"/*/; do
            [[ -f "$profile_directory/times.json" ]] || continue
            printf '%s\n' "${profile_directory%/}"
        done
    done
}

install_librewolf_prefs() {
    local source="$HOME/projects/personal/librewolf-config/user.js" profiles profile

    profiles="$(find_librewolf_profiles)"
    [[ -n "$profiles" ]] || {
        echo "bootstrap: не найден ни один профиль LibreWolf; восстанови через scripts/librewolf/profiles.sh и перезапусти" >&2
        return 1
    }

    while IFS= read -r profile; do
        link_config "$source" "$profile/user.js"
    done <<< "$profiles"
}

install_librewolf_chrome() {
    local source="$HOME/projects/personal/librewolf-config/chrome" profiles profile

    profiles="$(find_librewolf_profiles)"
    [[ -n "$profiles" ]] || { echo "bootstrap: не найден ни один профиль LibreWolf" >&2; return 1; }

    # Каталог целиком: css темы, keymap.uc.js, keymap.json и вендор fx-autoconfig.
    # link_config файловый, поэтому симлинк каталога проверяем сами.
    local resolved
    resolved="$(readlink -f "$source")"
    while IFS= read -r profile; do
        if [[ -L "$profile/chrome" ]]; then
            [[ "$(readlink -f "$profile/chrome")" == "$resolved" ]] && continue
            echo "bootstrap: $profile/chrome чужой симлинк; перенеси вручную и повтори" >&2
            return 1
        fi
        if [[ -e "$profile/chrome" ]]; then
            echo "bootstrap: $profile/chrome существует; перенеси вручную и повтори" >&2
            return 1
        fi
        ln -s "$resolved" "$profile/chrome"
    done <<< "$profiles"
}

install_librewolf_policies() {
    local source="$HOME/projects/personal/librewolf-config/policies.json"

    local merged
    merged="$(mktemp)"
    local config_home="$HOME/projects/personal/librewolf-config"
    python3 "$config_home/scripts/merge-policies.py" \
        "$source" \
        "$config_home/chrome/sidebery-sidebar.css" \
        /usr/share/librewolf/distribution/policies.json > "$merged"
    sudo install -D -m 644 "$merged" /usr/share/librewolf/distribution/policies.json
    rm -f "$merged"
}

install_librewolf_autoconfig() {
    local config_home="$HOME/projects/personal/librewolf-config"

    sudo python3 "$config_home/scripts/install-autoconfig.py" --files
    python3 "$config_home/scripts/install-autoconfig.py" --cache
}

normalize_git_url() {
    local url="$1"
    url="${url%/}"
    url="${url%.git}"
    printf '%s
' "$url"
}

pull_once() {
    local destination="$1" pull_output
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
        return "$RETRY_STOP"
    fi
    return 1
}

update_repository() {
    local destination="$1" retry_status=0
    retry "pull не прошёл" "$destination" pull_once "$destination" || retry_status=$?
    [[ "$retry_status" == "$RETRY_STOP" ]] && return 1
    [[ "$retry_status" == 0 ]] && return 0
    echo "bootstrap: pull не прошёл после повторов; продолжаю с текущим состоянием: $destination" >&2
    return 0
}

clone_once() {
    local url="$1" destination="$2"
    if git clone "$url" "$destination"; then
        echo "cloned:  $destination"
        return 0
    fi
    rm -rf -- "$destination"
    return 1
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
        retry "клон не прошёл" "$url" clone_once "$url" "$destination"
    fi
}

main() {
    require_fedora
    sudo -v

    sudo dnf upgrade -y

    sudo dnf install -y git git-crypt gh glab curl jq make gcc gcc-c++ golang postgresql \
        python3 pipx uv neovim ripgrep fd-find wl-clipboard acl kubectl \
        zsh zsh-autosuggestions zsh-syntax-highlighting util-linux-user \
        fontconfig google-noto-sans-fonts unzip
    sudo dnf install -y --allowerasing nodejs24 nodejs24-npm nodejs24-bin nodejs24-npm-bin

    mkdir -p "$CACHE" "$LOCAL_BIN"
    install_librewolf
    install_command "$REPOSITORY/bin/swayidle_laptop.py" swayidle-laptop
    install_system_file "$REPOSITORY/systemd/logind/lid.conf" /etc/systemd/logind.conf.d/lid.conf
    install_system_file "$REPOSITORY/systemd/sleep/60-deep.conf" /etc/systemd/sleep.conf.d/60-deep.conf
    "$REPOSITORY/scripts/hardening.sh"

    local output
    output="$(swaymsg -r -t get_outputs | jq -re '
        [.[] | select(.active == true and (.name | test("^eDP-[0-9]+$"))) | .name]
        | if length == 1 then .[0] else error("expected one active eDP output") end
    ')" || { echo "bootstrap: нужен один активный eDP-экран; запусти из Sway" >&2; return 1; }

    set_output_name "$REPOSITORY" "$output"
    local name
    for name in sway/config sway/config.d/90-swayidle.conf sway/desktop.conf sway/output.conf \
        sway/background.conf swaylock/config foot/foot.ini rofi/config.rasi \
        waybar/config.jsonc waybar/style.css dunst/dunstrc \
        gtk-3.0/settings.ini gtk-4.0/settings.ini fontconfig/fonts.conf; do
        link_config "$REPOSITORY/$name" "$CONFIGURATION_HOME/$name"
    done
    link_config "$REPOSITORY/zshrc" "$HOME/.zshrc"
    link_config "$REPOSITORY/zprofile" "$HOME/.zprofile"
    link_config "$REPOSITORY/gitconfig" "$HOME/.gitconfig"
    link_config "$REPOSITORY/psqlrc" "$HOME/.psqlrc"

    sway -C -c "$CONFIGURATION_HOME/sway/config"
    foot --check-config --config="$CONFIGURATION_HOME/foot/foot.ini"
    rofi -config "$CONFIGURATION_HOME/rofi/config.rasi" -dump-theme >/dev/null
    swaymsg reload
    systemctl --user restart dunst.service

    install_command "$REPOSITORY/bin/credentials-setup.sh" credentials-setup
    install_command "$REPOSITORY/bin/git-crypt-repo.sh" git-crypt-repo
    install_command "$REPOSITORY/bin/git-crypt-repo.sh" git-crypt-textconv
    install_command "$REPOSITORY/bin/git-cred-read.sh" git-cred-read
    install_command "$REPOSITORY/bin/herdr-ws.sh" herdr-ws
    link_config "$LOCAL_BIN/git-crypt-repo" "$HOME/.local/share/git-crypt/hooks/pre-commit"
    link_config "$REPOSITORY/systemd/user/ssh-agent.service" "$CONFIGURATION_HOME/systemd/user/ssh-agent.service"
    systemctl --user daemon-reload
    systemctl --user enable --now ssh-agent.service

    install_mihomo
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
        "https://github.com/s3nn1k/librewolf-config.git|$HOME/projects/personal/librewolf-config"
    )
    for repository_entry in "${PERSONAL_REPOSITORIES[@]}"; do
        repository_url="${repository_entry%%|*}"
        destination="${repository_entry#*|}"
        clone_repository "$repository_url" "$destination"
    done
    install_librewolf_prefs
    install_librewolf_chrome
    install_librewolf_policies
    install_librewolf_autoconfig
    NKP="$HOME/projects/personal/nkp"
    make -C "$NKP" install

    download https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v31.9.1/posh-linux-amd64 \
        574074a4e84797180e0bda0d133da5f01fbda89ecdb450134c7e566b9a389212 "$CACHE/oh-my-posh"
    install -m 755 "$CACHE/oh-my-posh" "$HOME/.local/bin/oh-my-posh"

    download https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Hack.zip \
        fa24da7de7cefe7766614d27762570b20453c852fc1d5b657111666df9a5e449 "$CACHE/Hack.zip"
    mkdir -p "$HOME/.local/share/fonts/Hack"
    unzip -oq "$CACHE/Hack.zip" -d "$HOME/.local/share/fonts/Hack"
    fc-cache -f "$HOME/.local/share/fonts/Hack"

    download https://github.com/googlefonts/noto-emoji/raw/v2.047/fonts/NotoColorEmoji.ttf \
        39ee3c587e10e89669b9ff32703261d10d5f9c4dd5ad147b6b5a1c5200591817 "$CACHE/NotoColorEmoji.ttf"
    install -D -m 644 "$CACHE/NotoColorEmoji.ttf" "$HOME/.local/share/fonts/NotoColorEmoji/NotoColorEmoji.ttf"
    fc-cache -f "$HOME/.local/share/fonts/NotoColorEmoji"

    clone_repository https://github.com/s3nn1k/pi-agent.git "$HOME/.pi/agent"
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 19)) process.exit(1)'
    npm install --global --prefix "$HOME/.local" --ignore-scripts @earendil-works/pi-coding-agent@1.3.0
    make -C "$HOME/.pi/agent" init
    "$HOME/.local/bin/pi" update --extensions

    clone_repository https://github.com/s3nn1k/nvim.git "$CONFIGURATION_HOME/nvim"
    mkdir -p "$CONFIGURATION_HOME/omp"
    link_config "$REPOSITORY/omp/prompt.omp.json" "$CONFIGURATION_HOME/omp/prompt.omp.json"
    "$CONFIGURATION_HOME/nvim/init.sh"

    configure_grub
    sudo restorecon /etc/default/grub
    sudo grub2-editenv - list | grep -q menu_auto_hide && sudo grub2-editenv - unset menu_auto_hide
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg

    local shell
    shell="$(command -v zsh)"
    if [[ "$(getent passwd "$(id -un)" | cut -d: -f7)" != "$shell" ]]; then
        chsh -s "$shell"
    fi

    sudo dnf -y copr enable alternateved/keyd
    sudo dnf install -y keyd

    sudo "$HOME/projects/personal/keyd-cfqv8/apply.sh"
    "$HOME/projects/personal/keyd-cfqv8/scripts/xremap-apply.sh"

    if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
        DOCKER_REPO_FILE="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/docker-ce.repo.XXXXXX")"
        curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo -o "$DOCKER_REPO_FILE"
        sudo install -m 644 "$DOCKER_REPO_FILE" /etc/yum.repos.d/docker-ce.repo
        rm -f "$DOCKER_REPO_FILE"
    fi
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$(id -un)"

    sudo dnf install -y cmake ffmpeg-free yt-dlp
    install_whisper
    install_command "$REPOSITORY/bin/wt" wt

    install_herdr

    clone_repository https://github.com/s3nn1k/obsidian-config.git "$CONFIGURATION_HOME/obsidian"
    for vault_name in personal work; do
        VAULT="$HOME/vaults/$vault_name"
        mkdir -p "$(dirname "$VAULT")"
        clone_repository "https://github.com/s3nn1k/obsidian-$vault_name.git" "$VAULT"
    done
    "$REPOSITORY/scripts/setup-secrets.sh" link

    printf '%s\n' "Готово. Выйди из сессии и войди снова для zsh и группы docker." \
        "Дальше: открой nkp, достань ключи и запусти scripts/setup-secrets.sh unlock." \
        "LibreWolf-профили: после unlock запусти scripts/librewolf/profiles.sh reset, затем init (регистрация) и pull (закладки из ~/credentials/librewolf, профили появятся в панели LibreWolf)." \
        "VPN: смена подписки - ~/.config/mihomo/subscription-url + scripts/mihomo-apply.sh, панель http://127.0.0.1:9090/ui."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
