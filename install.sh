#!/usr/bin/env bash
#
# Main entry point: detects the running distro and hands off to the
# matching installer (arch/install.sh or debian/install.sh).
#
# Flags are passed through unchanged:
#   --dry-run   Simulate without changing the system
#   --link      Symlink configs instead of copying

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ ! -f /etc/os-release ]; then
    echo -e "${RED}[ERROR]${NC} /etc/os-release not found. Cannot detect distribution."
    exit 1
fi

. /etc/os-release

DISTRO=""
case "$ID" in
    arch)   DISTRO="arch" ;;
    debian) DISTRO="debian" ;;
    nixos)  DISTRO="nixos" ;;
    *)
        if [[ "$ID_LIKE" == *arch* ]]; then
            DISTRO="arch"
            echo -e "${YELLOW}[WARN]${NC} Detected Arch-based distro '$ID'. Using the Arch installer."
        elif [[ "$ID_LIKE" == *debian* ]]; then
            DISTRO="debian"
            echo -e "${YELLOW}[WARN]${NC} Detected Debian-based distro '$ID'. Using the Debian installer."
        fi
        ;;
esac

if [ -z "$DISTRO" ]; then
    echo -e "${RED}[ERROR]${NC} Unsupported distribution: '$ID'."
    echo "Supported: Arch Linux (arch/install.sh), Debian (debian/install.sh), NixOS (nixos/install.sh)."
    echo "You can run one of those installers directly at your own risk."
    exit 1
fi

echo -e "${BLUE}[INFO]${NC} Detected distribution: $ID -> running $DISTRO/install.sh"
exec bash "$REPO_DIR/$DISTRO/install.sh" "$@"
