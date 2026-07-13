# my-i3wm-x11 — Multi-Distro Architecture & NixOS Integration Design

**Status: DESIGN FREEZE (2026-07-13). Approved for review; implementation awaits
explicit approval. No code in this document is final API.**

Scope: adds NixOS as the third supported distribution, finalizes the distro
abstraction, and generalizes the project's runtime-detection philosophy. Target
platforms: Arch Linux (rolling), Debian 13+, NixOS 26.05.

---

## 1. Core principles

- **P1 — Runtime truth.** The *installed, running system* is the only source of
  truth. Behavior is decided by probing it (`/etc/os-release`, command
  availability, sysfs, systemd state) at the moment of use. Installation media,
  installer flavor, or provenance never drive behavior. ISO identity may be
  used **only** as an optional *hint* inside the automated VM-validation
  harness, and even there the console/system probe remains authoritative.
- **P2 — Provenance independence.** The repository must work identically
  regardless of how the OS was installed (Arch manual/archinstall; Debian
  netinst/DVD/graphical/text; NixOS graphical/minimal; future distros). The
  universal convergence contract is:
  `git clone … && ./install.sh` on the installed system.
- **P3 — Single source of truth for the desktop.** `common/` holds the only
  copy of every config, script, theme, and asset. No distro backend transcribes
  or forks them; NixOS deploys the same files.
- **P4 — Config/state separation (XDG).** Configuration is static and may be
  deployed read-only; everything the desktop writes at runtime is *state* and
  lives under `${XDG_STATE_HOME:-~/.local/state}/i3wm-x11/`. This is what makes
  a fully immutable NixOS deployment possible and is correct engineering on
  every distro.
- **P5 — Minimal abstraction.** Distro-specific behavior is centralized in one
  small sourced library; hardware detection and desktop logic stay
  distro-agnostic and separate. No plugin systems, no speculative hooks.

## 2. Repository layout (target)

```
install.sh              # dispatcher: /etc/os-release → arch|debian|nixos backend
arch/install.sh         # imperative installer (pacman/yay), system-state aware
debian/install.sh       # imperative installer (apt), system-state aware
nixos/
├── flake.nix           # inputs: nixpkgs 26.05, home-manager 26.05 (follows)
│                       # outputs: nixosModules.{desktop,default},
│                       #   homeManagerModules.dotfiles,
│                       #   nixosConfigurations.example, checks, formatter
├── module.nix          # system module (see §6)
├── home.nix            # Home Manager module (see §6)
├── example/configuration.nix
└── install.sh          # integration wizard (see §6.4) — writes nothing
                        #   outside CWD
common/
├── lib/
│   ├── installer-common.sh   # (existing) shared imperative-installer logic
│   ├── distro.sh             # NEW: distro-facts runtime library (§3)
│   └── paths.sh              # NEW: XDG state-path contract (§4)
├── configs/ scripts/ themes/ .zshrc   # unchanged roles
docs/DESIGN.md          # this document
```

## 3. Distro abstraction — `common/lib/distro.sh`

A single, flat, dependency-free bash library, sourced by runtime scripts that
need distro *facts*. Contract (frozen):

- Detection: resolves `DISTRO_ID`, `DISTRO_LIKE` from `/etc/os-release`, then
  `DISTRO_FAMILY ∈ {arch, debian, nixos, unknown}` (ID first, ID_LIKE
  fallback). Pure read; no side effects; O(1); safe to source from zshrc.
- Facts/functions:
  - `distro_glyph` → U+F303 arch / U+F306 debian / U+F31B ubuntu /
    U+F313 nixos / U+F17C fallback (bytes emitted via printf escapes).
  - `distro_fastfetch_logo` → `arch_small|debian_small|ubuntu_small|nixos_small|""`.
  - `distro_update_count` → pacman/checkupdates+yay | apt-get -s | nixos: "0"
    (no cheap offline query exists; displayed quietly).
  - `distro_update_cmd` → `yay -Syu` | `sudo apt update && sudo apt
    full-upgrade` | NixOS ladder: `$NH_FLAKE`/`$FLAKE` set → `nix flake update
    && nixos-rebuild switch --flake` at that path; else `/etc/nixos/flake.nix`
    exists → same with `/etc/nixos`; else channel fallback
    `sudo nixos-rebuild switch --upgrade`.
- Consumers (migrated): `distro_icon.sh`, `updates.sh`, `setup_fastfetch.sh`,
  `.zshrc` (alias tier + zsh-plugin path list incl.
  `/run/current-system/sw/share/zsh-*`).
