#!/usr/bin/env bash
#
# Debian installer for the i3wm-x11 dotfiles.
# Run directly or via the root install.sh dispatcher.
#
# Mirrors the Arch installer feature-for-feature:
#   - pacman/yay packages         -> apt equivalents
#   - i3lock-color-git (AUR)      -> built from source (github.com/Raymo111/i3lock-color)
#   - picom-git (AUR)             -> picom (Debian repo, supports blur + rounded corners)
#   - autotiling (repo)           -> installed via pipx
#   - papirus-folders-git (AUR)   -> installed from upstream GitHub
#   - brave-bin (AUR)             -> official Brave apt repository
#   - visual-studio-code-bin (AUR)-> official Microsoft apt repository
#   - Nerd Fonts (ttf-*-nerd)     -> downloaded from nerd-fonts GitHub releases
#   - starship / fastfetch / eza  -> apt when available, official fallbacks otherwise

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/debian-i3wm-install.log"

DISTRO_TITLE="DEBIAN • I3WM • X11"
DISTRO_STACK="Debian + i3wm"
DISTRO_LABEL="DEBIAN"

source "$REPO_ROOT/common/lib/installer-common.sh"

export DEBIAN_FRONTEND=noninteractive

install_pkg() {
    local category="$1"
    local pkgs="$2"

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping install for $category: $pkgs"
        return 0
    fi

    log "Installing $category..."
    if sudo apt-get install -y $pkgs 2>> "$LOG_FILE"; then
        echo -e "${GREEN}[OK] $category Installed.${NC}"
        return 0
    fi

    # One uninstallable package aborts the whole apt transaction; retry
    # per package so a single bad name cannot take down the entire group.
    warn "Group install for $category failed. Retrying packages individually..."
    local failed=""
    local pkg
    for pkg in $pkgs; do
        sudo apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1 || failed="$failed $pkg"
    done

    if [ -z "$failed" ]; then
        echo -e "${GREEN}[OK] $category Installed.${NC}"
    else
        warn "Failed to install from $category:$failed. Check log at $LOG_FILE."
    fi
}

# Returns 0 if the package is actually installable (has a real candidate version;
# apt-cache show alone also matches removed/virtual packages)
apt_has_pkg() {
    local candidate
    candidate=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}')
    [ -n "$candidate" ] && [ "$candidate" != "(none)" ] && [ "$candidate" != "none" ]
}

#  AUR-EQUIVALENT BUILDS & FALLBACKS

build_i3lock_color() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping i3lock-color source build."
        return 0
    fi

    if [ -x /usr/local/bin/i3lock ]; then
        log "i3lock-color already installed at /usr/local/bin/i3lock. Skipping build."
        return 0
    fi

    log "Building i3lock-color from source (Debian has no package for it)..."

    local build_deps="autoconf automake gcc make pkg-config libpam0g-dev libcairo2-dev \
                      libfontconfig1-dev libxcb-composite0-dev libev-dev libx11-xcb-dev \
                      libxcb-xkb-dev libxcb-xinerama0-dev libxcb-randr0-dev libxcb-image0-dev \
                      libxcb-util0-dev libxcb-xrm-dev libxkbcommon-dev libxkbcommon-x11-dev \
                      libjpeg-dev libgif-dev"
    sudo apt-get install -y $build_deps 2>> "$LOG_FILE"

    rm -rf /tmp/i3lock-color
    if git clone https://github.com/Raymo111/i3lock-color.git /tmp/i3lock-color 2>> "$LOG_FILE"; then
        # Install under /usr/local so we never touch /usr/bin/i3lock: dpkg owns that
        # path via Debian's i3lock package (a Recommends of i3), and overwriting it
        # would get clobbered by dpkg on remove/upgrade. /usr/local/bin wins in PATH.
        # --sysconfdir=/etc keeps the PAM service file where PAM actually looks.
        (
            cd /tmp/i3lock-color || exit 1
            autoreconf -fi >> "$LOG_FILE" 2>&1 \
                && mkdir -p build && cd build \
                && ../configure --prefix=/usr/local --sysconfdir=/etc >> "$LOG_FILE" 2>&1 \
                && make >> "$LOG_FILE" 2>&1 \
                && sudo make install >> "$LOG_FILE" 2>&1
        )
        if [ -x /usr/local/bin/i3lock ]; then
            echo -e "${GREEN}[OK] i3lock-color installed to /usr/local/bin/i3lock.${NC}"
        else
            warn "i3lock-color build failed. Lockscreen will not work until fixed. Check $LOG_FILE."
        fi
    else
        warn "Could not clone i3lock-color repository."
    fi
}

