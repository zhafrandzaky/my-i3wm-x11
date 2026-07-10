#!/bin/bash
#
# Shared installer functions used by arch/install.sh and debian/install.sh.
# Callers must set (before sourcing):
#   REPO_ROOT     - absolute path to the repository root
#   LOG_FILE      - installer log path
#   DISTRO_TITLE  - header title line   (e.g. "ARCH • I3WM • X11")
#   DISTRO_STACK  - header stack line   (e.g. "Arch Linux + i3wm")
#   DISTRO_LABEL  - header banner label (e.g. "ARCH LINUX")

COMMON_DIR="$REPO_ROOT/common"
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

# Flags (parsed by parse_flags)
USE_SYMLINK=false
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

#  UTILITY FUNCTIONS

parse_flags() {
    for arg in "$@"; do
        case $arg in
            --link) USE_SYMLINK=true ;;
            --dry-run) DRY_RUN=true ;;
        esac
    done
}

show_header() {
    clear
    echo -e "${CYAN}"
    echo " $DISTRO_TITLE"
    echo " ╭──────────────────────────────────╮"
    printf " │  Stack     :  %-19s│\n" "$DISTRO_STACK"
    echo " │  Display   :  X11 (Xorg)         │"
    echo " │  Paradigm  :  Tiling WM          │"
    echo " ╰──────────────────────────────────╯"
    echo -e "${NC}"
    echo -e "${BLUE} // AUTOMATED INSTALLER & SETUP FOR ${DISTRO_LABEL}${NC}"
    echo -e "${RED} // DEV: adrenaline404${NC}"
    echo ""
}

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $(date): $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $(date): $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $(date): $1" >> "$LOG_FILE"
    exit 1
}

ask_user() {
    local prompt="$1"
    local default="$2"
    local choice

    if [ "$default" == "Y" ]; then
        echo -ne "${GREEN}?? $prompt [Y/n]: ${NC}"
        read choice
        choice=${choice:-Y}
    else
        echo -ne "${YELLOW}?? $prompt [y/N]: ${NC}"
        read choice
        choice=${choice:-N}
    fi

    [[ "$choice" =~ ^[Yy]$ ]]
}

deploy_config() {
    local src="$1"
    local dest="$2"

    local dest_dir=$(dirname "$dest")
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$dest_dir"
    fi

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Deploy: $src -> $dest"
        return
    fi

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        local base_name=$(basename "$dest")
        if [[ "$dest" != "$BACKUP_DIR"* ]]; then
            cp -r "$dest" "$BACKUP_DIR/${base_name}_old"
        fi
        rm -rf "$dest"
    fi

    if [ "$USE_SYMLINK" = true ]; then
        ln -sf "$src" "$dest"
        log "Symlinked: $src -> $dest"
    else
        cp -r "$src" "$dest"
        log "Copied: $src -> $dest"
    fi
}

#  SHARED INSTALL PHASES

preflight_checks() {
    log "Checking internet connection..."
    ping -c 1 8.8.8.8 &> /dev/null || error "No Internet Connection!"

    log "Checking sudo access..."
    if ! sudo -v; then
        error "Sudo access required for system configuration."
    fi
    # Keep sudo alive
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    log "Preparing Backup Directory..."
    if [ "$DRY_RUN" = false ]; then
        mkdir -m 700 -p "$BACKUP_DIR"
        log "Backup location: $BACKUP_DIR"
    fi
}