- Explicit NON-consumers (stay distro-agnostic by design): `launch.sh`
  (hardware), `picom_launch.sh` (GPU/virt), battery/caffeine/weather/lock/rofi
  scripts, `first_setup.sh` (desktop-file probing is already
  provenance-independent).
- Non-goals: no package-name mapping in the runtime layer (installer concern),
  no per-distro script directories, no eval-based dispatch. Adding distro #4 =
  extend the case arms here + add `<distro>/install.sh` + one dispatcher case.

Why one library and not per-concern plugins: three consumers, four facts —
a plugin system is over-engineering; a case statement is inspectable and
greppable. Why split `paths.sh` from `distro.sh`: state paths are not distro
facts; separating them keeps each file single-purpose (~40–100 lines each).

## 4. Config/state separation — `common/lib/paths.sh`

Contract: `I3WM_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/i3wm-x11"`,
created on demand by whoever writes first. Migration map (frozen):

| Runtime artifact (today) | New location |
|---|---|
| `~/.config/i3/themes/current` symlink | `$I3WM_STATE_DIR/themes/current` |
| pywal theme `~/.config/i3/themes/pywal-custom/` | `$I3WM_STATE_DIR/themes/pywal-custom/` |
| wallpapers copied into theme dir | theme dirs under `$I3WM_STATE_DIR/themes/` |
| `~/.config/i3/scripts/.weather_city` | `$I3WM_STATE_DIR/weather_city` |
| `~/.config/i3/.setup_done` | `$I3WM_STATE_DIR/setup_done` |
| `~/.config/i3/scripts/lock_colors.rc` | `$I3WM_STATE_DIR/lock_colors.rc` |
| dunst theme block (sed into dunstrc) | drop-in `~/.config/dunst/dunstrc.d/50-theme.conf` (dir left unmanaged; dunst ≥1.5 on all three distros) |
| starship palette sed | **removed** — both theme branches write `palette = "default"`; the sed is a functional no-op today. starship.toml becomes fully static |
| fastfetch generated presets | `$I3WM_STATE_DIR/fastfetch/presets/` (zshrc points here) |

Static configs referencing these paths (i3 `include`, polybar `include-file`,
5 rofi `@import`, ~8 scripts) are updated once. The pro-dark *source* theme
stays in `common/themes/`; the installer/first-run seeds
`$I3WM_STATE_DIR/themes/pro-dark` from it (copy on Arch/Debian/NixOS alike —
seeding state is not config mutation).

Result: **every file under `~/.config` is immutable** on NixOS (pure HM
symlinks); on Arch/Debian nothing user-visible changes. All scripts also move
to `#!/usr/bin/env bash` (mandatory on NixOS, no-op elsewhere).

## 5. Universal installer behavior (P1/P2 applied to Arch & Debian)

The imperative installers already probe package state; freeze adds
system-state awareness where provenance differs:

- **Arch — network service guard (new):** `archinstall` systems may already run
  systemd-networkd/iwd/dhcpcd. The installer enables NetworkManager **only if
  no other network-management service is enabled**; otherwise it warns with
  instructions (rofi_network requires nmcli) and skips. Bluetooth enable stays
  unconditional (no conflict class).
- **Debian — clearer sudo preflight (new message only):** text-installer runs
  where a root password was set leave the user outside the `sudo` group; the
  existing `sudo -v` failure now explains the fix
  (`usermod -aG sudo <user>` as root) instead of a bare error.
- **Existing display managers (all distros):** installers never install or
  remove a DM. If one exists (Debian DVD/GNOME, archinstall profile, Calamares
  GNOME), i3 appears as an additional session via `/usr/share/xsessions` /
  the NixOS session module — documented, no code needed.

## 6. NixOS implementation

### 6.1 Architecture (decision C — hybrid flake, re-affirmed)
`common/` files deployed verbatim via Home Manager; provisioning fully
declarative. Rejected alternatives, recorded: (A) full translation to HM
options (+ Stylix) — two sources of truth, kills the pywal UX;
(B) imperative port — anti-pattern; (D) mkOutOfStoreSymlink/tmpfiles
working-copy links — requires pinned impure clone path, breaks
`github:…?dir=nixos` consumption (documented as a power-user variant only).
With §4 in place, **all** HM file deployments are read-only store symlinks —
no activation-copy machinery exists at all.

### 6.2 System module (`nixos/module.nix`)
X11 + `services.xserver.windowManager.i3`; `services.displayManager.startx`
default with `enableDisplayManager` (lightdm) toggle — wizard recommends based
on detected DM; PipeWire (`services.pipewire` + rtkit + pulse + alsa);
NetworkManager; bluetooth + blueman; `fonts.packages` (nerd-fonts.jetbrains-mono,
nerd-fonts.symbols-only, noto-cjk/emoji, font-awesome, ibm-plex,
material-design-icons, fira-code, cascadia); backlight udev rule +
`extraGroups`; zsh login shell; **`programs.i3lock = { enable = true; package =
pkgs.i3lock-color; }`** (PAM — a home.packages locker cannot authenticate).
Options: `username`, `enableDisplayManager`, `withVSCode`, `withBrave`
(unfree default **off**; scoped `allowUnfreePredicate` when enabled).

