# shellcheck shell=bash
run_media() {
    mkdir -p "$HOME/Music"

    sudo dnf install -y ffmpeg-free yt-dlp
}
