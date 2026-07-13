#!/usr/bin/env bash
#
# Distro-facts runtime library (docs/DESIGN.md §3). Pure read, no side
# effects, O(1); safe to source from any script or from zshrc.
#
# Exposes:
#   DISTRO_ID, DISTRO_LIKE, DISTRO_FAMILY  (arch | debian | nixos | unknown)
#   distro_glyph            polybar/launcher logo glyph for this distro
#   distro_fastfetch_logo   fastfetch ASCII logo name ("" = let fastfetch pick)
#   distro_update_count     number of pending updates (best effort, no root)
#   distro_update_cmd       shell command string that performs a full update

DISTRO_ID=""
DISTRO_LIKE=""
if [ -f /etc/os-release ]; then
    DISTRO_ID=$(. /etc/os-release; echo "$ID")
    DISTRO_LIKE=$(. /etc/os-release; echo "${ID_LIKE:-}")
fi

case "$DISTRO_ID" in
    arch)   DISTRO_FAMILY="arch" ;;
    debian) DISTRO_FAMILY="debian" ;;
    nixos)  DISTRO_FAMILY="nixos" ;;
    *)
        if [[ "$DISTRO_LIKE" == *arch* ]]; then
            DISTRO_FAMILY="arch"
        elif [[ "$DISTRO_LIKE" == *debian* ]]; then
            DISTRO_FAMILY="debian"
        else
            DISTRO_FAMILY="unknown"
        fi
        ;;
esac

# Glyphs (font-logos range; covered by JetBrainsMono Nerd Font and Symbols
# Nerd Font Mono): U+F303 Arch, U+F306 Debian, U+F31B Ubuntu, U+F313 NixOS,
# U+F17C Tux fallback. Emitted via \u escapes so the bytes cannot be lost.
distro_glyph() {
    case "$DISTRO_ID" in
        ubuntu) printf '' ;;
        *)
            case "$DISTRO_FAMILY" in
                arch)   printf '' ;;
                debian) printf '' ;;
                nixos)  printf '' ;;
                *)      printf '' ;;
            esac
            ;;
    esac
}

distro_fastfetch_logo() {
    case "$DISTRO_ID" in
        arch)   echo "arch_small" ;;
        debian) echo "debian_small" ;;
        ubuntu) echo "ubuntu_small" ;;
        nixos)  echo "nixos_small" ;;
        *)      echo "" ;;
    esac
}

# Locate the system flake for NixOS updates: $NH_FLAKE / $FLAKE convention
# first, /etc/nixos/flake.nix second, channels as fallback (empty result).
_nixos_flake_dir() {
    if [ -n "${NH_FLAKE:-}" ]; then echo "$NH_FLAKE"; return; fi
    if [ -n "${FLAKE:-}" ];    then echo "$FLAKE";    return; fi
    if [ -f /etc/nixos/flake.nix ]; then echo "/etc/nixos"; return; fi
    echo ""
}

distro_update_count() {
    case "$DISTRO_FAMILY" in
        arch)
            local official aur
            if ! official=$(checkupdates 2>/dev/null | wc -l); then official=0; fi
            if ! aur=$(yay -Qua 2>/dev/null | wc -l); then aur=0; fi
            echo $((official + aur))
            ;;
        debian)
            apt-get -s -o Debug::NoLocking=true dist-upgrade 2>/dev/null \
                | grep -c '^Inst ' || true
            ;;
        nixos)
            # No cheap offline query exists for pending flake/channel updates.
            echo 0
            ;;
        *)
            echo 0
            ;;
    esac
}

distro_update_cmd() {
    case "$DISTRO_FAMILY" in
        arch)   echo "yay -Syu" ;;
        debian) echo "sudo apt update && sudo apt full-upgrade" ;;
        nixos)
            local flake_dir
            flake_dir=$(_nixos_flake_dir)
            if [ -n "$flake_dir" ]; then
                echo "cd '$flake_dir' && sudo nix flake update && sudo nixos-rebuild switch --flake ."
            else
                echo "sudo nixos-rebuild switch --upgrade"
            fi
            ;;
        *)      echo "" ;;
    esac
}
