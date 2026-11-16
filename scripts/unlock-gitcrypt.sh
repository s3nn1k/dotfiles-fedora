#!/usr/bin/env bash
set -euo pipefail
# shellcheck shell=bash disable=SC2153
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/lib.sh"

CREDENTIALS="$HOME/credentials"
CANARY_PATH="git/gitconfig"

fail() {
    echo "unlock-gitcrypt: $*" >&2
    exit 1
}

verify_decrypted() {
    [[ -f "$CREDENTIALS/$CANARY_PATH" ]] ||
        fail "decryption canary file is missing after unlock: $CREDENTIALS/$CANARY_PATH"
    if is_git_crypt_locked "$CREDENTIALS/$CANARY_PATH"; then
        fail "$CREDENTIALS is still encrypted after unlock: $CREDENTIALS/$CANARY_PATH
probable cause: rotated git-crypt key - the installed key is stale, so 'make unlock' was a no-op
treatment: cd $CREDENTIALS && make lock && make unlock (paste the new base64 key, or run VAULT_KEY=<key> make unlock)"
    fi
}

main() {
    [[ -d "$CREDENTIALS" ]] || fail "repository is missing: $CREDENTIALS"
    [[ -x "$CREDENTIALS/scripts/git-crypt-repo.sh" ]] ||
        fail "нет $CREDENTIALS/scripts/git-crypt-repo.sh; обнови ~/credentials (git pull)"

    local key
    read -r -s -p "ключ credentials: " key
    echo
    export VAULT_KEY="$key"
    (
        cd "$CREDENTIALS"
        make init
        make unlock
    )
    verify_decrypted

    if [[ -f "$CREDENTIALS/scripts/setup.sh" ]]; then
        sh "$CREDENTIALS/scripts/setup.sh" link
    else
        echo "unlock-gitcrypt: нет $CREDENTIALS/scripts/setup.sh; раскладка секретов пропущена" >&2
    fi

    "$REPOSITORY/scripts/bootstrap.sh" mihomo

    find "$CREDENTIALS" -type d -exec chmod 700 {} +
    find "$CREDENTIALS" -type f -exec chmod 600 {} +
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
