# shellcheck shell=bash
run_obsidian() {
    for vault_name in personal work; do
        VAULT="$HOME/vaults/$vault_name"
        mkdir -p "$(dirname "$VAULT")"
        clone_repository "https://github.com/s3nn1k/obsidian-$vault_name.git" "$VAULT"
    done
}
