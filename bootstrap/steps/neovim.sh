run_neovim() {
    sudo dnf install -y neovim

    clone_repository https://github.com/s3nn1k/nvim.git "$CONFIGURATION_HOME/nvim"
    mkdir -p "$CONFIGURATION_HOME/omp"
    link_config "$REPOSITORY/omp/prompt.omp.json" "$CONFIGURATION_HOME/omp/prompt.omp.json"
    "$CONFIGURATION_HOME/nvim/init.sh"
}
