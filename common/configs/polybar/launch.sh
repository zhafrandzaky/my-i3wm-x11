#!/bin/bash

killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Detect the active network interface (default route) for the traffic module
POLYBAR_IFACE=$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
if [ -z "$POLYBAR_IFACE" ]; then
    POLYBAR_IFACE=$(ls /sys/class/net 2>/dev/null | grep -vE '^(lo|docker|veth|br-|virbr|tun|tap)' | head -n1)
fi
export POLYBAR_IFACE=${POLYBAR_IFACE:-wlan0}

# Detect the backlight device for the backlight module
POLYBAR_BACKLIGHT=$(ls /sys/class/backlight 2>/dev/null | head -n1)
export POLYBAR_BACKLIGHT=${POLYBAR_BACKLIGHT:-intel_backlight}

# Compose module lists from available hardware so absent devices hide
# cleanly (no dangling separators or empty stubs) on any machine.
LEFT="ld distro sep caffeine"
if ls /sys/class/net 2>/dev/null | grep -qvE '^(lo|docker|veth|br-|virbr|tun|tap)'; then
    LEFT="$LEFT sep traffic"
fi
export POLYBAR_MODULES_LEFT="$LEFT sep xworkspaces rd"

RIGHT="ld updates sep cpu memory pulseaudio"
if [ -n "$(ls /sys/class/backlight 2>/dev/null)" ]; then
    RIGHT="$RIGHT backlight"
fi
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    RIGHT="$RIGHT battery"
fi
export POLYBAR_MODULES_RIGHT="$RIGHT sep systray sep powermenu rd"

if type "xrandr" > /dev/null; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload main -c ~/.config/polybar/config.ini &
  done
else
  polybar --reload main -c ~/.config/polybar/config.ini &
fi

echo "Polybar launched."