#!/bin/bash

# Prints the distro logo glyph for the Polybar launcher module.
# Output keeps the original " <glyph> " spacing of the old static label.
# Glyphs are emitted via \u escapes (font-logos range, covered by
# JetBrainsMono Nerd Font and Symbols Nerd Font Mono):
#   U+F303 Arch, U+F306 Debian, U+F31B Ubuntu, U+F17C Tux fallback

ID=""
ID_LIKE=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
fi

case "$ID" in
    arch)   printf '  \n' ;;
    debian) printf '  \n' ;;
    ubuntu) printf '  \n' ;;
    *)
        if [[ "$ID_LIKE" == *arch* ]]; then
            printf '  \n'
        elif [[ "$ID_LIKE" == *debian* ]]; then
            printf '  \n'
        else
            printf '  \n'
        fi
        ;;
esac