### 6.3 Home Manager module (`nixos/home.nix`)
`home.packages` incl. **`polybarFull`** (default `polybar` lacks
pulse/i3 flags — same failure class as v1.0.x BUG-1), i3lock-color *not* here
(PAM, §6.2), pywal, autotiling, papirus-folders, rofi, dunst, kitty, picom,
feh, playerctl, flameshot, zenity, mesa-demos, CLI set; read-only
`xdg.configFile` links for every `common/` config + scripts; polkit-gnome as a
**systemd user service** (store paths can't be probed by the i3 exec loop; the
loop finds nothing and exits silently — zero `common/` changes); `gtk` module
sets Arc-Dark/Papirus declaratively (the config's `gsettings` execs become
consistent no-ops); state seeding of pro-dark via one first-run check in
`theme_switcher.sh` (shared, not NixOS-specific).

### 6.4 Integration wizard (`nixos/install.sh`)
Never writes outside CWD. Ladder (P1): confirm NixOS + version → flakes
enabled? → existing DM? → `/etc/nixos` shape (flake vs channels) → HM present?
Then interactive Q&A (username, DM, unfree) → **generates** an example host
flake/config into `./nixos-example/` + prints exact commands
(`nixos-rebuild switch --flake`). Wizard's own read-only nix commands pass
`--extra-experimental-features 'nix-command flakes'` per invocation (no system
mutation); permanence comes declaratively from the generated config's
`nix.settings.experimental-features`. `--dry-run` prints without writing.

## 7. Validation architecture

- Fresh-VM E2E on all three distros from the **public repo only** (existing
  QEMU/KVM harness; QMP keystrokes + screendump + ssh).
- **Provenance matrix (P2):** full graphical suite on one canonical image per
  distro (Arch ISO scripted, Debian netinst preseed, NixOS **graphical ISO** —
  the one on hand); provenance *variants* (archinstall, Debian DVD, NixOS
  minimal) validated to the convergence point (clone + installer/wizard
  completes + session starts), since downstream is identical by construction.
- **ISO handling (P1):** live-environment bootstrap uses filename as an
  optional routing hint, verified by console screendump probe (`login:` vs
  shell; VT-switch via ctrl-alt-f2 unifies graphical/minimal). Post-install,
  the harness knows nothing about the ISO.
- NixOS-specific gates: `nix flake check`; rebuild idempotency (second
  `switch` = zero rebuild actions); PAM unlock test; pywal theme switch
  survives a rebuild (state, §4); parity screenshots vs Arch/Debian.
- Regression: Arch+Debian E2E re-run (state-dir refactor touches them).

## 8. Decision log (what changed at freeze, and why)

1. Copy-on-activation → **XDG state separation** (§4): removes the impure
   mechanism entirely; challenged-and-replaced in adversarial review.
2. Guided /etc/nixos editing → **wizard, zero system writes** (§6.4): merge
   logic against arbitrary user configs is unmaintainable and trust-destroying.
3. Flakes: silent enable → **per-invocation flags + declarative permanence**.
4. Updates on NixOS: `--upgrade` → **flake-aware ladder** (§3): `--upgrade` is
   channel-only and misleading on flake systems.
5. Per-script distro branches → **`common/lib/distro.sh`** (§3): third distro
   turns duplication into proven drift risk.
6. NEW at freeze — Arch NetworkManager **conflict guard** (§5): direct
   consequence of P2 (archinstall provenance).
7. NEW at freeze — Debian sudo-group **preflight message** (§5): P2 (text
   installer with root password).
8. ISO-derived behavior demoted to **hint-only inside the harness** (P1);
   user-facing recommendation: graphical ISO + "No desktop" for newcomers,
   minimal for experts; existing NixOS users unaffected.

## 9. Frozen defaults & explicit non-goals

Defaults: startx (DM opt-in) · unfree off (wizard prompt) · Stylix documented
as the pure alternative, not used · version target **v1.1.0** · state-dir
refactor is internal (no user-facing breaking change).
Non-goals: no nix profile installs; no source builds on NixOS; no /etc or
nix.conf mutation by scripts; no mkOutOfStoreSymlink default; no PAM/setuid
workarounds; no Stylix default; no per-distro forks of `common/`.
