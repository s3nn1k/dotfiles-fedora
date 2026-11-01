#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
ALL_LANGPACKS="glibc-all-langpacks"
BLOCK_ORDER=(leftovers firmware guest-agents installer printing telemetry misc node24 langpacks finish)
export PATH="$HOME/.local/bin:$PATH"

print_usage() {
    echo "cleanup: использование: cleanup.sh [--dry-run]" >&2
}

parse_arguments() {
    if (( $# > 1 )); then
        print_usage
        return 1
    fi
    case "${1:-}" in
        "") ;;
        --dry-run) DRY_RUN=true ;;
        *) print_usage; return 1 ;;
    esac
}

require_fedora() {
    [[ -f /etc/os-release ]] || { echo "cleanup: нет /etc/os-release" >&2; return 1; }
    . /etc/os-release
    [[ "${ID:-}" == fedora ]] || { echo "cleanup: требуется Fedora" >&2; return 1; }
}

block_packages() {
    case "$1" in
        leftovers)
            printf '%s\n' qt6-qtwebengine python3-botocore webkit2gtk4.1 mercurial
            ;;
        firmware)
            printf '%s\n' \
                nvidia-gpu-firmware amd-gpu-firmware amd-ucode-firmware atheros-firmware \
                mt7xxx-firmware brcmfmac-firmware tiwilink-firmware libertas-firmware \
                iwlwifi-dvm-firmware b43-fwcutter b43-openfwwf realtek-firmware
            ;;
        guest-agents)
            printf '%s\n' hyperv-daemons open-vm-tools open-vm-tools-desktop \
                virtualbox-guest-additions qemu-guest-agent spice-vdagent spice-webdavd
            ;;
        installer)
            printf '%s\n' anaconda-core anaconda-tui anaconda-webui anaconda-install-env-deps \
                anaconda-live kdump-anaconda-addon libreport-anaconda livesys-scripts \
                isomd5sum mediawriter
            ;;
        printing)
            printf '%s\n' cups cups-browsed cups-filters cups-pk-helper hplip gutenprint \
                gutenprint-cups system-config-printer system-config-printer-udev bluez-cups \
                ghostscript
            ;;
        telemetry)
            printf '%s\n' abrt abrt-cli abrt-desktop setroubleshoot rsyslog \
                setroubleshoot-server setroubleshoot-plugins
            ;;
        misc)
            printf '%s\n' iscsi-initiator-utils nfs-utils dnsmasq words \
                minicom lrzsz
            ;;
        node24)
            printf '%s\n' nodejs22 nodejs22-bin nodejs22-libs nodejs22-npm nodejs22-npm-bin \
                nodejs22-full-i18n nodejs22-docs nodejs24-devel nodejs24-docs
            ;;
        *)
            echo "cleanup: неизвестный блок $1" >&2
            return 1
            ;;
    esac
}

installed_packages() {
    local package
    for package in "$@"; do
        if rpm -q "$package" >/dev/null 2>&1; then
            printf '%s\n' "$package"
        fi
    done
}

block_installed_packages() {
    local candidates_output
    candidates_output="$(block_packages "$1")" || return 1
    local -a candidates
    mapfile -t candidates <<<"$candidates_output"
    installed_packages "${candidates[@]}"
}

run_dnf() {
    local subcommand="$1"
    shift
    if [[ "$DRY_RUN" == true ]]; then
        sudo dnf "$subcommand" --assumeno "$@" || true
    else
        sudo dnf "$subcommand" -y "$@"
    fi
}

remove_block() {
    local block_name="$1"
    local installed_output
    installed_output="$(block_installed_packages "$block_name")" || return 1
    local -a installed=()
    if [[ -n "$installed_output" ]]; then
        mapfile -t installed <<<"$installed_output"
    fi
    if [[ "${#installed[@]}" == 0 ]]; then
        echo "cleanup: блок $block_name пропущен (установленных пакетов нет)"
        return 0
    fi
    echo "cleanup: блок $block_name"
    run_dnf remove "${installed[@]}"
}

