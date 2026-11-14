run_packages() {
    sudo dnf upgrade -y

    sudo dnf install -y git git-crypt gh glab curl jq make gcc gcc-c++ golang postgresql \
        python3 pipx uv neovim ripgrep fd-find wl-clipboard acl kubectl \
        zsh zsh-autosuggestions zsh-syntax-highlighting util-linux-user \
        fontconfig google-noto-sans-fonts unzip
    sudo dnf install -y --allowerasing nodejs24 nodejs24-npm nodejs24-bin nodejs24-npm-bin
}
