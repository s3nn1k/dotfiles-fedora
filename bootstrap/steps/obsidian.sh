run_obsidian() {
    OBSIDIAN_CONFIG="$CONFIGURATION_HOME/obsidian"
    clone_repository https://github.com/s3nn1k/obsidian-config.git "$OBSIDIAN_CONFIG"
    for vault_name in personal work; do
        VAULT="$HOME/vaults/$vault_name"
        mkdir -p "$(dirname "$VAULT")"
        clone_repository "https://github.com/s3nn1k/obsidian-$vault_name.git" "$VAULT"
    done

    link_safely "$OBSIDIAN_CONFIG" "$HOME/vaults/personal/.obsidian"
    link_safely "$OBSIDIAN_CONFIG" "$HOME/vaults/work/.obsidian"
}
