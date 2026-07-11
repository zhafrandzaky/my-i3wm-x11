# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-07-11

First public release: a fully automated i3wm (X11) desktop for **Arch Linux**
and **Debian**, restructured as a multi-distro monorepo. The Debian installer
was validated end-to-end on fresh Debian 13 (trixie) systems — repeated clean
Docker container installs plus an unattended QEMU/KVM virtual machine install
with graphical verification of every desktop component (Polybar, picom, Rofi,
Dunst, Kitty, lock screen, fonts, volume keys, first-boot greeter).

### Added

- Automated installer with dotfile backups, sudo keep-alive, conflict
  handling, and `--dry-run`/`--link` flags for both distributions.
- Multi-distro monorepo layout: shared assets in `common/` (configs, scripts,
  themes, `.zshrc`), distro-specific installers in `arch/` and `debian/`.
- Root `install.sh` entry point that detects the distribution via
  `/etc/os-release` (including `ID_LIKE` derivatives) and dispatches to the
  matching installer.
- Arch installer using `pacman` with AUR support bootstrapped via `yay`.
- Debian installer using `apt`, mirroring the Arch installer
  prompt-for-prompt, with equivalents for every AUR-only dependency:
  - `i3lock-color` built from upstream source into `/usr/local`.
  - `autotiling` installed via `pipx` with a system-wide symlink.
  - `papirus-folders` installed from upstream GitHub.
  - Brave and Visual Studio Code from their official apt repositories.
  - JetBrainsMono/Hack/Symbols Nerd Fonts and Material Design Icons downloaded
    from upstream releases into `~/.local/share/fonts`.
  - `starship`, `fastfetch`, and `eza` from apt when packaged, with official
    upstream fallbacks otherwise.
- Shared installer library (`common/lib/installer-common.sh`) with the backup,
  deployment, hardening, and prompt logic used by both installers.
- i3 window manager configuration with gaps, autotiling, and a documented
  keybinding scheme.
- Polybar setup with multi-monitor support and custom modules: workspaces,
  updates, weather (wttr.in with caching), battery, caffeine, backlight,
  audio, and system tray.
- Dynamic theming engine: static Pro Dark (Catppuccin Mocha) theme plus
  pywal-based theme generation from any wallpaper (`theme_builder.py`).
- Custom Rofi tooling: application launcher, power menu, network manager,
  media/calendar dashboard, keybinding cheatsheet, and wallpaper gallery.
- i3lock-color lock screen with blur, themed clock ring, and xss-lock
  integration.
- Terminal environment: Kitty, Zsh, Starship prompt, and randomized Fastfetch
  presets with custom artwork.
- First-boot greeter for default browser and weather location setup, with the
  browser menu built from installed `.desktop` files.
- Dunst notification theming, picom compositor configuration, and GTK/icon
  theme integration (Arc-Dark, Papirus).
- Dynamic distro awareness in shared assets:
  - `distro_icon.sh` shows the matching logo in the Polybar launcher module.
  - Fastfetch presets select the matching ASCII logo at generation time.
  - `updates.sh` counts and applies updates via `checkupdates`/`yay` on Arch
    and simulated `apt-get dist-upgrade` on Debian.
  - `.zshrc` selects `yay`/`pacman`/`apt` aliases, sources zsh plugins from
    both distros' paths, and falls back to Debian's `batcat`.
- Adaptive picom launcher (`picom_launch.sh`): keeps the GLX backend on real
  GPUs, falls back to xrender on software renderers (VMs), where GLX + vsync
  freezes the display.
- Polkit agent auto-selection on Debian (`policykit-1-gnome`, `mate-polkit`,
  or `lxpolkit`, whichever the release ships) with all agent paths tried in
  the i3 autostart.
- Compatibility symlinks on Debian: `bat` → `batcat`, `fd` → `fdfind`,
  `wal` and `autotiling` exposed in `/usr/local/bin`.
- Idempotent installers: source builds, font downloads, and vendor repository
  setup are skipped when already present, verified by repeated runs in the
  same environment.
- MIT license.

### Changed

- Default shell change uses `sudo chsh` so the installer never blocks on an
  interactive password prompt.
- Connectivity preflight falls back to HTTPS when ICMP is unavailable
  (containers, filtered networks).
- Debian package-group installs retry per package on failure so a single
  unavailable package cannot abort an entire group.
- Dunst is started explicitly at i3 session start instead of relying on D-Bus
  activation, which stalls under `startx` sessions.
- picom config uses the non-deprecated `_GTK_FRAME_EXTENTS@` rule syntax
  (silences warnings on picom ≥ 12 on both distros).

### Fixed

- i3lock-color build on Debian: install under `/usr/local` with
  `--sysconfdir=/etc` so dpkg never clobbers the binary when Debian's `i3lock`
  package changes, and add the missing `libgif-dev` build dependency.
- i3 `bindsym` commands containing `;` are double-quoted — i3 splits command
  lists on `;` even inside single quotes, which silently broke the browser
  keybinding.
- Debian 13 package removals handled: `policykit-1-gnome`, `python3-pywal`,
  and `fonts-ibm-plex` are no longer assumed to be installable; working
  alternatives are selected automatically.
- Package availability checks verify an installable candidate version —
  `apt-cache show` also matches removed or virtual packages.
- Current Arch package names: `ttf-font-awesome` → `otf-font-awesome`,
  `p7zip` → `7zip`.
- First-boot greeter set a nonexistent `brave.desktop` as default browser;
  Brave's actual desktop entry is `brave-browser.desktop`.
- `psmisc`/`procps` installed explicitly on Debian (`killall`/`pgrep` are
  required by the Polybar launcher and theme switcher).

[unreleased]: https://github.com/zhafrandzaky/my-i3wm-x11/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/zhafrandzaky/my-i3wm-x11/releases/tag/v1.0.0
