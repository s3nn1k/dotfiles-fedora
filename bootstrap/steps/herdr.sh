# shellcheck shell=bash
install_herdr() {
    download https://github.com/herdrdev/herdr/releases/download/v0.9.5/herdr-linux-x86_64 \
        14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d "$CACHE/herdr"
    install -m 755 "$CACHE/herdr" "$LOCAL_BIN/herdr"
    herdr --version

    mkdir -p "$CONFIGURATION_HOME/herdr"
    link_config "$REPOSITORY/herdr/config.toml" "$CONFIGURATION_HOME/herdr/config.toml"

    herdr integration install pi >/dev/null 2>&1 || true
}

run_herdr() {
    install_herdr
    install_command "$REPOSITORY/herdr/bin/herdr-ws.sh" herdr-ws
    install_command "$REPOSITORY/herdr/bin/herdr-agent-rename.sh" herdr-agent-rename
}
