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
    cat > "$STAGING_FILE"
    sudo install -d -m 755 "$(dirname "$destination")" < /dev/null
    sudo cmp -s "$STAGING_FILE" "$destination" < /dev/null && return 1
    sudo install -m 644 "$STAGING_FILE" "$destination" < /dev/null
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
enable_deny_ptrace() {
    [[ "$(getsebool deny_ptrace 2>/dev/null)" == *"--> on"* ]] && return 0
    sudo setsebool -P deny_ptrace on
    echo "hardening: SELinux deny_ptrace включён"
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
configure_authselect() {
    local -a profile=(local with-faillock with-pwhistory without-nullok with-silent-lastlog with-mdns4 with-fingerprint)
    local applied current feature
    current="$(authselect current 2>/dev/null || true)"
    for feature in with-faillock with-pwhistory without-nullok; do
        if [[ "$current" != *"$feature"* ]]; then
            sudo authselect select "${profile[@]}" --force >/dev/null
            applied="$(authselect current | tr '\n' ' ')"
            echo "hardening: authselect применён: $applied"
            return 0
        fi
    done
}
configure_faillock() {
    if install_root_file_if_changed "/etc/security/faillock.conf" <<'EOF'
deny = 3
fail_interval = 900
unlock_time = 300
silent
audit
EOF
    then
        echo "hardening: faillock настроен: /etc/security/faillock.conf"
    fi
}
configure_pwquality() {
    if install_root_file_if_changed "/etc/security/pwquality.conf" <<'EOF'
minlen = 14
minclass = 4
maxrepeat = 3
maxsequence = 3
difok = 8
dictcheck = 1
enforcing = 1
enforce_for_root
EOF
    then
        echo "hardening: pwquality настроен: /etc/security/pwquality.conf"
    fi
}
configure_pwhistory() {
    if install_root_file_if_changed "/etc/security/pwhistory.conf" <<'EOF'
remember = 24
enforce_for_root
EOF
    then
        echo "hardening: pwhistory настроен: /etc/security/pwhistory.conf"
    fi
}
configure_sudo() {
    local sudoers="/etc/sudoers.d/50-hardening" staged="/etc/sudoers.d/50-hardening.new"
    cat > "$STAGING_FILE" <<'EOF'
Defaults log_input, log_output
Defaults iolog_dir=/var/log/sudo-io/%{user}
Defaults logfile=/var/log/sudo.log
Defaults log_exit_status
Defaults use_pty
Defaults timestamp_timeout=5
EOF
    if sudo cmp -s "$STAGING_FILE" "$sudoers"; then
        return 0
    fi
    sudo install -d -m 755 "$(dirname "$sudoers")"
    sudo install -m 440 "$STAGING_FILE" "$staged"
    if ! sudo visudo -cf "$staged" >/dev/null; then
        sudo rm -f "$staged"
        echo "hardening: visudo отклонил $staged; файл удалён" >&2
        return 1
    fi
    sudo mv "$staged" "$sudoers"
    echo "hardening: sudo-логи включены: $sudoers прошёл visudo (0440)"
}
configure_dnf_and_banners() {
    local dnf_conf="/etc/dnf/dnf.conf" grep_exit=0 matched normalized
    local -a appended=()
    local key
    [[ -f "$dnf_conf" ]] || { echo "hardening: нет $dnf_conf" >&2; return 1; }
    for key in gpgcheck localpkg_gpgcheck; do
        grep_exit=0
        matched="$(sudo grep -E "^[[:space:]]*${key}[[:space:]]*=" "$dnf_conf")" || grep_exit=$?
        case "$grep_exit" in
            1)
                printf '%s\n' "$key=1" | sudo tee -a "$dnf_conf" >/dev/null
                appended+=("$key")
                ;;
            0)
                normalized="${matched//[[:space:]]/}"
                [[ "$normalized" == "$key=1" ]] || {
                    matched="${matched//$'\n'/; }"
                    echo "hardening: $dnf_conf содержит '$matched', ожидалось '$key=1'; исправь вручную и перезапусти" >&2
                    return 1
                }
                ;;
            *)
                echo "hardening: grep упал на $dnf_conf (exit $grep_exit), проверка $key прервана" >&2
                return 1
                ;;
        esac
    done
    if ((${#appended[@]} > 0)); then
        echo "hardening: $dnf_conf дополнен: ${appended[*]}"
    fi
    if install_root_file_if_changed "/etc/issue" <<'EOF'
Authorized users only. All activity is logged.
EOF
    then
        echo "hardening: баннер /etc/issue обновлён"
    fi
    if install_root_file_if_changed "/etc/issue.net" <<'EOF'
Authorized users only. All activity is logged.
EOF
    then
        echo "hardening: баннер /etc/issue.net обновлён"
    fi
}
configure_auditd() {
    local installed=false rules_replaced=false rules_written=false readback
    if ! rpm -q audit-rules >/dev/null 2>&1; then
        sudo dnf install -y audit-rules >/dev/null
        installed=true
    fi
    if sudo test -f /etc/audit/rules.d/audit.rules &&
        sudo grep -q '^-a task,never' /etc/audit/rules.d/audit.rules; then
        [[ -f /usr/share/audit-rules/10-base-config.rules ]] || {
            echo "hardening: нет /usr/share/audit-rules/10-base-config.rules; замена мёртвых audit-правил прервана" >&2
            return 1
        }
        sudo rm /etc/audit/rules.d/audit.rules
        sudo cp /usr/share/audit-rules/10-base-config.rules /etc/audit/rules.d/
        rules_replaced=true
    fi
    if install_root_file_if_changed "/etc/audit/rules.d/50-hardening.rules" <<'EOF'
## Identity and privilege files
-a always,exit -F arch=b64 -F path=/etc/passwd -F perm=wa -k identity
-a always,exit -F arch=b64 -F path=/etc/shadow -F perm=wa -k identity
-a always,exit -F arch=b64 -F path=/etc/group -F perm=wa -k identity
-a always,exit -F arch=b64 -F path=/etc/gshadow -F perm=wa -k identity
-a always,exit -F arch=b64 -F path=/etc/sudoers -F perm=wa -k actions
-a always,exit -F arch=b64 -F dir=/etc/sudoers.d/ -F perm=wa -k actions
-a always,exit -F arch=b64 -F path=/etc/ssh/sshd_config -F perm=wa -k sshd_config
-a always,exit -F arch=b64 -F dir=/etc/ssh/sshd_config.d/ -F perm=wa -k sshd_config
-a always,exit -F arch=b64 -F dir=/etc/selinux/ -F perm=wa -k selinux_config
## User and group management
-a always,exit -F arch=b64 -F path=/usr/sbin/useradd -F perm=x -k user_mgmt
-a always,exit -F arch=b64 -F path=/usr/sbin/userdel -F perm=x -k user_mgmt
-a always,exit -F arch=b64 -F path=/usr/sbin/usermod -F perm=x -k user_mgmt
-a always,exit -F arch=b64 -F path=/usr/bin/passwd -F perm=x -k user_mgmt
## Time changes
-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time_change
## Mounts by real users
-a always,exit -F arch=b64 -S mount,umount2 -F auid>=1000 -F auid!=unset -k mount
## Denied file access by real users
-a always,exit -F arch=b64 -S openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k unauthed_access
-a always,exit -F arch=b64 -S openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -k unauthed_access
## Kernel module load and unload
-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k module_load
EOF
    then
        rules_written=true
    fi
    if [[ "$installed" == true || "$rules_replaced" == true || "$rules_written" == true ]]; then
        sudo augenrules --load >/dev/null
        readback="$(sudo auditctl -l 2>/dev/null | head -1 || true)"
        if [[ -z "$readback" || "$readback" == "-a never,task" ]]; then
            if [[ -z "$readback" ]]; then
                echo "hardening: auditctl -l недоступен или аудит выключен в ядре; readback правил не удался" >&2
            else
                echo "hardening: auditctl -l показывает '-a never,task'; правила auditd не загрузились" >&2
            fi
            return 1
        fi
        sudo systemctl enable auditd >/dev/null
        echo "hardening: auditd: правила загружены (50-hardening.rules)"
    fi
}
ensure_fstab_backup() {
    if [[ ! -e /etc/fstab.hardening.bak ]]; then
        sudo cp /etc/fstab /etc/fstab.hardening.bak
    fi
}
harden_mounts() {
    local fstab="/etc/fstab"
    local boot_match home_match boot_line_no boot_options home_line_no home_options shm_present
    local boot_changed=false home_changed=false shm_changed=false
    local -a applied=()
    boot_match="$(awk '$1 !~ /^#/ && $2 == "/boot" { print NR, $4; exit }' "$fstab")"
    home_match="$(awk '$1 !~ /^#/ && $2 == "/home" { print NR, $4; exit }' "$fstab")"
    shm_present="$(awk '$1 !~ /^#/ && $2 == "/dev/shm" { print NR; exit }' "$fstab")"
    boot_line_no="${boot_match%% *}"
    boot_options="${boot_match#* }"
    home_line_no="${home_match%% *}"
    home_options="${home_match#* }"
    if [[ -n "$boot_options" && "$boot_options" != *noexec* ]]; then
        ensure_fstab_backup
        sudo sed -i -E "${boot_line_no}"'s/^([^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+)([[:space:]])/\1,nodev,nosuid,noexec\2/' "$fstab"
        applied+=("/boot +nodev,nosuid,noexec")
        boot_changed=true
    fi
    if [[ -n "$home_options" && ( "$home_options" != *nodev* || "$home_options" != *nosuid* ) ]]; then
        ensure_fstab_backup
        sudo sed -i -E "${home_line_no}"'s/^([^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+)([[:space:]])/\1,nodev,nosuid\2/' "$fstab"
        applied+=("/home +nodev,nosuid")
        home_changed=true
    fi
    if [[ -z "$shm_present" ]]; then
        ensure_fstab_backup
        printf '%s\n' 'tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec 0 0' | sudo tee -a "$fstab" >/dev/null
        applied+=("/dev/shm +defaults,nodev,nosuid,noexec")
        shm_changed=true
    fi
    if [[ "$boot_changed" == true || "$home_changed" == true || "$shm_changed" == true ]]; then
        if ! sudo findmnt --verify >/dev/null; then
            echo "hardening: findmnt --verify отклонил $fstab; восстанови из /etc/fstab.hardening.bak и исправь вручную" >&2
            return 1
        fi
        if [[ "$boot_changed" == true ]]; then
            sudo mount -o remount /boot
        fi
        if [[ "$home_changed" == true ]]; then
            sudo mount -o remount /home
        fi
        if [[ "$shm_changed" == true ]]; then
            sudo mount -o remount /dev/shm
        fi
    fi
    if install_root_file_if_changed "/etc/systemd/system/tmp.mount.d/50-hardening.conf" <<'EOF'
[Mount]
Options=mode=1777,strictatime,nosuid,nodev,noexec,size=50%%,nr_inodes=1m,x-systemd.graceful-option=usrquota
EOF
    then
        sudo systemctl daemon-reload
        applied+=("/tmp tmp.mount drop-in noexec")
        if ! sudo systemctl restart tmp.mount 2>/dev/null; then
            echo "hardening: /tmp занят, noexec применится после перезагрузки" >&2
        fi
    fi
    if ((${#applied[@]} > 0)); then
        echo "hardening: mount-флаги: ${applied[*]}"
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
    enable_deny_ptrace
    trim_firewall_zone
    enable_security_updates
    configure_authselect
    configure_faillock
    configure_pwquality
    configure_pwhistory
    configure_sudo
    configure_dnf_and_banners
    configure_auditd
    harden_mounts
    echo "hardening: вручную (один раз): sudo grub2-setpassword - пароль GRUB-меню от несанкционированного редактирования"
    echo "hardening: готово"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