install_autotiling() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping autotiling install."
        return 0
    fi

    if command -v autotiling &> /dev/null; then
        log "autotiling already installed. Skipping."
        return 0
    fi

    log "Installing autotiling via pipx (not packaged in Debian)..."
    sudo apt-get install -y pipx python3-venv 2>> "$LOG_FILE"
    pipx install autotiling >> "$LOG_FILE" 2>&1

    if [ -x "$HOME/.local/bin/autotiling" ]; then
        # i3 autostart may not have ~/.local/bin in PATH; expose it system-wide
        sudo ln -sf "$HOME/.local/bin/autotiling" /usr/local/bin/autotiling
        echo -e "${GREEN}[OK] autotiling installed.${NC}"
    else
        warn "autotiling install failed. Check $LOG_FILE."
    fi
}

install_papirus_folders() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping papirus-folders install."
        return 0
    fi

    if command -v papirus-folders &> /dev/null; then
        log "papirus-folders already installed. Skipping."
        return 0
    fi

    log "Installing papirus-folders from upstream GitHub (not packaged in Debian)..."
    rm -rf /tmp/papirus-folders
    if git clone --depth 1 https://github.com/PapirusDevelopmentTeam/papirus-folders.git /tmp/papirus-folders 2>> "$LOG_FILE"; then
        sudo install -m 755 /tmp/papirus-folders/papirus-folders /usr/local/bin/papirus-folders
        echo -e "${GREEN}[OK] papirus-folders installed.${NC}"
    else
        warn "Could not clone papirus-folders repository."
    fi
}

install_nerd_fonts() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping Nerd Fonts download."
        return 0
    fi

    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"

    local font
    for font in JetBrainsMono Hack NerdFontsSymbolsOnly; do
        if [ -d "$font_dir/$font" ] && [ -n "$(ls -A "$font_dir/$font" 2>/dev/null)" ]; then
            log "Nerd Font '$font' already present. Skipping."
            continue
        fi

        log "Downloading Nerd Font: $font..."
        if curl -fL --max-time 300 -o "/tmp/${font}.zip" \
            "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip" 2>> "$LOG_FILE"; then
            mkdir -p "$font_dir/$font"
            unzip -o -q "/tmp/${font}.zip" -d "$font_dir/$font" >> "$LOG_FILE" 2>&1
            rm -f "/tmp/${font}.zip"
            echo -e "${GREEN}[OK] Nerd Font '$font' installed.${NC}"
        else
            warn "Failed to download Nerd Font '$font'. Polybar/Kitty icons may look wrong."
        fi
    done

    # Material Design Icons (AUR: ttf-material-design-icons-desktop-git)
    if [ ! -f "$font_dir/MaterialDesignIconsDesktop.ttf" ]; then
        log "Downloading Material Design Icons font..."
        curl -fL --max-time 120 -o "$font_dir/MaterialDesignIconsDesktop.ttf" \
            "https://raw.githubusercontent.com/Templarian/MaterialDesign-Font/master/MaterialDesignIconsDesktop.ttf" 2>> "$LOG_FILE" \
            || warn "Failed to download Material Design Icons font."
    fi

    log "Refreshing font cache..."
    fc-cache -f >> "$LOG_FILE" 2>&1
}

install_starship() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping starship install."
        return 0
    fi

    if command -v starship &> /dev/null; then
        log "starship already installed. Skipping."
        return 0
    fi

    if apt_has_pkg starship; then
        install_pkg "Starship (apt)" "starship"
    else
        log "Installing starship via official installer (not packaged in this Debian release)..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y >> "$LOG_FILE" 2>&1
        if command -v starship &> /dev/null; then
            echo -e "${GREEN}[OK] starship installed.${NC}"
        else
            warn "starship install failed. Check $LOG_FILE."
        fi
    fi
}

install_fastfetch() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping fastfetch install."
        return 0
    fi

    if command -v fastfetch &> /dev/null; then
        log "fastfetch already installed. Skipping."
        return 0
    fi

    if apt_has_pkg fastfetch; then
        install_pkg "Fastfetch (apt)" "fastfetch"
        return 0
    fi

    log "Installing fastfetch from GitHub releases (not packaged in this Debian release)..."
    local deb_arch ff_arch
    deb_arch=$(dpkg --print-architecture)
    case "$deb_arch" in
        amd64) ff_arch="amd64" ;;
        arm64) ff_arch="aarch64" ;;
        armhf) ff_arch="armv7l" ;;
        *)
            warn "No fastfetch build for architecture '$deb_arch'. Skipping."
            return 1
            ;;
    esac

    if curl -fL --max-time 300 -o /tmp/fastfetch.deb \
        "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${ff_arch}.deb" 2>> "$LOG_FILE"; then
        sudo apt-get install -y /tmp/fastfetch.deb 2>> "$LOG_FILE" \
            && echo -e "${GREEN}[OK] fastfetch installed.${NC}" \
            || warn "fastfetch .deb install failed. Check $LOG_FILE."
        rm -f /tmp/fastfetch.deb
    else
        warn "Failed to download fastfetch."
    fi
}

