#!/bin/bash
#
# Arch Linux installer for the i3wm-x11 dotfiles.
# Run directly or via the root install.sh dispatcher.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/arch-i3wm-install.log"

DISTRO_TITLE="ARCH • I3WM • X11"
DISTRO_STACK="Arch Linux + i3wm"
DISTRO_LABEL="ARCH LINUX"

source "$REPO_ROOT/common/lib/installer-common.sh"

install_pkg() {
    local category="$1"
    local pkgs="$2"

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping install for $category: $pkgs"
        return 0
    fi

    log "Installing $category..."
    yay -S --noconfirm --needed $pkgs 2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK] $category Installed.${NC}"
    else
        warn "Some packages in $category failed to install. Check log at $LOG_FILE."
    fi
}

#  MAIN EXECUTION

parse_flags "$@"
show_header
preflight_checks

# AUR HELPER (YAY)
log "Checking AUR Helper (yay)..."
if ! command -v yay &> /dev/null && [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}Yay not found. Installing base-devel & yay...${NC}"
    sudo pacman -S --noconfirm base-devel git
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm
    cd "$REPO_ROOT" || exit
fi

# CONFLICT HANDLING
log "Checking for conflicting packages..."
if [ "$DRY_RUN" = false ]; then
    CONFLICTS=("i3lock" "picom" "picom-ibhagwan-git" "nitrogen")
    for pkg in "${CONFLICTS[@]}"; do
        if pacman -Qq "$pkg" &> /dev/null; then
            warn "Removing conflict: $pkg"
            sudo pacman -Rdd --noconfirm "$pkg"
        fi
    done
fi

# PACKAGE INSTALLATION
echo -e "\n${CYAN}>>> PACKAGE SELECTION${NC}"

# Core Packages Grouping
PKG_XORG="xorg-server xorg-xinit xorg-xset xorg-xrandr"
PKG_WM="i3-wm polybar rofi dunst i3lock-color-git picom-git xss-lock autotiling python-i3ipc libnotify"
PKG_SYS="brightnessctl xfce4-power-manager polkit-gnome lxappearance qt5ct"
PKG_NET="network-manager-applet blueman"
PKG_AUDIO="pavucontrol playerctl"
PKG_APPS="flameshot dmenu zenity imagemagick feh mpv"
PKG_CLI="jq progress curl htop neovim python-pynvim npm xclip ripgrep nano less tree bat fd python-pywal"
PKG_THEMES="papirus-icon-theme arc-gtk-theme papirus-folders-git"

PKGS_CORE="$PKG_XORG $PKG_WM $PKG_SYS $PKG_NET $PKG_AUDIO $PKG_APPS $PKG_CLI $PKG_THEMES"

install_pkg "Core System (WM, Utils & Rice Tools)" "$PKGS_CORE"

if ask_user "Install Modern Terminal Environment (Kitty, Zsh, Starship, Fastfetch)?" "Y"; then
    PKGS_TERM="kitty zsh starship fastfetch eza bat zsh-syntax-highlighting zsh-autosuggestions fzf"
    install_pkg "Terminal Tools" "$PKGS_TERM"
fi

if ask_user "Install Mega Font Pack (Coding, Emoji, CJK Support)?" "Y"; then
    PKGS_FONTS="ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols \
                ttf-fira-code ttf-hack-nerd ttf-cascadia-code ttf-ibm-plex \
                noto-fonts-emoji noto-fonts-cjk otf-font-awesome \
                ttf-material-design-icons-desktop-git"
    install_pkg "Fonts" "$PKGS_FONTS"
fi

if ask_user "Install File Manager Tools (Thunar + Archive Support)?" "Y"; then
    PKGS_FILE="thunar thunar-archive-plugin thunar-volman file-roller gvfs gvfs-mtp unzip 7zip unrar"
    install_pkg "File Management" "$PKGS_FILE"
fi

if ask_user "Install Web Browser (Firefox)?" "Y"; then
    install_pkg "Firefox" "firefox"
fi

if ask_user "Install Web Browser (Chromium)? (Optional)" "N"; then
    install_pkg "Chromium" "chromium"
fi

if ask_user "Install Web Browser (Brave)? (Optional)" "N"; then
    install_pkg "Brave" "brave-bin"
fi

if ask_user "Install Basic Dev Tools (Git, Python, VSCode-Bin)?" "Y"; then
    PKGS_DEV="git python python-pip visual-studio-code-bin \
              tk python-gobject python-cairo python-matplotlib python-pillow"
    install_pkg "Developer Tools" "$PKGS_DEV"
fi

# CONFIGURATION DEPLOYMENT
deploy_all_configs

# INITIALIZE WALLPAPER DIRECTORY
setup_wallpapers

# SYSTEM HARDENING & FIXES
apply_system_fixes "video,input,storage,audio"

final_message
