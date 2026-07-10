#!/bin/bash

# Prints the distro logo glyph for the Polybar launcher module.
# Output keeps the original " <glyph> " spacing of the old static label.

ID=""
ID_LIKE=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
fi

case "$ID" in
    arch)   echo " " ;;
    debian) echo " " ;;
    *)
        if [[ "$ID_LIKE" == *arch* ]]; then
            echo " "
        elif [[ "$ID_LIKE" == *debian* ]]; then
            echo " "
        else
            echo " "
        fi
        ;;
esac
