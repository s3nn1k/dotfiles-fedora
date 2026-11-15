# shellcheck shell=bash
run_pi-agent() {
    clone_repository https://github.com/s3nn1k/pi-agent.git "$HOME/.pi/agent"
    node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 19)) process.exit(1)'
    npm install --global --prefix "$HOME/.local" --ignore-scripts @earendil-works/pi-coding-agent@1.3.0
    make -C "$HOME/.pi/agent" init
    "$HOME/.local/bin/pi" update --extensions
}
