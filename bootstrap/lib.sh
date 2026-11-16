# shellcheck shell=bash
REPOSITORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
export GOBIN="$HOME/.local/bin"
# shellcheck disable=SC2034
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
    # shellcheck disable=SC1091
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

link_config() {
    local source="$1" destination="$2" extra_allowed="${3:-}"
    local resolved_source resolved_destination
    [[ -f "$source" || -d "$source" ]] || { echo "bootstrap: нет источника $source" >&2; return 1; }
    resolved_source="$(readlink -f "$source")" || {
        echo "bootstrap: не удалось разрешить источник $source" >&2
        return 1
    }
    if [[ -L "$destination" ]]; then
        if [[ ! -e "$destination" ]]; then
            rm "$destination"
        else
            resolved_destination="$(readlink -f "$destination")" || {
                echo "bootstrap: $destination неразрешимая ссылка; перенеси вручную и повтори" >&2
                return 1
            }
            [[ "$resolved_destination" == "$resolved_source" ]] && return
            # shellcheck disable=SC2053
            if [[ "$resolved_destination" == "$REPOSITORY"/* ]] ||
                { [[ -n "$extra_allowed" ]] && [[ "$resolved_destination" == $extra_allowed ]]; }; then
                rm "$destination"
            else
                echo "bootstrap: $destination не наш симлинк; перенеси вручную и повтори" >&2
                return 1
            fi
        fi
    elif [[ -e "$destination" ]]; then
        echo "bootstrap: $destination существует; перенеси вручную и повтори" >&2
        return 1
    fi
    mkdir -p "$(dirname "$destination")"
    ln -s "$resolved_source" "$destination"
}

validate_link_destination() {
    local source="$1" destination="$2"
    if [[ -L "$destination" ]]; then
        if [[ "$(readlink "$destination")" != "$source" ]]; then
            echo "bootstrap: refusing to replace existing symlink: $destination" >&2
            return 1
        fi
    elif [[ -e "$destination" ]]; then
        echo "bootstrap: refusing to replace existing path: $destination" >&2
        return 1
    fi
}

link_safely() {
    local source="$1" destination="$2"
    validate_link_destination "$source" "$destination" || return 1
    mkdir -p "$(dirname "$destination")"
    [[ -L "$destination" ]] || {
        ln -s "$source" "$destination"
        echo "linked: $destination -> $source"
    }
}

is_git_crypt_locked() {
    [[ -f "$1" ]] || return 1
    printf '\000GITCRYPT' | cmp -s - <(head -c 9 "$1")
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
