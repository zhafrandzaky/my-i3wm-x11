#!/usr/bin/env bash
#
# NixOS integration wizard (docs/DESIGN.md §6.4).
# Detects the current system, asks a few questions, and GENERATES a ready
# host configuration in ./nixos-example/ plus the exact commands to apply it.
# It never writes outside the current working directory and never edits
# /etc/nixos or nix.conf.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &> /dev/null && pwd)"
OUT_DIR="$PWD/nixos-example"
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
    esac
done

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
note()  { echo -e "${YELLOW}[NOTE]${NC} $1"; }

echo -e "${CYAN}"
echo " NIXOS • I3WM • X11"
echo " ╭──────────────────────────────────╮"
echo " │  Stack     :  NixOS + i3wm       │"
echo " │  Display   :  X11 (Xorg)         │"
echo " │  Paradigm  :  Declarative        │"
echo " ╰──────────────────────────────────╯"
echo -e "${NC}"
echo -e "${BLUE} // INTEGRATION WIZARD FOR NIXOS${NC}"
echo -e " This wizard generates a host configuration; it changes nothing on"
echo -e " your system. You review and apply it with nixos-rebuild yourself."
echo ""

# ---------- Detection ladder (runtime truth, docs/DESIGN.md §1/P1) ----------
if [ ! -f /etc/os-release ] || ! grep -q '^ID=nixos' /etc/os-release; then
    echo -e "${RED}[ERROR]${NC} This wizard is for NixOS. Detected something else."
    exit 1
fi
NIXOS_VERSION=$(nixos-version 2>/dev/null | cut -d'.' -f1,2)
info "NixOS $NIXOS_VERSION detected."

# The wizard only ever runs read-only nix commands, each self-supplying the
# experimental-feature flags; permanence comes from the generated config.
if nix flake --help &> /dev/null; then
    FLAKES_STATE="enabled system-wide"
else
    FLAKES_STATE="not enabled system-wide (the generated config enables them declaratively)"
fi
info "Flakes: $FLAKES_STATE"

EXISTING_DM="none"
if systemctl is-enabled display-manager.service &> /dev/null; then
    EXISTING_DM=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null | xargs basename 2>/dev/null || echo "unknown")
fi
info "Existing display manager: $EXISTING_DM"

if [ -f /etc/nixos/flake.nix ]; then
    SYSTEM_STYLE="flake (/etc/nixos/flake.nix)"
elif [ -f /etc/nixos/configuration.nix ]; then
    SYSTEM_STYLE="channels (/etc/nixos/configuration.nix)"
else
    SYSTEM_STYLE="unknown"
fi
info "System configuration style: $SYSTEM_STYLE"

# ---------- Questions (defaults suit a fresh minimal system) ----------
echo ""
printf "Username to set the desktop up for [%s]: " "$USER"
read -r ANSWER_USER
WIZ_USER=${ANSWER_USER:-$USER}

DM_DEFAULT="n"
DM_PROMPT="Use LightDM instead of startx? [y/N]: "
if [ "$EXISTING_DM" != "none" ] && [ "$EXISTING_DM" != "unknown" ]; then
    note "You already run '$EXISTING_DM'. Keep it: i3 will appear there as a session."
    DM_PROMPT="Enable LightDM anyway (usually NO if you keep $EXISTING_DM)? [y/N]: "
fi
printf "%s" "$DM_PROMPT"
read -r ANSWER_DM
[[ "${ANSWER_DM:-$DM_DEFAULT}" =~ ^[Yy]$ ]] && WIZ_DM="true" || WIZ_DM="false"

printf "Include Visual Studio Code (unfree)? [y/N]: "
read -r ANSWER_CODE
[[ "${ANSWER_CODE:-n}" =~ ^[Yy]$ ]] && WIZ_CODE="true" || WIZ_CODE="false"

printf "Include Brave browser (unfree)? [y/N]: "
read -r ANSWER_BRAVE
[[ "${ANSWER_BRAVE:-n}" =~ ^[Yy]$ ]] && WIZ_BRAVE="true" || WIZ_BRAVE="false"

# ---------- Generate ----------
FLAKE_URL="path:$REPO_DIR?dir=nixos"

render_flake() {
cat <<EOF
{
  description = "Host configuration using the my-i3wm-x11 desktop";

  inputs = {
    i3wm-x11.url = "$FLAKE_URL";
    nixpkgs.follows = "i3wm-x11/nixpkgs";
  };

  outputs = { self, nixpkgs, i3wm-x11 }: {
    nixosConfigurations."$HOSTNAME_NOW" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        i3wm-x11.nixosModules.default
        ./configuration.nix
        ./hardware-configuration.nix
      ];
    };
  };
}
EOF
}

render_configuration() {
cat <<EOF
{ config, pkgs, ... }:

{
  services.i3wm-x11 = {
    enable = true;
    username = "$WIZ_USER";
    enableDisplayManager = $WIZ_DM;
    withVSCode = $WIZ_CODE;
    withBrave = $WIZ_BRAVE;
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Merged with your existing user; remove if you define the user elsewhere.
  users.users.$WIZ_USER = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  system.stateVersion = "$NIXOS_VERSION";
}
EOF
}

HOSTNAME_NOW=$(cat /proc/sys/kernel/hostname)

if [ "$DRY_RUN" = true ]; then
    echo ""
    info "[DRY-RUN] Would write: $OUT_DIR/{flake.nix,configuration.nix,hostname}"
    info "[DRY-RUN] configuration.nix would contain:"
    render_configuration
else
    mkdir -p "$OUT_DIR"
    render_flake > "$OUT_DIR/flake.nix"
    render_configuration > "$OUT_DIR/configuration.nix"
    if [ -f /etc/nixos/hardware-configuration.nix ]; then
        cp /etc/nixos/hardware-configuration.nix "$OUT_DIR/hardware-configuration.nix"
        ok "Copied your hardware-configuration.nix from /etc/nixos."
    else
        note "No /etc/nixos/hardware-configuration.nix found; generate one with 'nixos-generate-config' and place it in $OUT_DIR."
    fi
    # Nix flakes only see git-tracked files. Make the generated config a
    # self-contained git repo so 'nixos-rebuild --flake ./nixos-example' works
    # even when this wizard is run from inside another (this) git clone.
    if command -v git &> /dev/null && [ ! -d "$OUT_DIR/.git" ]; then
        git -C "$OUT_DIR" init -q
        git -C "$OUT_DIR" add -A
        ok "Initialized $OUT_DIR as a git repo (required for flakes)."
    fi
    ok "Generated $OUT_DIR"
fi

echo ""
echo -e "${CYAN}>>> NEXT STEPS (run these yourself)${NC}"
echo ""
echo "  1. Review the generated files:"
echo "       \$EDITOR $OUT_DIR/configuration.nix"
echo ""
echo "  2. Merge your existing system settings (bootloader, filesystems,"
echo "     users) — the generated config intentionally contains ONLY the"
echo "     desktop pieces plus a minimal user entry."
echo ""
echo "  3. Apply:"
echo "       sudo nixos-rebuild switch --flake $OUT_DIR#$HOSTNAME_NOW"
if [[ "$FLAKES_STATE" == not* ]]; then
    echo "     (first run may need: --extra-experimental-features 'nix-command flakes')"
fi
echo ""
echo "  Alternatively, import '$FLAKE_URL' (or github:zhafrandzaky/my-i3wm-x11?dir=nixos)"
echo "  directly from your own flake and enable services.i3wm-x11 there."
echo ""
