run_base() {
    sudo dnf upgrade -y

    sudo dnf install -y curl jq make postgresql python3 pipx uv ripgrep fd-find wl-clipboard acl kubectl \
        util-linux-user fontconfig google-noto-sans-fonts unzip
    sudo dnf install -y --allowerasing nodejs24 nodejs24-npm nodejs24-bin nodejs24-npm-bin
}
