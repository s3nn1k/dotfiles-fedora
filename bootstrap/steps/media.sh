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

install_whisper() {
    local model="$HOME/.local/share/whisper/models/ggml-large-v3-turbo.bin"
    local source_directory="$CACHE/whisper.cpp-1.9.5" version_file="$LOCAL_BIN/whisper-cli.version"
    local installed_version=""

    download https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.5.tar.gz \
        ff1a9053feb509ff9d7729703355541ae9690073a6b1c40eb692c962e0dc1720 \
        "$CACHE/whisper.cpp-v1.9.5.tar.gz"

    [[ -f "$version_file" ]] && installed_version="$(cat "$version_file")"
    if [[ ! -x "$LOCAL_BIN/whisper-cli" || "$installed_version" != "v1.9.5" ]]; then
        rm -rf "$source_directory"
        tar -xzf "$CACHE/whisper.cpp-v1.9.5.tar.gz" -C "$CACHE"
        cmake -S "$source_directory" -B "$source_directory/build" -DBUILD_SHARED_LIBS=OFF
        cmake --build "$source_directory/build" --config Release -j"$(nproc)"
        install -m 755 "$source_directory/build/bin/whisper-cli" "$LOCAL_BIN/whisper-cli"
        printf 'v1.9.5\n' > "$version_file"
    fi

    mkdir -p "$(dirname "$model")"
    download_model https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin \
        1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69 "$model"
}

run_media() {
    install_mpd_mpris

    sudo dnf install -y mpd mpc
    install_rmpc
    mkdir -p "$HOME/Music" "$HOME/.local/share/mpd/playlists"
    systemctl --user enable --now mpd.service

    sudo dnf install -y cmake ffmpeg-free yt-dlp
    install_whisper
}
