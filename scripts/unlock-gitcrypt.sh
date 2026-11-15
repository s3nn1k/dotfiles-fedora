#!/usr/bin/env bash
set -euo pipefail
# shellcheck shell=bash disable=SC2153
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/lib.sh"

REPOSITORIES=(
    "$HOME/credentials"
    "$HOME/vaults/personal"
    "$HOME/vaults/work"
)
CREDENTIALS="${REPOSITORIES[0]}"

fail() {
    echo "unlock-gitcrypt: $*" >&2
    exit 1
}

decryption_canary_path() {
    local repository="$1"
    if [[ "$repository" == "$CREDENTIALS" ]]; then
        printf '%s\n' "git/gitconfig"
        return
    fi
    git -C "$repository" ls-files -- '*.md' ':(exclude)**/README.md' | sed -n '1p'
}

verify_repository_decrypted() {
    local repository="$1" canary_path
    canary_path="$(decryption_canary_path "$repository")"
    if [[ -z "$canary_path" ]]; then
        echo "unlock-gitcrypt: nothing tracked under the git-crypt filter to verify in $repository" >&2
        return 0
    fi
    if [[ ! -f "$repository/$canary_path" ]]; then
        fail "decryption canary file is missing after unlock: $repository/$canary_path"
    fi
    if is_git_crypt_locked "$repository/$canary_path"; then
        fail "$repository is still encrypted after unlock: $repository/$canary_path
probable cause: rotated git-crypt key - the installed key is stale, so 'make unlock' was a no-op
treatment: cd $repository && make lock && make unlock (paste the new base64 key, or run VAULT_KEY=<key> make unlock)"
    fi
}

unlock_repository() {
    local repository="$1" key
    read -r -s -p "ключ ${repository#"$HOME"/}: " key
    echo
    export VAULT_KEY="$key"
    (
        cd "$repository"
        git-crypt-repo init
        git-crypt-repo unlock
    )
    verify_repository_decrypted "$repository"
}

main() {
    local repository
    command -v git-crypt-repo >/dev/null 2>&1 || fail "git-crypt-repo не установлен; запусти scripts/bootstrap.sh git"
    for repository in "${REPOSITORIES[@]}"; do
        [[ -d "$repository" ]] || fail "repository is missing: $repository"
    done

    for repository in "${REPOSITORIES[@]}"; do
        unlock_repository "$repository"
    done

    if [[ -f "$CREDENTIALS/scripts/setup.sh" ]]; then
        sh "$CREDENTIALS/scripts/setup.sh" link
    else
        echo "unlock-gitcrypt: нет $CREDENTIALS/scripts/setup.sh; раскладка секретов пропущена (свежий vault ещё не обновлён)" >&2
    fi

    # shellcheck disable=SC2153
    "$REPOSITORY/scripts/bootstrap.sh" mihomo

    find "$CREDENTIALS" -type d -exec chmod 700 {} +
    find "$CREDENTIALS" -type f -exec chmod 600 {} +
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
