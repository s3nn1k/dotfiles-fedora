run_nkp() {
    clone_repository https://github.com/s3nn1k/nkp.git "$HOME/projects/personal/nkp"
    NKP="$HOME/projects/personal/nkp"
    make -C "$NKP" install
}
