#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPOSITORY/scripts/bootstrap.sh"

die() {
    printf 'xremap-apply: %s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_host() {
    [[ "$EUID" != 0 ]] || die "run as the normal user, not root"
    [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] ||
        die "requires Fedora x86_64 Linux; do not run this installer on macOS"
    [[ -r /etc/os-release ]] || die "cannot identify Fedora"
    . /etc/os-release
    [[ "$ID" == fedora ]] || die "requires Fedora"
    [[ "$CONFIGURATION_HOME" == /* ]] || die "XDG_CONFIG_HOME must be an absolute path"
    [[ -n "${WAYLAND_DISPLAY:-}" && -n "${SWAYSOCK:-}" && -n "${XDG_CURRENT_DESKTOP:-}" ]] ||
        die "run from an active Sway session with Wayland, SWAYSOCK, and XDG_CURRENT_DESKTOP"
    swaymsg -r -t get_tree >/dev/null ||
        die "Sway is not reachable; run this from the active Sway session"
}

preflight_link() {
    local source="$1" destination="$2"
    [[ -f "$source" ]] || die "missing repository file: $source"
    if [[ -L "$destination" ]]; then
        [[ "$(readlink -f -- "$destination")" == "$(readlink -f -- "$source")" ]] ||
            die "foreign symlink exists: $destination"
    elif [[ -e "$destination" ]]; then
        die "foreign path exists: $destination"
    fi
}

link_source() {
    local source="$1" destination="$2"
    [[ -L "$destination" ]] && return
    mkdir -p "$(dirname "$destination")"
    ln -s -- "$source" "$destination"
}

preflight_system_copy() {
    local source="$1" destination="$2"
    if sudo test -L "$destination"; then
        die "foreign system symlink exists: $destination"
    fi
    if sudo test -e "$destination"; then
        if ! sudo test -f "$destination" || ! sudo cmp -s "$source" "$destination"; then
            die "foreign system file exists: $destination"
        fi
    fi
}

install_system_copy() {
    local source="$1" destination="$2"
    sudo test -e "$destination" || sudo install -m 644 "$source" "$destination"
}

find_keyd_events() {
    local event_path event_syspath
    KEYD_EVENT_DEVICES=()
    KEYD_EVENT_SYSPATHS=()
    for event_path in /sys/class/input/event*; do
        [[ -r "$event_path/device/name" ]] || continue
        [[ "$(<"$event_path/device/name")" == "$KEYD_DEVICE_NAME" ]] || continue
        event_syspath="$(readlink -f -- "$event_path")"
        KEYD_EVENT_DEVICES+=("/dev/input/${event_path##*/}")
        KEYD_EVENT_SYSPATHS+=("$event_syspath")
    done
    ((${#KEYD_EVENT_DEVICES[@]} > 0))
}

check_access() {
    local device="$1" required="$2" acl_output
    [[ -r "$device" ]] || die "uaccess ACL did not grant read access to $device"
    [[ "$required" != write || -w "$device" ]] ||
        die "uaccess ACL did not grant write access to $device"
    acl_output="$(getfacl -n -c -p -- "$device")" ||
        die "cannot read the ACL for $device"
    printf '%s\n' "$acl_output" | awk -F: -v uid="$CURRENT_UID" -v required="$required" '
        $1 == "user" && $2 == uid {
            if (required == "read" && substr($3, 1, 1) == "r") found = 1
            if (required == "write" && substr($3, 2, 1) == "w") found = 1
        }
        END { exit(found ? 0 : 1) }
    ' || die "named uaccess ACL for uid $CURRENT_UID is missing on $device"
}

require_host
for command_name in awk cmp curl getfacl grep id install ln modprobe sudo swaymsg systemctl unzip udevadm; do
    require_command "$command_name"
done

CONFIGURATION_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_DIRECTORY="$CACHE/xremap"
ZIP_PATH="$CACHE_DIRECTORY/xremap-linux-x86_64-wlroots.zip"
STAGED_BINARY="$CACHE_DIRECTORY/xremap"
XREMAP_BINARY="$HOME/.local/bin/xremap"
KEYD_DEVICE_NAME="keyd virtual keyboard"
DOWNLOAD_URL="https://github.com/xremap/xremap/releases/download/v0.15.16/xremap-linux-x86_64-wlroots.zip"
DOWNLOAD_SHA256="9e8e3eb56423b06607c507788eef2100f9dfd241da58988d69e8a6fdbae4482b"
KEYD_EVENT_DEVICES=()
KEYD_EVENT_SYSPATHS=()
CURRENT_UID="$(id -u)"

find_keyd_events || die "keyd virtual keyboard was not found"
preflight_link "$REPOSITORY/xremap/config.yml" "$CONFIGURATION_HOME/xremap/config.yml"
preflight_link "$REPOSITORY/xremap/xremap.service" "$CONFIGURATION_HOME/systemd/user/xremap.service"
sudo -v
preflight_system_copy "$REPOSITORY/xremap/70-xremap.rules" /etc/udev/rules.d/70-xremap.rules
preflight_system_copy "$REPOSITORY/xremap/uinput.conf" /etc/modules-load.d/uinput.conf

mkdir -p "$CACHE_DIRECTORY"
download "$DOWNLOAD_URL" "$DOWNLOAD_SHA256" "$ZIP_PATH"
unzip -Z1 "$ZIP_PATH" | grep -Fxq xremap ||
    die "the pinned archive does not contain the expected xremap binary"
unzip -p "$ZIP_PATH" xremap > "$STAGED_BINARY.part"
mv "$STAGED_BINARY.part" "$STAGED_BINARY"
chmod 755 "$STAGED_BINARY"

if [[ -L "$XREMAP_BINARY" ]]; then
    die "foreign binary symlink exists: $XREMAP_BINARY"
elif [[ -e "$XREMAP_BINARY" ]]; then
    cmp -s "$STAGED_BINARY" "$XREMAP_BINARY" ||
        die "foreign binary exists: $XREMAP_BINARY"
else
    install -D -m 755 "$STAGED_BINARY" "$XREMAP_BINARY"
fi

link_source "$REPOSITORY/xremap/config.yml" "$CONFIGURATION_HOME/xremap/config.yml"
link_source "$REPOSITORY/xremap/xremap.service" "$CONFIGURATION_HOME/systemd/user/xremap.service"
install_system_copy "$REPOSITORY/xremap/70-xremap.rules" /etc/udev/rules.d/70-xremap.rules
install_system_copy "$REPOSITORY/xremap/uinput.conf" /etc/modules-load.d/uinput.conf

sudo modprobe uinput
sudo udevadm control --reload-rules
UINPUT_SYSPATH="$(udevadm info --query=syspath --name=/dev/uinput)" ||
    die "udev cannot resolve /dev/uinput"
sudo udevadm trigger --action=change "$UINPUT_SYSPATH"
for event_syspath in "${KEYD_EVENT_SYSPATHS[@]}"; do
    sudo udevadm trigger --action=change "$event_syspath"
done
sudo udevadm settle --timeout=10

check_access /dev/uinput write
for event_device in "${KEYD_EVENT_DEVICES[@]}"; do
    check_access "$event_device" read
done
"$XREMAP_BINARY" --desktop wlroots --validate-config "$CONFIGURATION_HOME/xremap/config.yml" ||
    die "xremap rejected the configuration"
"$XREMAP_BINARY" --desktop wlroots --list-windows >/dev/null ||
    die "wlroots app detection is unavailable; refusing to start the foot-specific trial"

systemctl --user import-environment WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_CONFIG_HOME
systemctl --user daemon-reload
systemctl --user start xremap.service
printf '%s\n' "xremap trial started; verify global, foot, footclient, Shift+Super+C, US/RU, and keyd restart."
