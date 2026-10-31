#!/usr/bin/env bash
# Unlock or link cloned git-crypt repositories and wire their runtime links.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

CONFIGURATION_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
RUNTIME_GITCONFIG="$HOME/.config/git/credentials.gitconfig"
OBSIDIAN_CONFIG="$CONFIGURATION_HOME/obsidian"
REPOSITORIES=(
    "$HOME/credentials"
    "$HOME/vaults/personal"
    "$HOME/vaults/work"
)
CREDENTIALS="${REPOSITORIES[0]}"
GIT_CRYPT_REPO="$HOME/.local/bin/git-crypt-repo"
GIT_CRYPT_TEXTCONV="$HOME/.local/bin/git-crypt-textconv"
GIT_CRED_READ="$HOME/.local/bin/git-cred-read"
CREDENTIALS_SETUP="$HOME/.local/bin/credentials-setup"

fail() {
    echo "setup-secrets: $*" >&2
    exit 1
}

run_make_target() {
    local repository="$1" target="$2"
    if ! make -C "$repository" "$target"; then
        echo "setup-secrets: make -C $repository $target failed" >&2
        exit 1
    fi
}

validate_link_destination() {
    local source="$1" destination="$2"
    if [[ -L "$destination" ]]; then
        if [[ "$(readlink "$destination")" != "$source" ]]; then
            fail "refusing to replace existing symlink: $destination"
        fi
    elif [[ -e "$destination" ]]; then
        fail "refusing to replace existing path: $destination"
    fi
}

link_safely() {
    local source="$1" destination="$2"
    validate_link_destination "$source" "$destination"
    mkdir -p "$(dirname "$destination")"
    [[ -L "$destination" ]] || {
        ln -s "$source" "$destination"
        echo "linked: $destination -> $source"
    }
}

# Запертый git-crypt файл начинается с заголовка \0"GITCRYPT", расшифрованный - после unlock
is_git_crypt_locked() {
    [[ -f "$1" ]] || return 1
    printf '\000GITCRYPT' | cmp -s - <(head -c 9 "$1")
}

command_unlock() {
    command -v make >/dev/null 2>&1 || fail "make is required"
    for repository in "${REPOSITORIES[@]}"; do
        [[ -d "$repository" ]] || fail "repository is missing: $repository"
        [[ -e "$repository/.git" ]] || fail "git metadata is missing: $repository"
        [[ -f "$repository/Makefile" ]] || fail "Makefile is missing: $repository"
    done
    for helper in "$GIT_CRYPT_REPO" "$GIT_CRYPT_TEXTCONV" "$GIT_CRED_READ"; do
        [[ -x "$helper" ]] || fail "helper is missing or not executable: $helper"
    done

    for repository in "${REPOSITORIES[@]}"; do
        run_make_target "$repository" init
        run_make_target "$repository" unlock
    done
    if [[ ! -f "$CREDENTIALS/git/gitconfig" ]] || is_git_crypt_locked "$CREDENTIALS/git/gitconfig"; then
        fail "unlocked credentials gitconfig is missing: $CREDENTIALS/git/gitconfig"
    fi

    command_link
    echo "setup-secrets: credentials and vaults unlocked"
}

command_link() {
    if [[ -d "$CREDENTIALS" ]]; then
        if [[ -f "$CREDENTIALS/git/gitconfig" ]] && ! is_git_crypt_locked "$CREDENTIALS/git/gitconfig"; then
            [[ -x "$CREDENTIALS_SETUP" ]] || fail "helper is missing or not executable: $CREDENTIALS_SETUP"
            run_make_target "$CREDENTIALS" link
            link_safely "$CREDENTIALS/git/gitconfig" "$RUNTIME_GITCONFIG"
        fi
    fi

    for repository_index in 1 2; do
        vault="${REPOSITORIES[$repository_index]}"
        [[ -d "$vault" && -d "$OBSIDIAN_CONFIG" ]] || continue
        link_safely "$OBSIDIAN_CONFIG" "$vault/.obsidian"
    done
}

case "${1:-}" in
    unlock)
        command_unlock
        ;;
    link)
        command_link
        ;;
    *)
        echo "usage: setup-secrets.sh {unlock|link}" >&2
        exit 1
        ;;
esac
