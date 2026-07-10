#!/bin/bash

ACCENT=$(grep '^primary =' "$HOME/.config/i3/themes/current/colors.ini" | awk '{print $3}')
if [ -z "$ACCENT" ]; then ACCENT="#CBA6F7"; fi

# Detect package backend: pacman/yay (Arch) or apt (Debian)
if command -v pacman >/dev/null 2>&1; then
    BACKEND="arch"
elif command -v apt-get >/dev/null 2>&1; then
    BACKEND="debian"
else
    BACKEND="unknown"
fi

apt_upgradable() {
    # Simulated dist-upgrade works without root and without touching the lock
    apt-get -s -o Debug::NoLocking=true dist-upgrade 2>/dev/null | grep '^Inst '
}

get_count() {
    if [ "$BACKEND" = "arch" ]; then
        if ! updates_arch=$(checkupdates 2> /dev/null | wc -l ); then
            updates_arch=0
        fi

        if ! updates_aur=$(yay -Qua 2> /dev/null | wc -l); then
            updates_aur=0
        fi

        updates=$((updates_arch + updates_aur))
    elif [ "$BACKEND" = "debian" ]; then
        updates=$(apt_upgradable | wc -l)
    else
        updates=0
    fi

    if [ "$updates" -gt 0 ]; then
        echo " $updates"
    else
        echo " 0"
    fi
}

show_list() {
    if [ "$BACKEND" = "arch" ]; then
        list_arch=$(checkupdates 2>/dev/null | sed 's/^/  /')
        list_aur=$(yay -Qua 2>/dev/null | sed 's/^/󰣇  /')

        full_list="$list_arch\n$list_aur"
    elif [ "$BACKEND" = "debian" ]; then
        full_list=$(apt_upgradable | awk '{gsub(/[\[\]()]/,""); printf "  %s %s -> %s\n", $2, $3, $4}')
    else
        full_list=""
    fi

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
    if [ "$BACKEND" = "arch" ]; then
        UPDATE_CMD="yay -Syu"
    elif [ "$BACKEND" = "debian" ]; then
        UPDATE_CMD="sudo apt update && sudo apt full-upgrade"
    else
        notify-send "System Update" "No supported package manager found."
        exit 1
    fi

    kitty --hold -e sh -c "$UPDATE_CMD; echo ''; echo 'System Update Complete! Press Enter to exit.'; read"
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
