run_docker() {
    if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
        DOCKER_REPO_FILE="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/docker-ce.repo.XXXXXX")"
        curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo -o "$DOCKER_REPO_FILE"
        sudo install -m 644 "$DOCKER_REPO_FILE" /etc/yum.repos.d/docker-ce.repo
        rm -f "$DOCKER_REPO_FILE"
    fi
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$(id -un)"
}
