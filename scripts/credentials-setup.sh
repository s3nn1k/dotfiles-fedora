#!/usr/bin/env bash
# ~/credentials wiring: link (symlink secrets into $HOME) and secure (tighten
# permissions of the decrypted tree). The repository itself is cloned by
# scripts/bootstrap.sh; this helper only operates on the standard path.
set -euo pipefail

REPOSITORY_ROOT="$HOME/credentials"
[ ! -L "$REPOSITORY_ROOT" ] || {
    echo "credentials-setup: repository root is a symlink, refusing: $REPOSITORY_ROOT" >&2
    exit 1
}
[ -d "$REPOSITORY_ROOT" ] || {
    echo "credentials-setup: $REPOSITORY_ROOT not found (bootstrap first)." >&2
    exit 1
}

SECURE_DIRECTORIES=(
    "$REPOSITORY_ROOT/agents-credentials"
    "$REPOSITORY_ROOT/git"
    "$REPOSITORY_ROOT/kube"
    "$REPOSITORY_ROOT/nkp"
    "$REPOSITORY_ROOT/pi"
    "$REPOSITORY_ROOT/ssh"
)
SECURE_FILES=(
    "$REPOSITORY_ROOT"/git/*
    "$REPOSITORY_ROOT/agents-credentials/git-credentials"
    "$REPOSITORY_ROOT"/kube/*
    "$REPOSITORY_ROOT"/nkp/*.txt
    "$REPOSITORY_ROOT"/pi/*
    "$REPOSITORY_ROOT"/ssh/*
)

link_file() {
    local source_path="$1" destination_path="$2"
    [ -e "$source_path" ] || { echo "link: source missing, skipping: $source_path"; return; }
    mkdir -p "$(dirname "$destination_path")"
    if [ -L "$destination_path" ]; then
        [ "$(readlink "$destination_path")" = "$source_path" ] || {
            echo "link: destination is another symlink, refusing: $destination_path" >&2
            return 1
        }
        return
    fi
    [ -e "$destination_path" ] || {
        ln -s "$source_path" "$destination_path"
        echo "linked: $destination_path -> $source_path"
        return
    }
    echo "link: destination exists, refusing: $destination_path" >&2
    return 1
}

validate_secure_sources() {
    [ ! -L "$REPOSITORY_ROOT" ] || {
        echo "credentials-setup: repository root is a symlink, refusing: $REPOSITORY_ROOT" >&2
        return 1
    }
    for directory_path in "${SECURE_DIRECTORIES[@]}"; do
        [ ! -L "$directory_path" ] || {
            echo "credentials-setup: source directory is a symlink, refusing: $directory_path" >&2
            return 1
        }
        if [ -e "$directory_path" ] && [ ! -d "$directory_path" ]; then
            echo "credentials-setup: source directory is not a directory: $directory_path" >&2
            return 1
        fi
    done
    for file_path in "${SECURE_FILES[@]}"; do
        [ ! -L "$file_path" ] || {
            echo "credentials-setup: source file is a symlink, refusing: $file_path" >&2
            return 1
        }
    done
}

apply_secure_permissions() {
    chmod 700 "$REPOSITORY_ROOT"
    for directory_path in "${SECURE_DIRECTORIES[@]}"; do
        [ -d "$directory_path" ] || continue
        chmod 700 "$directory_path"
    done
    for file_path in "${SECURE_FILES[@]}"; do
        [ -f "$file_path" ] || continue
        chmod 600 "$file_path"
    done
}

secure() {
    validate_secure_sources
    apply_secure_permissions
}

validate_destination_parent() {
    local destination="$1" parent
    parent="$(dirname "$destination")"
    while [ "$parent" != "$HOME" ]; do
        case "$parent" in
        "$HOME"/*)
            ;;
        *)
            return 0
            ;;
        esac
        [ ! -L "$parent" ] || {
            echo "credentials-setup: destination parent is a symlink, refusing: $parent" >&2
            return 1
        }
        if [ -e "$parent" ] && [ ! -d "$parent" ]; then
            echo "credentials-setup: destination parent is not a directory: $parent" >&2
            return 1
        fi
        parent="$(dirname "$parent")"
    done
}

preflight_destination_parents() {
    local source_path file_name
    if [ -d "$REPOSITORY_ROOT/ssh" ]; then
        validate_destination_parent "$HOME/.ssh/.credentials-setup-preflight"
        for source_path in "$REPOSITORY_ROOT"/ssh/*; do
            [ -e "$source_path" ] || continue
            case "$source_path" in *.zsh) continue ;; esac
            validate_destination_parent "$HOME/.ssh/$(basename "$source_path")"
        done
    fi
    if [ -d "$REPOSITORY_ROOT/kube" ]; then
        validate_destination_parent "$HOME/.kube/.credentials-setup-preflight"
        for source_path in "$REPOSITORY_ROOT"/kube/*; do
            [ -e "$source_path" ] || continue
            validate_destination_parent "$HOME/.kube/$(basename "$source_path")"
        done
    fi
    [ -e "$REPOSITORY_ROOT/git/git-credentials" ] &&
        validate_destination_parent "$HOME/.git-credentials"
    if [ -d "$REPOSITORY_ROOT/pi" ] && {
        [ -e "$REPOSITORY_ROOT/pi/auth.json" ] ||
        [ -e "$REPOSITORY_ROOT/pi/mcp.json" ]
    }; then
        for file_name in auth.json mcp.json; do
            [ -e "$REPOSITORY_ROOT/pi/$file_name" ] || continue
            validate_destination_parent "$HOME/.pi/agent/$file_name"
        done
    fi
}

command="${1:-}"
case "$command" in
secure)
    secure
    ;;
link)
    # secrets go live through symlinks; tighten permissions before exposing them
    validate_secure_sources
    preflight_destination_parents
    apply_secure_permissions

    if [ -d "$REPOSITORY_ROOT/ssh" ]; then
        mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
        for source_path in "$REPOSITORY_ROOT"/ssh/*; do
            [ -e "$source_path" ] || continue
            # *.zsh (ssh wrapper function) is sourced by zshrc, not linked here
            case "$source_path" in *.zsh) continue ;; esac
            link_file "$source_path" "$HOME/.ssh/$(basename "$source_path")"
        done
    fi

    if [ -d "$REPOSITORY_ROOT/kube" ]; then
        mkdir -p "$HOME/.kube" && chmod 700 "$HOME/.kube"
        for source_path in "$REPOSITORY_ROOT"/kube/*; do
            [ -e "$source_path" ] || continue
            link_file "$source_path" "$HOME/.kube/$(basename "$source_path")"
        done
    fi

    if [ -f "$REPOSITORY_ROOT/git/git-credentials" ]; then
        link_file "$REPOSITORY_ROOT/git/git-credentials" "$HOME/.git-credentials"
    fi

    if [ -d "$REPOSITORY_ROOT/pi" ] && {
        [ -e "$REPOSITORY_ROOT/pi/auth.json" ] ||
        [ -e "$REPOSITORY_ROOT/pi/mcp.json" ]
    }; then
        mkdir -p "$HOME/.pi/agent"
        for file_name in auth.json mcp.json; do
            link_file "$REPOSITORY_ROOT/pi/$file_name" "$HOME/.pi/agent/$file_name"
        done
    fi
    ;;
*)
    echo "usage: credentials-setup {link|secure}" >&2
    exit 1
    ;;
esac
