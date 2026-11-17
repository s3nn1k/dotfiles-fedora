# shellcheck shell=bash
run_configs() {
    install_command "$REPOSITORY/swayidle/swayidle-laptop.py" swayidle-laptop

    local output
    output="$(swaymsg -r -t get_outputs | jq -re '
        [.[] | select(.active == true and (.name | test("^eDP-[0-9]+$"))) | .name]
        | if length == 1 then .[0] else error("expected one active eDP output") end
    ')" || { echo "bootstrap: нужен один активный eDP-экран; запусти из Sway" >&2; return 1; }

    set_output_name "$REPOSITORY" "$output"
    local name
    for name in sway/config sway/config.d/90-swayidle.conf sway/desktop.conf sway/output.conf \
        sway/background.conf swaylock/config foot/foot.ini rofi/config.rasi \
        waybar/config.jsonc waybar/style.css waybar/lang.sh waybar/mihomo-status.sh \
        dunst/dunstrc \
        gtk-3.0/settings.ini gtk-3.0/gtk.css gtk-4.0/settings.ini gtk-4.0/gtk.css fontconfig/fonts.conf \
        mpd/mpd.conf rmpc/config.ron environment.d/qt-theme.conf; do
        link_config "$REPOSITORY/$name" "$CONFIGURATION_HOME/$name"
    done
    link_config "$REPOSITORY/zshrc" "$HOME/.zshrc"
    link_config "$REPOSITORY/zprofile" "$HOME/.zprofile"
    link_config "$REPOSITORY/gitconfig" "$HOME/.gitconfig"
    link_config "$REPOSITORY/psqlrc" "$HOME/.psqlrc"

    sway -C -c "$CONFIGURATION_HOME/sway/config"
    foot --check-config --config="$CONFIGURATION_HOME/foot/foot.ini"
    rofi -config "$CONFIGURATION_HOME/rofi/config.rasi" -dump-theme >/dev/null
    swaymsg reload
    systemctl --user restart dunst.service
}