deploy_all_configs() {
    echo -e "\n${CYAN}>>> CONFIGURATION DEPLOYMENT${NC}"

    # Deploy standard configs from common/configs/ folder
    for dir in "$COMMON_DIR/configs"/*; do
        if [ -d "$dir" ] || [ -f "$dir" ]; then
            base_name=$(basename "$dir")
            deploy_config "$dir" "$HOME/.config/$base_name"
        fi
    done

    # Deploy Zshrc
    deploy_config "$COMMON_DIR/.zshrc" "$HOME/.zshrc"

    # Deploy i3 Scripts & Themes
    deploy_config "$COMMON_DIR/scripts" "$HOME/.config/i3/scripts"
    deploy_config "$COMMON_DIR/themes" "$HOME/.config/i3/themes"
}

setup_wallpapers() {
    if [ "$DRY_RUN" = false ]; then
        log "Setting up Default Wallpapers directory..."
        TARGET_WALLPAPER_DIR="$HOME/Wallpapers"
        mkdir -p "$TARGET_WALLPAPER_DIR"

        if [ -f "$COMMON_DIR/themes/pro-dark/wallpaper.jpg" ]; then
            cp "$COMMON_DIR/themes/pro-dark/wallpaper.jpg" "$TARGET_WALLPAPER_DIR/default_pro_dark.jpg"
            log "Copied default wallpaper to $TARGET_WALLPAPER_DIR"
        else
            warn "Default wallpaper.jpg not found in $COMMON_DIR/themes/pro-dark/"
        fi
    fi
}

# apply_system_fixes <group1,group2,...>
apply_system_fixes() {
    local user_groups="$1"

    echo -e "\n${CYAN}>>> SYSTEM HARDENING & FIXES${NC}"

    if [ "$DRY_RUN" = false ]; then
        log "Setting Executable Permissions..."
        chmod +x "$HOME/.config/i3/scripts/"*.sh
        chmod +x "$HOME/.config/polybar/launch.sh"
        chmod +x "$HOME/.config/i3/scripts/rofi_dashboard.sh" 2>/dev/null

        if [ -f "$HOME/.config/i3/scripts/theme_builder.py" ]; then
            chmod +x "$HOME/.config/i3/scripts/theme_builder.py"
        fi

        log "Generating Dynamic Fastfetch Presets..."
        bash "$HOME/.config/i3/scripts/setup_fastfetch.sh"

        log "Creating Udev Rules for Backlight Control..."
        echo 'ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video /sys/class/backlight/%k/brightness"' | sudo tee /etc/udev/rules.d/90-backlight.rules > /dev/null
        echo 'ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"' | sudo tee -a /etc/udev/rules.d/90-backlight.rules > /dev/null
        sudo udevadm control --reload-rules
        sudo udevadm trigger

        log "Configuring Python Matplotlib Backend..."
        mkdir -p "$HOME/.config/matplotlib"
        echo "backend: TkAgg" > "$HOME/.config/matplotlib/matplotlibrc"

        log "Adding user to required groups..."
        local group
        for group in ${user_groups//,/ }; do
            if getent group "$group" > /dev/null; then
                sudo usermod -aG "$group" "$USER"
            else
                warn "Group '$group' does not exist on this system. Skipping."
            fi
        done

        log "Changing Default Shell to Zsh..."
        if [ "$SHELL" != "/usr/bin/zsh" ]; then
            chsh -s /usr/bin/zsh
        fi

        log "Applying Default Theme (Pro-Dark)..."
        bash "$HOME/.config/i3/scripts/theme_switcher.sh" "pro-dark"
    else
        log "[DRY-RUN] Skipping permissions, udev rules, and shell changes."
    fi
}

final_message() {
    echo -e "${GREEN}"
    echo " "
    echo "   INSTALLATION SUCCESSFUL!"
    echo "   Github: adrenaline404"
    echo " "
    echo "   [!] IMPORTANT:"
    echo "   1. A reboot is REQUIRED for brightness & group permissions to work."
    echo "   2. Select 'i3' session at login screen."
    echo "   3. Backup of your old configs is at: $BACKUP_DIR"
    echo "   4. First boot will prompt for default browser setup."
    echo "   5. Don't forget to give a star on GitHub if you like the setup! :)"
    echo "   6. For issues, feedback, or contributions, visit the GitHub repo."
    echo " "
    echo -e "${NC}"

    if ask_user "Do you want to reboot now?" "N"; then
        reboot
    else
        echo "Please reboot manually later."
    fi
}
