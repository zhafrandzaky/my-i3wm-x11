#!/usr/bin/env bash
#
# Shared path contract: everything the desktop writes at runtime is state and
# lives here (docs/DESIGN.md §4). Static configs (i3 include, polybar
# include-file, rofi @import) reference ~/.local/state/i3wm-x11 literally, so
# this is pinned to $HOME rather than honoring $XDG_STATE_HOME overrides —
# the two must never diverge.

I3WM_STATE_DIR="$HOME/.local/state/i3wm-x11"
I3WM_THEMES_DIR="$I3WM_STATE_DIR/themes"
I3WM_CURRENT_THEME="$I3WM_THEMES_DIR/current"

# Seed initial state on first run: copy the shipped pro-dark theme out of the
# (possibly read-only) deployed config tree and point 'current' at it.
# Idempotent; safe to call from installers, launch.sh, and HM activation.
i3wm_seed_state() {
    mkdir -p "$I3WM_THEMES_DIR" "$I3WM_STATE_DIR/fastfetch"

    local src="$HOME/.config/i3/themes/pro-dark"
    if [ ! -d "$I3WM_THEMES_DIR/pro-dark" ] && [ -d "$src" ]; then
        cp -r --no-preserve=mode "$src" "$I3WM_THEMES_DIR/pro-dark"
    fi

    if [ ! -e "$I3WM_CURRENT_THEME" ] && [ -d "$I3WM_THEMES_DIR/pro-dark" ]; then
        ln -sfn "$I3WM_THEMES_DIR/pro-dark" "$I3WM_CURRENT_THEME"
    fi
}
