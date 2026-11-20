# shellcheck shell=bash
run_projects() {
    sudo dnf install -y gcc gcc-c++ golang cmake

    mkdir -p "$HOME/projects/work"
    local repository_entry repository_url destination
    PERSONAL_REPOSITORIES=(
        "https://github.com/s3nn1k/nova-42|$HOME/projects/personal/nova-42"
        "https://github.com/s3nn1k/ci-cd.git|$HOME/projects/personal/ci-cd"
        "https://github.com/s3nn1k/go-service-template.git|$HOME/projects/personal/go-service-template"
        "https://github.com/s3nn1k/share.git|$HOME/vaults/share"
    )
    for repository_entry in "${PERSONAL_REPOSITORIES[@]}"; do
        repository_url="${repository_entry%%|*}"
        destination="${repository_entry#*|}"
        clone_repository "$repository_url" "$destination"
    done
}
