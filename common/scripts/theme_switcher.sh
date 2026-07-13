#!/usr/bin/env bash

source "$HOME/.config/i3/lib/paths.sh"

THEME=$1
LINK_TARGET="$I3WM_CURRENT_THEME"
DUNST_DROPIN_DIR="$HOME/.config/dunst/dunstrc.d"

i3wm_seed_state

if [ -z "$THEME" ] || [ "$THEME" == "gui" ]; then
    OPT_PRO="  Pro Dark"
    OPT_PYWAL="  Pywal"
    OPTIONS="$OPT_PRO\n$OPT_PYWAL"
    HEADER="<span color='#888888'>SELECT SYSTEM THEME STYLE</span>"

    CHOICE_INDEX=$(echo -e "$OPTIONS" | rofi -dmenu -i -format d -p "Theme" -mesg "$HEADER" -theme ~/.config/rofi/theme_select.rasi)

    case "$CHOICE_INDEX" in
        1) THEME="pro-dark" ;;
        2) THEME="pywal-custom" ;;
        *) exit 0 ;;
    esac
fi

if [ ! -d "$I3WM_THEMES_DIR/$THEME" ]; then
    notify-send "Error" "Theme '$THEME' not found!"
    exit 1
fi

if [ "$THEME" == "pro-dark" ]; then
    ACCENT="#CBA6F7"
    BG_COLOR="#1E1E2EF2"
elif [ "$THEME" == "pywal-custom" ]; then
    ACCENT=$(grep "primary:" "$I3WM_THEMES_DIR/$THEME/rofi.rasi" | cut -d'#' -f2 | cut -d';' -f1)
    ACCENT="#$ACCENT"
    BG_COLOR="#0A0A0FF2"
fi

# Theme colors land in a dunst drop-in (loaded after dunstrc, overrides it)
# so the base dunstrc stays static.
mkdir -p "$DUNST_DROPIN_DIR"
cat > "$DUNST_DROPIN_DIR/50-theme.conf" <<EOF
[global]
    background = "$BG_COLOR"
    frame_color = "$ACCENT"
EOF

cat > "$I3WM_STATE_DIR/lock_colors.rc" <<EOF
export LOCK_RING="${ACCENT}cc"
export LOCK_TEXT="${ACCENT}ee"
export LOCK_INSIDE="#00000000"
export LOCK_WRONG="#F38BA8bb"
export LOCK_VERIFY="#CDD6F4bb"
EOF

rm -rf "$LINK_TARGET"
ln -s "$I3WM_THEMES_DIR/$THEME" "$LINK_TARGET"
papirus-folders -C blue --theme Papirus-Dark &

if [ -f "$LINK_TARGET/wallpaper.jpg" ]; then
    feh --bg-fill "$LINK_TARGET/wallpaper.jpg"
fi

~/.config/polybar/launch.sh &
i3-msg reload >/dev/null

killall -9 dunst 2>/dev/null; sleep 1; dunst &
notify-send "System Synced" "Theme applied: $THEME"
