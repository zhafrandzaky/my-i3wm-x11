# MY-I3WM-X11

![Arch Linux](https://img.shields.io/badge/OS-Arch_Linux-33b7ff?style=for-the-badge&logo=archlinux&logoColor=white)
![Debian](https://img.shields.io/badge/OS-Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Window Manager](https://img.shields.io/badge/WM-i3wm-black?style=for-the-badge&logo=i3&logoColor=white)
![Shell](https://img.shields.io/badge/Shell-Zsh-black?style=for-the-badge&logo=zsh&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

A highly modular, robust, and fully automated dotfiles deployment for **Arch Linux** and **Debian** (X11). This project transforms a base installation into a fully functional, aesthetically pleasing, and highly productive desktop environment with just one script — and the desktop looks and behaves identically on both distros.

## Key Features

- **Multi-Distro Monorepo:** One shared set of configs, scripts, and themes (`common/`) with distro-specific installers (`arch/`, `debian/`). The root `install.sh` auto-detects your distro.
- **Bulletproof Installer:** Automated deployment with safe backup mechanisms, `sudo` keep-alive, strict path resolution, and advanced flags (`--dry-run` and `--link` for developers).
- **Dynamic Theming Engine:** Built-in Python script (`theme_builder.py`) using `pywal` to automatically generate system-wide color schemes (Polybar, Rofi, Dunst, i3) instantly from any wallpaper. Includes static themes (`Pro Dark`) out of the box.
- **True Multi-Monitor Support:** Polybar automatically detects and scales across all connected displays seamlessly.
- **Instant Keybinding Cheatsheet:** Never forget a shortcut. Press `Mod + F1` to instantly parse and view all your active i3 keybindings via an elegant Rofi menu.
- **Blazing Fast Terminal Environment:** Pre-configured `Zsh` with `Starship` prompt (async Git fetching enabled) and dynamic `Fastfetch` presets.
- **Custom Rofi Tooling:** Specialized Rofi menus for:
  - Network Management (`nmcli` GUI)
  - Power Menu
  - Theme / Wallpaper Switcher
  - Dashboard
- **First Boot Greeter:** Interactive setup upon first login to configure default applications like your web browser.

---

## Directory Structure

```text
MY-I3WM-X11/
├── install.sh        # Main entry point: detects distro, runs the right installer
├── arch/
│   └── install.sh    # Arch Linux installer (pacman + yay/AUR)
├── debian/
│   └── install.sh    # Debian installer (apt + source builds for AUR-only tools)
├── common/           # Everything shared between distros
│   ├── configs/      # Base configurations (i3, polybar, rofi, dunst, kitty, picom, fastfetch)
│   ├── scripts/      # The brain behind the rice (pywal generator, network, battery, etc.)
│   ├── themes/       # Static theme bases (Pro-Dark) and Pywal targets
│   ├── lib/          # Shared installer functions
│   └── .zshrc        # Custom Zsh configuration (distro-aware aliases & plugin paths)
├── LICENSE
└── README.md
```

---

## Prerequisites

Before running the installer, ensure you have:

1. A fresh or existing **Arch Linux** or **Debian 12+ (Debian 13 "trixie" recommended)** installation (X11 environment).
2. An active internet connection.
3. A user account with `sudo` privileges (on Debian: make sure your user is in the `sudo` group).

> **Debian note:** Debian 13 (trixie) is recommended. On Debian 12 (bookworm) most things work, but `polybar` is older than 3.7 and does not support the `internal/tray` systray module — the bar will still run, minus the tray.

---

## Installation

Clone the repository and run the installation script. The script detects your distro, installs the necessary packages (AUR via `yay` on Arch; apt plus official upstream sources on Debian), backs up your existing dotfiles, and deploys the new configurations.

```bash
git clone https://github.com/zhafrandzaky/my-i3wm-x11.git
cd my-i3wm-x11
./install.sh
```

You can also run a distro installer directly:

```bash
./arch/install.sh     # Arch Linux
./debian/install.sh   # Debian
```

### Advanced Installer Flags (For Developers)

- `./install.sh --dry-run` : Simulates the installation process without making any actual changes to your system or installing packages. Perfect for reviewing what the script does.
- `./install.sh --link` : Uses `symlinks` instead of copying files. Ideal if you plan to modify the dotfiles and want the changes reflected immediately in your cloned Git repository.

Both flags also work when calling `arch/install.sh` or `debian/install.sh` directly.

---

## How Debian Gets Feature Parity

Several components of this rice are AUR-only or missing from Debian's repositories. The Debian installer fills every gap so the desktop looks and behaves the same:

| Arch (AUR/repo) | Debian equivalent |
| --- | --- |
| `i3lock-color-git` | Built from source ([Raymo111/i3lock-color](https://github.com/Raymo111/i3lock-color)) → `/usr/local/bin/i3lock` |
| `picom-git` | `picom` (Debian repo; supports blur + rounded corners) |
| `autotiling` | Installed via `pipx`, symlinked into `/usr/local/bin` |
| `papirus-folders-git` | Installed from [upstream GitHub](https://github.com/PapirusDevelopmentTeam/papirus-folders) |
| `brave-bin` | Official Brave apt repository |
| `visual-studio-code-bin` | Official Microsoft apt repository |
| `ttf-jetbrains-mono-nerd`, `ttf-hack-nerd`, `ttf-nerd-fonts-symbols` | Downloaded from [nerd-fonts releases](https://github.com/ryanoasis/nerd-fonts) into `~/.local/share/fonts` |
| `ttf-material-design-icons-desktop-git` | Downloaded from [Templarian/MaterialDesign-Font](https://github.com/Templarian/MaterialDesign-Font) |
| `starship` | apt if available, otherwise the official starship.rs installer |
| `fastfetch` | apt if available, otherwise the official `.deb` from GitHub releases |
| `eza` | apt if available, otherwise the official `deb.gierens.de` repository |
| `firefox` | `firefox-esr` (the `Mod+b` binding and first-boot greeter handle both) |
| `bat`, `fd` | `bat`/`fd-find` (Debian's `batcat`/`fdfind` are symlinked to the standard names) |
| `polkit-gnome` | `policykit-1-gnome` (the i3 config finds the agent on either path) |
| `unrar` | `unrar-free` |

Other niceties handled automatically on Debian: `pipewire-pulse`/`pulseaudio-utils` for the volume keys and the Polybar audio module, `libnotify-bin` for `notify-send`, and the Polybar launcher icon / Fastfetch logo automatically switch to the Debian logo on Debian (and stay the Arch logo on Arch).

---

## Workflow & Keybindings

Once installed and rebooted, log into the `i3` session. Your main modifier key (`$mod`) is typically the **Windows/Super key**.

### The Most Important Shortcut

> **Press `$mod + F1**` at any time to open the **Rofi Cheatsheet**. It dynamically reads your `i3/config` and displays all available shortcuts!

### Basic Navigation

| Keybinding | Action |
| --- | --- |
| `$mod + Enter` | Open Terminal (Kitty) |
| `$mod + d` | Open App Launcher (Rofi) |
| `$mod + q` | Close focused window |
| `$mod + [1-9]` | Switch to workspace 1-9 |
| `$mod + Shift + [1-9]` | Move focused window to workspace 1-9 |

### System & Scripts

| Keybinding | Action |
| --- | --- |
| `$mod + Shift + e` | Open Power Menu |
| `$mod + Shift + n` | Open Network Manager |
| `$mod + t` | Open Theme (pro-dark, custom pywall) |
| `$mod + Shift + w` | Wallpaper Switcher |
| `$mod + Shift + d` | Open Rofi Dashboard |
| `$mod + Shift + x` | Lockscreen |

---

## Managing Themes & Wallpapers

You can change your system's entire look with a few clicks.

1. **Open the Gallery:** Run the Wallpaper Manager via Rofi.
2. **Import or Select:** Choose an existing image or import a new one.
3. **Dynamic Generation:** Upon selecting an image, you will be prompted to either "Set Wallpaper Only" or **"Generate Dynamic Theme (Pywal)"**.
4. Selecting Pywal will instantly re-color your *Polybar*, *Rofi*, *Dunst notifications*, and *i3 borders* to match your wallpaper!

---

### Interactive Weather Module

A lightweight, API-free weather module integrated into Polybar, utilizing `wttr.in` with smart caching and dynamic GUI interactions.

**Key Features:**
**API-Free & Efficient:** Retrieves data directly from `wttr.in`—no API keys or registration required.
**Smart RAM Caching:** Stores weather data in `/tmp` for 15 minutes to minimize network requests, ensure instant bar reloads, and prevent server rate-limiting.
**Dynamic GUI Setup:** Prompts for a default city via `zenity` during `first_setup.sh`. Unconfigured states elegantly fallback to a "Set Location" module prompt.

**Interactive Mouse Bindings:**
**Left-Click:** Displays a detailed forecast tooltip (feels-like temperature, wind, humidity, moon phase) via `dunst`.
**Right-Click:** Opens a `rofi` prompt to update the target city on-the-fly without manually editing configuration files.

**Dependencies:** `curl`, `rofi`, `libnotify`, `zenity` *(handled automatically by the installer)*.

---

### System Updates Module

The Polybar updates module works on both distros:

- **Arch:** counts official updates via `checkupdates` and AUR updates via `yay -Qua`; right-click launches `yay -Syu` in Kitty.
- **Debian:** counts upgradable packages via a simulated `apt-get dist-upgrade` (no root needed); right-click launches `sudo apt update && sudo apt full-upgrade` in Kitty.

---

## Contributing

Contributions, issues, and feature requests are welcome!
Feel free to check issues page if you want to contribute.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'feat: Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## License

Distributed under the MIT License. See `LICENSE` for more information.

---

*Built by Ziona Zyy.*
