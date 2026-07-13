#!/usr/bin/env bash

# Launch picom with the right backend for the GPU:
#  - Real GPUs use the glx backend from picom.conf (blur, vsync).
#  - Software renderers (VMs, llvmpipe) hang the display with glx+vsync,
#    so fall back to xrender there (no blur; corners/shadows still work).

RENDERER=""
if command -v glxinfo >/dev/null 2>&1; then
    RENDERER=$(glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL renderer string/{print $2}')
fi

use_xrender=false
case "$RENDERER" in
    *llvmpipe*|*softpipe*|*SWR*|*"Software Rasterizer"*)
        use_xrender=true
        ;;
    "")
        # No glxinfo: assume real hardware unless we are clearly in a VM
        if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --quiet --vm; then
            use_xrender=true
        fi
        ;;
esac

if [ "$use_xrender" = true ]; then
    exec picom -b --backend xrender
else
    exec picom -b
fi
