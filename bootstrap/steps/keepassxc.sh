# shellcheck shell=bash
run_keepassxc() {
    sudo dnf install -y keepassxc
    link_config "$REPOSITORY/keepassxc/keepassxc.ini" "$CONFIGURATION_HOME/keepassxc/keepassxc.ini"
    link_config "$REPOSITORY/keepassxc/keepassxc-local.ini" "$HOME/.local/state/keepassxc/keepassxc.ini"
}