install_eza() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping eza install."
        return 0
    fi

    if command -v eza &> /dev/null; then
        log "eza already installed. Skipping."
        return 0
    fi

    if apt_has_pkg eza; then
        install_pkg "Eza (apt)" "eza"
        return 0
    fi

    log "Adding official eza apt repository (deb.gierens.de)..."
    sudo mkdir -p /etc/apt/keyrings
    if curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc 2>> "$LOG_FILE" \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg; then
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
            | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
        sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
        sudo apt-get update 2>> "$LOG_FILE"
        install_pkg "Eza" "eza"
    else
        warn "Failed to set up eza repository. 'ls' aliases will fall back to plain ls."
    fi
}

install_polkit_agent() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping polkit agent install."
        return 0
    fi

    # policykit-1-gnome (bookworm) was removed in trixie; fall back to the
    # MATE or LXDE agents. The i3 config autostart tries all their paths.
    local agent
    for agent in policykit-1-gnome mate-polkit lxpolkit; do
        if apt_has_pkg "$agent"; then
            install_pkg "Polkit Agent ($agent)" "$agent"
            return 0
        fi
    done
    warn "No polkit authentication agent available. GUI privilege prompts will not work."
}

install_pywal() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping pywal install."
        return 0
    fi

    if command -v wal &> /dev/null; then
        log "pywal already installed. Skipping."
        return 0
    fi

    if apt_has_pkg python3-pywal; then
        install_pkg "Pywal (apt)" "python3-pywal"
        return 0
    fi

    log "Installing pywal via pipx (removed from this Debian release)..."
    sudo apt-get install -y pipx python3-venv 2>> "$LOG_FILE"
    pipx install pywal >> "$LOG_FILE" 2>&1

    if [ -x "$HOME/.local/bin/wal" ]; then
        # theme_builder.py invokes 'wal'; i3-spawned processes may lack ~/.local/bin in PATH
        sudo ln -sf "$HOME/.local/bin/wal" /usr/local/bin/wal
        echo -e "${GREEN}[OK] pywal installed.${NC}"
    else
        warn "pywal install failed. Dynamic Pywal theming will not work. Check $LOG_FILE."
    fi
}

install_ibm_plex() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping IBM Plex font install."
        return 0
    fi

    if apt_has_pkg fonts-ibm-plex; then
        install_pkg "IBM Plex (apt)" "fonts-ibm-plex"
        return 0
    fi

    local font_dir="$HOME/.local/share/fonts/IBMPlex"
    if [ -d "$font_dir" ] && [ -n "$(ls -A "$font_dir" 2>/dev/null)" ]; then
        log "IBM Plex fonts already present. Skipping."
        return 0
    fi

    log "Downloading IBM Plex fonts from upstream GitHub (removed from this Debian release)..."
    if curl -fL --max-time 300 -o /tmp/ibm-plex.zip \
        "https://github.com/IBM/plex/releases/download/v6.4.0/TrueType.zip" 2>> "$LOG_FILE"; then
        mkdir -p "$font_dir"
        unzip -o -q /tmp/ibm-plex.zip -d "$font_dir" >> "$LOG_FILE" 2>&1
        rm -f /tmp/ibm-plex.zip
        echo -e "${GREEN}[OK] IBM Plex fonts installed.${NC}"
    else
        warn "Failed to download IBM Plex fonts (cosmetic only; no config depends on them)."
    fi
}

setup_cli_symlinks() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping bat/fd compatibility symlinks."
        return 0
    fi

    # Debian renames the binaries: bat -> batcat, fd -> fdfind
    mkdir -p "$HOME/.local/bin"
    if command -v batcat &> /dev/null && ! command -v bat &> /dev/null; then
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
        log "Symlinked bat -> batcat"
    fi
    if command -v fdfind &> /dev/null && ! command -v fd &> /dev/null; then
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        log "Symlinked fd -> fdfind"
    fi
}

install_brave() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping Brave install."
        return 0
    fi

    if command -v brave-browser &> /dev/null; then
        log "Brave already installed. Skipping."
        return 0
    fi

    log "Adding official Brave apt repository..."
    if sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg 2>> "$LOG_FILE"; then
        echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
            | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
        sudo apt-get update 2>> "$LOG_FILE"
        install_pkg "Brave" "brave-browser"
    else
        warn "Failed to set up Brave repository."
    fi
}

