#!/bin/bash

SETUP_FLAG="$HOME/.config/i3/.setup_done"

if [ -f "$SETUP_FLAG" ]; then exit 0; fi

sleep 3

rm -rf ~/.cache/fastfetch
rm -f /tmp/weather_cache
notify-send -u normal -t 3000 "System Setup" "Clearing old caches & preparing environment..."

sleep 1

notify-send -u critical -t 10000 "Welcome to Pro Dark :)" "Please select your default web browser to complete the setup."

# Build the browser list from what is actually installed (names differ per distro,
# e.g. firefox on Arch vs firefox-esr on Debian, brave-bin ships brave-browser.desktop)
BROWSER_LIST=""
for entry in "firefox:firefox.desktop" \
             "firefox-esr:firefox-esr.desktop" \
             "brave:brave-browser.desktop" \
             "chromium:chromium.desktop"; do
    name="${entry%%:*}"
    desktop="${entry#*:}"
    if [ -f "/usr/share/applications/$desktop" ] || [ -f "$HOME/.local/share/applications/$desktop" ]; then
        BROWSER_LIST+="${name}\n"
    fi
done

if [ -z "$BROWSER_LIST" ]; then
    BROWSER_LIST="firefox\nbrave\nchromium\n"
fi

BROWSER=$(echo -e "${BROWSER_LIST%\\n}" | rofi -dmenu -p "Browser" -theme ~/.config/rofi/config.rasi)

if [ -n "$BROWSER" ]; then
    case "$BROWSER" in
        brave) DESKTOP_FILE="brave-browser.desktop" ;;
        *)     DESKTOP_FILE="${BROWSER}.desktop" ;;
    esac
    xdg-settings set default-web-browser "$DESKTOP_FILE"
    notify-send "Setup Complete" "Default browser set to $BROWSER. Enjoy your new workspace!"
fi

CITY_INPUT=$(zenity --entry \
    --title="Weather Location Setup" \
    --text="Enter your City name for the Polybar weather widget:\n(e.g., Jakarta, Bandung, Tokyo)\n\nLeave blank to set it later via Right-Click on the widget." \
    --entry-text="")

CITY_FILE="$HOME/.config/i3/scripts/.weather_city"

if [ -n "$CITY_INPUT" ]; then
    SAFE_CITY=$(echo "$CITY_INPUT" | sed 's/[^a-zA-Z0-9 ,-]//g' | sed 's/ /+/g')
    echo "$SAFE_CITY" > "$CITY_FILE"
    rm -f /tmp/weather_cache
    zenity --info --title="Success" --text="Weather location set to: $CITY_INPUT" --timeout=3
else
    > "$CITY_FILE"
fi

touch "$SETUP_FLAG"