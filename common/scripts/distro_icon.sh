#!/usr/bin/env bash

# Polybar launcher module icon: the distro logo glyph, from the shared
# distro-facts library. Keeps the original " <glyph> " spacing.

source "$HOME/.config/i3/lib/distro.sh"

printf ' %s \n' "$(distro_glyph)"
