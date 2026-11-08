require_fedora() {
    local prefix="$1"
    [[ -f /etc/os-release ]] || { echo "$prefix: нет /etc/os-release" >&2; return 1; }
    . /etc/os-release
    [[ "${ID:-}" == fedora ]] || { echo "$prefix: требуется Fedora" >&2; return 1; }
}
