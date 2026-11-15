# shellcheck shell=bash
install_mpd_mpris() {
    local archive="$CACHE/mpd-mpris_0.4.4_linux_amd64.tar.gz"
    if [[ ! -x "$LOCAL_BIN/mpd-mpris" ]]; then
        download https://github.com/natsukagami/mpd-mpris/releases/download/v0.4.4/mpd-mpris_0.4.4_linux_amd64.tar.gz \
            33f0a3322267f23ea5ac4ee9b5248894e0ad52410e0c2b3c9302effbcb3c5d57 "$archive"
        tar -xzf "$archive" -C "$CACHE" mpd-mpris
        install -m 755 "$CACHE/mpd-mpris" "$LOCAL_BIN/mpd-mpris"
    fi
    link_config "$REPOSITORY/systemd/user/mpd-mpris.service" "$CONFIGURATION_HOME/systemd/user/mpd-mpris.service"
    systemctl --user daemon-reload
    systemctl --user enable --now mpd-mpris.service
}

install_rmpc() {
    download https://github.com/mierak/rmpc/releases/download/v0.11.0/rmpc-v0.11.0-x86_64-unknown-linux-gnu.tar.gz \
        b03d4b777cf0afe61107abb4ee847b7c6539b8f5c76555fd759cd15a6c1ff604 "$CACHE/rmpc.tar.gz"
    rm -rf "$CACHE/rmpc-extract"
    mkdir -p "$CACHE/rmpc-extract"
    tar -xzf "$CACHE/rmpc.tar.gz" -C "$CACHE/rmpc-extract"
    install -m 755 "$CACHE/rmpc-extract/rmpc" "$LOCAL_BIN/rmpc"
}

run_media() {
    install_mpd_mpris

    sudo dnf install -y mpd mpc
    install_rmpc
    mkdir -p "$HOME/Music" "$HOME/.local/share/mpd/playlists"
    systemctl --user enable --now mpd.service

    sudo dnf install -y ffmpeg-free yt-dlp
}
