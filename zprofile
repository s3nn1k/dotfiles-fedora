export EDITOR=nvim
export VISUAL=nvim
export PATH="$HOME/.local/bin:$PATH"
export GOBIN="$HOME/.local/bin"

if [[ -z "${SSH_AUTH_SOCK:-}" || "$SSH_AUTH_SOCK" == "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.sock" ]]; then
    export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.sock"
fi
