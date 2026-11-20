# shellcheck shell=bash
run_keepassxc() {
    sudo dnf install -y keepassxc
    link_config "$REPOSITORY/keepassxc/keepassxc.ini" "$CONFIGURATION_HOME/keepassxc/keepassxc.ini"
}
