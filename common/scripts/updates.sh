#!/usr/bin/env bash

source "$HOME/.config/i3/lib/distro.sh"

ACCENT=$(grep '^primary =' "$HOME/.local/state/i3wm-x11/themes/current/colors.ini" | awk '{print $3}')
if [ -z "$ACCENT" ]; then ACCENT="#CBA6F7"; fi

get_count() {
    local updates
    updates=$(distro_update_count)

    if [ "$updates" -gt 0 ]; then
        echo " $updates"
    else
        echo " 0"
    fi
}

show_list() {
    local full_list=""

    case "$DISTRO_FAMILY" in
        arch)
            local list_arch list_aur
            list_arch=$(checkupdates 2>/dev/null | sed 's/^/  /')
            list_aur=$(yay -Qua 2>/dev/null | sed 's/^/󰣇  /')
            full_list="$list_arch\n$list_aur"
            ;;
        debian)
            full_list=$(apt-get -s -o Debug::NoLocking=true dist-upgrade 2>/dev/null \
                | awk '/^Inst /{gsub(/[\[\]()]/,""); printf "  %s %s -> %s\n", $2, $3, $4}')
            ;;
        nixos)
            notify-send "System Updates" "NixOS updates are applied declaratively.\nRight-click this module to rebuild the system."
            exit 0
            ;;
        *)
            notify-send "System Updates" "No supported package manager found."
            exit 0
            ;;
    esac

    local clean_list
    clean_list=$(echo -e "$full_list" | sed '/^$/d' | grep -v '^\s*$')

    if [ -z "$clean_list" ]; then
        notify-send "System Status" "No updates available. Your system is up to date!"
        exit 0
    fi

    HEADER="<span color='$ACCENT'><b>      AVAILABLE SYSTEM UPDATES      </b></span>"
    LAYOUT="window {width: 700px;} listview {lines: 12;} element-text {font: \"JetBrainsMono Nerd Font 11\";}"

    echo -e "$clean_list" | rofi -dmenu -i -p "Updates" \
        -theme ~/.config/rofi/config.rasi \
        -theme-str "$LAYOUT" \
        -mesg "$HEADER"
}

run_update() {
    local update_cmd
    update_cmd=$(distro_update_cmd)

    if [ -z "$update_cmd" ]; then
        notify-send "System Update" "No supported package manager found."
        exit 1
    fi

    kitty --hold -e sh -c "$update_cmd; echo ''; echo 'System Update Complete! Press Enter to exit.'; read"
}

case "$1" in
    show)
        show_list
        ;;
    update)
        run_update
        ;;
    *)
        get_count
        ;;
esac