install_vscode() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping VS Code install."
        return 0
    fi

    if command -v code &> /dev/null; then
        log "VS Code already installed. Skipping."
        return 0
    fi

    log "Adding official Microsoft VS Code apt repository..."
    sudo apt-get install -y gnupg 2>> "$LOG_FILE"
    sudo mkdir -p /etc/apt/keyrings
    if curl -fsSL https://packages.microsoft.com/keys/microsoft.asc 2>> "$LOG_FILE" \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg; then
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
            | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        sudo apt-get update 2>> "$LOG_FILE"
        install_pkg "VS Code" "code"
    else
        warn "Failed to set up VS Code repository."
    fi
}

#  MAIN EXECUTION

parse_flags "$@"
show_header
preflight_checks

# APT REFRESH
if [ "$DRY_RUN" = false ]; then
    log "Refreshing apt package lists..."
    sudo apt-get update 2>> "$LOG_FILE" || warn "apt update reported errors. Check $LOG_FILE."
fi

# CONFLICT HANDLING
log "Checking for conflicting packages..."
if [ "$DRY_RUN" = false ]; then
    CONFLICTS=("nitrogen")
    for pkg in "${CONFLICTS[@]}"; do
        if dpkg -s "$pkg" &> /dev/null; then
            warn "Removing conflict: $pkg"
            sudo apt-get remove -y "$pkg" 2>> "$LOG_FILE"
        fi
    done
fi

# PACKAGE INSTALLATION
echo -e "\n${CYAN}>>> PACKAGE SELECTION${NC}"

# Core Packages Grouping (apt equivalents of the Arch lists)
PKG_XORG="xserver-xorg xinit x11-xserver-utils"
PKG_WM="i3 polybar rofi dunst picom xss-lock python3-i3ipc libnotify-bin"
PKG_SYS="brightnessctl xfce4-power-manager lxappearance qt5ct dbus-x11 libglib2.0-bin xdg-utils xdg-user-dirs psmisc procps mesa-utils"
PKG_NET="network-manager network-manager-gnome blueman"
PKG_AUDIO="pavucontrol playerctl pipewire-pulse wireplumber pulseaudio-utils"
PKG_APPS="flameshot suckless-tools zenity imagemagick feh mpv"
PKG_CLI="jq progress curl wget gnupg htop neovim python3-pynvim npm xclip ripgrep nano less tree bat fd-find unzip git"
PKG_THEMES="papirus-icon-theme arc-theme"

PKGS_CORE="$PKG_XORG $PKG_WM $PKG_SYS $PKG_NET $PKG_AUDIO $PKG_APPS $PKG_CLI $PKG_THEMES"

install_pkg "Core System (WM, Utils & Rice Tools)" "$PKGS_CORE"

# AUR-equivalents required by the core setup
install_polkit_agent
build_i3lock_color
install_autotiling
install_papirus_folders
install_pywal
setup_cli_symlinks

if ask_user "Install Modern Terminal Environment (Kitty, Zsh, Starship, Fastfetch)?" "Y"; then
    PKGS_TERM="kitty zsh zsh-syntax-highlighting zsh-autosuggestions fzf"
    install_pkg "Terminal Tools" "$PKGS_TERM"
    install_starship
    install_fastfetch
    install_eza
fi

if ask_user "Install Mega Font Pack (Coding, Emoji, CJK Support)?" "Y"; then
    PKGS_FONTS="fonts-firacode fonts-cascadia-code \
                fonts-noto-color-emoji fonts-noto-cjk fonts-font-awesome fontconfig"
    install_pkg "Fonts (apt)" "$PKGS_FONTS"
    install_ibm_plex
    install_nerd_fonts
fi

if ask_user "Install File Manager Tools (Thunar + Archive Support)?" "Y"; then
    PKGS_FILE="thunar thunar-archive-plugin thunar-volman file-roller gvfs gvfs-backends gvfs-fuse unzip p7zip-full unrar-free"
    install_pkg "File Management" "$PKGS_FILE"
fi

if ask_user "Install Web Browser (Firefox ESR)?" "Y"; then
    install_pkg "Firefox ESR" "firefox-esr"
fi

if ask_user "Install Web Browser (Chromium)? (Optional)" "N"; then
    install_pkg "Chromium" "chromium"
fi

if ask_user "Install Web Browser (Brave)? (Optional)" "N"; then
    install_brave
fi

if ask_user "Install Basic Dev Tools (Git, Python, VSCode)?" "Y"; then
    PKGS_DEV="git python3 python3-pip python3-venv pipx \
              python3-tk python3-gi python3-gi-cairo python3-matplotlib python3-pil"
    install_pkg "Developer Tools" "$PKGS_DEV"
    install_vscode
fi

# CONFIGURATION DEPLOYMENT
deploy_all_configs

# INITIALIZE WALLPAPER DIRECTORY
setup_wallpapers

# SYSTEM HARDENING & FIXES
# Debian has no 'storage' group; plugdev covers removable media access.
apply_system_fixes "video,input,audio,plugdev"

final_message
