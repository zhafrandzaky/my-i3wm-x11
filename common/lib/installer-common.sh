#!/usr/bin/env bash
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

# Transactional rollback engine (records every mutation for uninstall.sh).
# shellcheck source=/dev/null
source "$COMMON_DIR/lib/rollback.sh"

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
    echo -e "${RED} // DEV: zhafrandzaky${NC}"
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

    local existed_before="false" backup_path="-"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        existed_before="true"
        local base_name=$(basename "$dest")
        if [[ "$dest" != "$BACKUP_DIR"* ]]; then
            backup_path="$BACKUP_DIR/${base_name}_old"
            cp -r "$dest" "$backup_path"
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

    # Record the operation for rollback ("replace" if we backed something up).
    if [ "$existed_before" = true ]; then
        rollback_record_file "replace" "$dest" "$backup_path" "true"
    else
        rollback_record_file "create" "$dest" "-" "false"
    fi
}

#  SHARED INSTALL PHASES

preflight_checks() {
    log "Checking internet connection..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        # ICMP may be unavailable (containers, filtered networks); fall back to HTTPS
        curl -fsI --max-time 10 https://deb.debian.org &> /dev/null \
            || curl -fsI --max-time 10 https://archlinux.org &> /dev/null \
            || error "No Internet Connection!"
    fi

    log "Checking sudo access..."
    if ! sudo -v; then
        # Common on Debian text-installer runs where a root password was set:
        # the created user is not in the sudo group.
        error "Sudo access required. If your user lacks sudo, run as root: usermod -aG sudo $USER  (then log out and back in)."
    fi
    # Keep sudo alive
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    log "Preparing Backup Directory..."
    if [ "$DRY_RUN" = false ]; then
        mkdir -m 700 -p "$BACKUP_DIR"
        log "Backup location: $BACKUP_DIR"
        # Open a rollback transaction: from here on, every mutation is recorded.
        local rb_distro="unknown"
        command -v pacman >/dev/null 2>&1 && rb_distro="arch"
        command -v apt-get >/dev/null 2>&1 && rb_distro="debian"
        rollback_begin "$rb_distro" "1.2.1" "$BACKUP_DIR"
        log "Rollback transaction: $RB_ID"
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

    # Deploy i3 Scripts, Themes & shared runtime libraries
    deploy_config "$COMMON_DIR/scripts" "$HOME/.config/i3/scripts"
    deploy_config "$COMMON_DIR/themes" "$HOME/.config/i3/themes"
    deploy_config "$COMMON_DIR/lib" "$HOME/.config/i3/lib"
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
        local udev_existed="false"
        [ -e /etc/udev/rules.d/90-backlight.rules ] && udev_existed="true"
        echo 'ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video /sys/class/backlight/%k/brightness"' | sudo tee /etc/udev/rules.d/90-backlight.rules > /dev/null
        echo 'ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"' | sudo tee -a /etc/udev/rules.d/90-backlight.rules > /dev/null
        sudo udevadm control --reload-rules
        sudo udevadm trigger
        rollback_record_udev "/etc/udev/rules.d/90-backlight.rules" "$udev_existed"

        log "Configuring Python Matplotlib Backend..."
        local mpl_existed="false"
        [ -e "$HOME/.config/matplotlib/matplotlibrc" ] && mpl_existed="true"
        mkdir -p "$HOME/.config/matplotlib"
        echo "backend: TkAgg" > "$HOME/.config/matplotlib/matplotlibrc"
        if [ "$mpl_existed" = false ]; then
            rollback_record_file "create" "$HOME/.config/matplotlib/matplotlibrc" "-" "false"
        fi

        log "Adding user to required groups..."
        local group
        for group in ${user_groups//,/ }; do
            if getent group "$group" > /dev/null; then
                # Only record groups the user was not already a member of.
                if ! id -nG "$USER" | tr ' ' '\n' | grep -qx "$group"; then
                    sudo usermod -aG "$group" "$USER" && rollback_record_group "$group"
                fi
            else
                warn "Group '$group' does not exist on this system. Skipping."
            fi
        done

        log "Changing Default Shell to Zsh..."
        local shell_before
        shell_before=$(getent passwd "$USER" | cut -d: -f7)
        if [ "$shell_before" != "/usr/bin/zsh" ] && [ -x /usr/bin/zsh ]; then
            # Via sudo: chsh run as the user would prompt for a password
            if sudo chsh -s /usr/bin/zsh "$USER"; then
                rollback_record_shell "$shell_before" "/usr/bin/zsh"
            fi
        fi

        log "Applying Default Theme (Pro-Dark)..."
        bash "$HOME/.config/i3/scripts/theme_switcher.sh" "pro-dark"

        # Seal the rollback transaction: diff packages, write + validate the
        # manifest. Abort loudly if it fails — a silent broken manifest would
        # make uninstall.sh a no-op that falsely reports success.
        log "Finalizing rollback transaction..."
        if ! rollback_finalize; then
            error "Rollback manifest generation FAILED. The desktop is installed, but uninstall.sh would not be able to undo it. Check $LOG_FILE and re-run, or report this. (Not printing success.)"
        fi
        log "Rollback manifest validated: $RB_DIR/manifest.json"
    else
        log "[DRY-RUN] Skipping permissions, udev rules, and shell changes."
    fi
}

final_message() {
    echo -e "${GREEN}"
    echo " "
    echo "   INSTALLATION SUCCESSFUL!"
    echo "   Github: zhafrandzaky"
    echo " "
    echo "   [!] IMPORTANT:"
    echo "   1. A reboot is REQUIRED for brightness & group permissions to work."
    echo "   2. Select 'i3' session at login screen."
    echo "   3. Backup of your old configs is at: $BACKUP_DIR"
    echo "   4. First boot will prompt for default browser setup."
    echo "   5. Don't forget to give a star on GitHub if you like the setup! :)"
    echo "   6. To fully undo this installation, run: ./uninstall.sh"
    echo " "
    echo -e "${NC}"

    if ask_user "Do you want to reboot now?" "N"; then
        reboot
    else
        echo "Please reboot manually later."
    fi
}
