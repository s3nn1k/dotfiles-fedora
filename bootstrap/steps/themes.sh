# shellcheck shell=bash
install_gtk_theme() {
    gsettings set org.gnome.desktop.interface gtk-theme Gruvbox-Material-Dark
    gsettings set org.gnome.desktop.interface icon-theme Gruvbox-Material-Dark
    [[ -d "$HOME/.themes/Gruvbox-Material-Dark" ]] && return 0
    local archive="$CACHE/gruvbox-material-gtk.tar.gz"
    download https://github.com/TheGreatMcPain/gruvbox-material-gtk/archive/refs/heads/master.tar.gz \
        073ad0b27396b9d68663f5bf8df10b32603523a47a19bb5ebed2519cf9ae14d1 "$archive"
    tar -xzf "$archive" -C "$CACHE" \
        gruvbox-material-gtk-master/themes/Gruvbox-Material-Dark \
        gruvbox-material-gtk-master/themes/Gruvbox-Material-Dark-HIDPI \
        gruvbox-material-gtk-master/icons/Gruvbox-Material-Dark
    mkdir -p "$HOME/.themes" "$HOME/.icons"
    cp -r "$CACHE/gruvbox-material-gtk-master/themes/Gruvbox-Material-Dark" "$HOME/.themes/"
    cp -r "$CACHE/gruvbox-material-gtk-master/themes/Gruvbox-Material-Dark-HIDPI" "$HOME/.themes/"
    cp -r "$CACHE/gruvbox-material-gtk-master/icons/Gruvbox-Material-Dark" "$HOME/.icons/"
    local theme_css
    for theme_css in "$HOME/.themes/Gruvbox-Material-Dark"*/gtk-{3,4}.0/gtk.css; do
        sed -i \
            -e 's/#d4be98/#d4d4d4/g' \
            -e 's/#ddc7a1/#bdae93/g' \
            -e 's/#ea6962/#fb4934/g' \
            -e 's/#a9b665/#b8bb26/g' \
            -e 's/#d8a657/#fabd2f/g' \
            "$theme_css"
    done
}

install_sddm_theme() {
    sudo rm -rf /usr/share/sddm/themes/gruvbox
    sudo install -d -m 755 /usr/share/sddm/themes/gruvbox
    sudo install -m 644 \
        sddm/theme/main.qml \
        sddm/theme/metadata.desktop \
        sddm/theme/theme.conf \
        /usr/share/sddm/themes/gruvbox/
    sudo install -m 644 "$HOME/.local/share/fonts/Hack/HackNerdFont-Regular.ttf" /usr/share/sddm/themes/gruvbox/
    sudo install -m 644 wallpapers/pepe-in-the-rain.jpg /usr/share/sddm/themes/gruvbox/background.jpg
    sudo install -d -m 755 /etc/sddm.conf.d
    sudo install -m 644 sddm/99-gruvbox.conf /etc/sddm.conf.d/99-gruvbox.conf
}

run_themes() {
    download https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Hack.zip \
        fa24da7de7cefe7766614d27762570b20453c852fc1d5b657111666df9a5e449 "$CACHE/Hack.zip"
    mkdir -p "$HOME/.local/share/fonts/Hack"
    unzip -oq "$CACHE/Hack.zip" -d "$HOME/.local/share/fonts/Hack"
    fc-cache -f "$HOME/.local/share/fonts/Hack"

    download https://github.com/googlefonts/noto-emoji/raw/v2.047/fonts/NotoColorEmoji.ttf \
        39ee3c587e10e89669b9ff32703261d10d5f9c4dd5ad147b6b5a1c5200591817 "$CACHE/NotoColorEmoji.ttf"
    install -D -m 644 "$CACHE/NotoColorEmoji.ttf" "$HOME/.local/share/fonts/NotoColorEmoji/NotoColorEmoji.ttf"
    fc-cache -f "$HOME/.local/share/fonts/NotoColorEmoji"

    install_gtk_theme
    install_sddm_theme
}
