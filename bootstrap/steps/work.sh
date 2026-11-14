install_herdr() {
    download https://github.com/herdrdev/herdr/releases/download/v0.9.5/herdr-linux-x86_64 \
        14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d "$CACHE/herdr"
    install -m 755 "$CACHE/herdr" "$LOCAL_BIN/herdr"
    herdr --version

    mkdir -p "$CONFIGURATION_HOME/herdr"
    link_config "$REPOSITORY/herdr/config.toml" "$CONFIGURATION_HOME/herdr/config.toml"

    herdr integration install pi >/dev/null 2>&1 || true
}

run_work() {
    CREDENTIALS="$HOME/credentials"
    clone_repository https://github.com/s3nn1k/credentials.git "$CREDENTIALS"

    mkdir -p "$HOME/projects/work"
    local repository_entry repository_url destination
    PERSONAL_REPOSITORIES=(
        "https://github.com/s3nn1k/nova-42|$HOME/projects/personal/nova-42"
        "https://github.com/s3nn1k/ci-cd.git|$HOME/projects/personal/ci-cd"
        "https://github.com/s3nn1k/go-service-template.git|$HOME/projects/personal/go-service-template"
        "https://github.com/s3nn1k/nkp.git|$HOME/projects/personal/nkp"
        "https://github.com/s3nn1k/keyd-cfqv8.git|$HOME/projects/personal/keyd-cfqv8"
        "https://github.com/s3nn1k/librewolf-config.git|$HOME/projects/personal/librewolf-config"
    )
    for repository_entry in "${PERSONAL_REPOSITORIES[@]}"; do
        repository_url="${repository_entry%%|*}"
        destination="${repository_entry#*|}"
        clone_repository "$repository_url" "$destination"
    done

    NKP="$HOME/projects/personal/nkp"
    make -C "$NKP" install

    clone_repository https://github.com/s3nn1k/pi-agent.git "$HOME/.pi/agent"
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 19)) process.exit(1)'
    npm install --global --prefix "$HOME/.local" --ignore-scripts @earendil-works/pi-coding-agent@1.3.0
    make -C "$HOME/.pi/agent" init
    "$HOME/.local/bin/pi" update --extensions

    clone_repository https://github.com/s3nn1k/nvim.git "$CONFIGURATION_HOME/nvim"
    mkdir -p "$CONFIGURATION_HOME/omp"
    link_config "$REPOSITORY/omp/prompt.omp.json" "$CONFIGURATION_HOME/omp/prompt.omp.json"
    "$CONFIGURATION_HOME/nvim/init.sh"

    sudo "$HOME/projects/personal/keyd-cfqv8/apply.sh"
    "$HOME/projects/personal/keyd-cfqv8/scripts/xremap-apply.sh"

    install_herdr

    clone_repository https://github.com/s3nn1k/obsidian-config.git "$CONFIGURATION_HOME/obsidian"
    for vault_name in personal work; do
        VAULT="$HOME/vaults/$vault_name"
        mkdir -p "$(dirname "$VAULT")"
        clone_repository "https://github.com/s3nn1k/obsidian-$vault_name.git" "$VAULT"
    done
    "$REPOSITORY/scripts/setup-secrets.sh" link
}
