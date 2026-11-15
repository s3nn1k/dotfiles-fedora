run_keyboard() {
    clone_repository https://github.com/s3nn1k/keyd-cfqv8.git "$HOME/projects/personal/keyd-cfqv8"

    sudo dnf -y copr enable alternateved/keyd
    sudo dnf install -y keyd

    sudo "$HOME/projects/personal/keyd-cfqv8/apply.sh"
    "$HOME/projects/personal/keyd-cfqv8/scripts/xremap-apply.sh"
}