migrate_node24() {
    if ! rpm -q nodejs24 >/dev/null 2>&1; then
        echo "cleanup: nodejs24 не установлен; поставь nodejs24 и повтори" >&2
        return 1
    fi
    echo "cleanup: блок node24"
    if ! rpm -q nodejs24-bin >/dev/null 2>&1 || ! rpm -q nodejs24-npm-bin >/dev/null 2>&1; then
        echo "cleanup: node24: ставлю nodejs24-bin и nodejs24-npm-bin с --allowerasing"
        run_dnf install --allowerasing nodejs24-bin nodejs24-npm-bin
        if [[ "$DRY_RUN" == true ]]; then
            echo "cleanup: dry-run: установка nodejs24-bin отклонена dnf"
        fi
    fi
    local obsolete_output
    obsolete_output="$(block_installed_packages node24)" || return 1
    local -a obsolete=()
    if [[ -n "$obsolete_output" ]]; then
        mapfile -t obsolete <<<"$obsolete_output"
    fi
    if [[ "${#obsolete[@]}" == 0 ]]; then
        echo "cleanup: блок node24 пропущен (устаревших пакетов нет)"
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        echo "cleanup: dry-run: remove-транзакция node24 не превьюируется (после отклонённого install показала бы каскад nodejs24-семьи, которого в реальном прогоне нет)"
        return 0
    fi
    run_dnf remove "${obsolete[@]}"
    local node_version npm_version
    node_version="$(node -v)" || {
        echo "cleanup: node недоступен после миграции" >&2
        return 1
    }
    [[ "$node_version" == v24.* ]] || {
        echo "cleanup: node -v показывает $node_version, ожидался v24" >&2
        return 1
    }
    npm_version="$(npm -v)" || {
        echo "cleanup: npm недоступен после миграции" >&2
        return 1
    }
    [[ "$npm_version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || {
        echo "cleanup: npm -v показывает $npm_version, ожидался номер версии" >&2
        return 1
    }
    if command -v pi >/dev/null 2>&1; then
        pi --version >/dev/null 2>&1 || {
            echo "cleanup: pi --version упал после миграции" >&2
            return 1
        }
    fi
    echo "cleanup: Node.js 24 активна: node $node_version, npm $npm_version"
}

trim_langpacks() {
    if ! rpm -q "$ALL_LANGPACKS" >/dev/null 2>&1; then
        echo "cleanup: блок langpacks пропущен ($ALL_LANGPACKS не установлен)"
        return 0
    fi
    echo "cleanup: блок langpacks"
    run_dnf install glibc-langpack-en glibc-langpack-ru
    run_dnf remove "$ALL_LANGPACKS"
}

finish_cleanup() {
    echo "cleanup: блок finish"
    run_dnf autoremove
    if [[ "$DRY_RUN" == true ]]; then
        echo "cleanup: dry-run: dnf clean all и rm -rf ~/.cache/libdnf5 пропущены"
        return 0
    fi
    run_dnf clean all
    rm -rf "$HOME/.cache/libdnf5"
}

root_available_bytes() {
    LC_ALL=C df --output=avail -B1 / | awk 'NR == 2 { print $1 }'
}

show_plan() {
    local block_name installed_output
    local -a installed
    echo "cleanup: план (найдено установленных пакетов к удалению):"
    for block_name in "${BLOCK_ORDER[@]}"; do
        case "$block_name" in
            langpacks)
                if rpm -q "$ALL_LANGPACKS" >/dev/null 2>&1; then
                    printf '  %-13s %s\n' "$block_name" 1
                else
                    printf '  %-13s %s\n' "$block_name" 0
                fi
                ;;
            finish)
                printf '  %-13s %s\n' "$block_name" "dnf autoremove + dnf clean all + ~/.cache/libdnf5"
                ;;
            *)
                installed_output="$(block_installed_packages "$block_name")" || return 1
                installed=()
                if [[ -n "$installed_output" ]]; then
                    mapfile -t installed <<<"$installed_output"
                fi
                printf '  %-13s %s\n' "$block_name" "${#installed[@]}"
                ;;
        esac
    done
}

confirm_plan() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "cleanup: dry-run: подтверждение не требуется"
        return 0
    fi
    local reply
    read -r -p "Продолжить? [y/N] " reply || {
        echo
        echo "cleanup: отменено"
        return 1
    }
    case "$reply" in
        y|Y|yes|Yes|YES) return 0 ;;
        *) ;;
    esac
    echo "cleanup: отменено"
    return 1
}

run_blocks() {
    local block_name
    for block_name in "${BLOCK_ORDER[@]}"; do
        case "$block_name" in
            node24) migrate_node24 ;;
            langpacks) trim_langpacks ;;
            finish) finish_cleanup ;;
            *) remove_block "$block_name" ;;
        esac
    done
}

main() {
    parse_arguments "$@"
    require_fedora
    sudo -v
    local available_before available_after freed_bytes
    available_before="$(root_available_bytes)"
    show_plan
    confirm_plan || exit 0
    run_blocks
    available_after="$(root_available_bytes)"
    freed_bytes=$((available_after - available_before))
    echo "cleanup: / доступно: $(numfmt --to=iec -- "$available_before") -> $(numfmt --to=iec -- "$available_after")"
    echo "cleanup: освобождено $(numfmt --to=iec -- "$freed_bytes")"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
