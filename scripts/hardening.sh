#!/usr/bin/env bash
set -euo pipefail

STAGING_FILE=""
require_fedora() {
    [[ -f /etc/os-release ]] || { echo "hardening: нет /etc/os-release" >&2; return 1; }
    . /etc/os-release
    [[ "${ID:-}" == fedora ]] || { echo "hardening: требуется Fedora" >&2; return 1; }
}
install_root_file_if_changed() {
    local destination="$1"
    sudo install -d -m 755 "$(dirname "$destination")"
    cat > "$STAGING_FILE"
    sudo cmp -s "$STAGING_FILE" "$destination" && return 1
    sudo install -m 644 "$STAGING_FILE" "$destination"
}
apply_sysctl() {
    if install_root_file_if_changed "/etc/sysctl.d/99-hardening.conf" <<'EOF'
# Sysctl security-hardening; применяется scripts/hardening.sh
# Network
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
# Kernel
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.perf_event_paranoid = 3
kernel.kexec_load_disabled = 1
kernel.sysrq = 4
kernel.dmesg_restrict = 1
# Filesystem
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0
EOF
    then
        sudo sysctl --system >/dev/null
        echo "hardening: sysctl применён: ptrace_scope=$(sysctl -n kernel.yama.ptrace_scope) kptr_restrict=$(sysctl -n kernel.kptr_restrict) perf_event_paranoid=$(sysctl -n kernel.perf_event_paranoid)"
    fi
}
disable_llmnr() {
    if install_root_file_if_changed "/etc/systemd/resolved.conf.d/50-no-llmnr.conf" <<'EOF'
[Resolve]
LLMNR=no
EOF
    then
        sudo systemctl restart systemd-resolved
        echo "hardening: LLMNR отключён, systemd-resolved перезапущен"
    fi
}
mask_avahi() {
    local service_state socket_state
    service_state="$(systemctl is-enabled avahi-daemon.service 2>/dev/null || true)"
    socket_state="$(systemctl is-enabled avahi-daemon.socket 2>/dev/null || true)"
    if [[ "$service_state" == masked && "$socket_state" == masked ]] ||
        [[ "$service_state" == not-found && "$socket_state" == not-found ]]; then
        return 0
    fi
    sudo systemctl mask --now avahi-daemon.service avahi-daemon.socket
    echo "hardening: avahi замаскирован и остановлен"
}
trim_firewall_zone() {
    local service query_exit removed=()
    for service in ssh mdns; do
        query_exit=0
        sudo firewall-cmd --permanent --query-service="$service" >/dev/null 2>&1 || query_exit=$?
        case "$query_exit" in
            0)
                sudo firewall-cmd --permanent --remove-service="$service" >/dev/null
                removed+=("$service")
                ;;
            1) ;;
            *)
                echo "hardening: firewalld недоступен (exit $query_exit); срез $service прерван" >&2
                return 1
                ;;
        esac
    done
    if ((${#removed[@]} == 0)); then
        return 0
    fi
    sudo firewall-cmd --reload >/dev/null
    echo "hardening: firewall default-зона: убраны ${removed[*]}"
}
enable_security_updates() {
    local installed=false config_written=false
    if ! rpm -q dnf5-plugin-automatic >/dev/null 2>&1; then
        sudo dnf install -y dnf5-plugin-automatic >/dev/null
        installed=true
    fi
    if install_root_file_if_changed "/etc/dnf/automatic.conf" <<'EOF'
[commands]
upgrade_type = security
download_updates = yes
apply_updates = yes
reboot = never

[emitters]
emit_via = stdio
EOF
    then
        config_written=true
    fi
    sudo systemctl enable --now dnf5-automatic.timer >/dev/null
    if [[ "$installed" == true || "$config_written" == true ]]; then
        echo "hardening: автообновления безопасности включены (dnf5-automatic.timer)"
    fi
}
main() {
    require_fedora
    sudo -v
    STAGING_FILE="$(mktemp "${TMPDIR:-/tmp}/dotfiles-fedora-hardening.XXXXXX")"
    trap 'rm -f "$STAGING_FILE"' EXIT
    apply_sysctl
    disable_llmnr
    mask_avahi
    trim_firewall_zone
    enable_security_updates
    echo "hardening: готово"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
