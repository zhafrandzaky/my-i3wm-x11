#!/usr/bin/env bash
#
# Transactional rollback for my-i3wm-x11 (docs/DESIGN.md §10).
#
# Reverses exactly what a recorded installation did — restoring overwritten
# files, replaced symlinks, the login shell, GTK/gsettings, enabled services,
# added groups, and installer-installed packages — and nothing else.
#
# Usage:
#   ./uninstall.sh              # roll back the most recent installation
#   ./uninstall.sh --id <ID>    # roll back a specific transaction
#   ./uninstall.sh --list       # list recorded transactions
#   ./uninstall.sh --dry-run    # show what would be done, change nothing
#   ./uninstall.sh --force      # do not stop on user-modified files (still warns)
#   ./uninstall.sh --keep-packages   # restore everything except removing packages

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/common/lib/rollback.sh"
# shellcheck source=/dev/null
source "$REPO_DIR/common/lib/distro.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

DRY_RUN=false
FORCE=false
KEEP_PACKAGES=false
TARGET_ID=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --force) FORCE=true ;;
        --keep-packages) KEEP_PACKAGES=true ;;
        --id) NEXT_IS_ID=true ;;
        --list) LIST_ONLY=true ;;
        *) if [ "${NEXT_IS_ID:-}" = true ]; then TARGET_ID="$arg"; NEXT_IS_ID=false; fi ;;
    esac
done

run() { if [ "$DRY_RUN" = true ]; then echo -e "  ${CYAN}[dry-run]${NC} $*"; else eval "$*"; fi; }

# ---------- NixOS: declarative rollback via generations ----------
if [ "$DISTRO_FAMILY" = "nixos" ]; then
    echo -e "${CYAN}"
    echo " NIXOS ROLLBACK"
    echo -e "${NC}"
    info "NixOS is declarative — the desktop was applied as a system generation."
    echo ""
    echo "  Rolling back activates the previous generation (this works for both"
    echo "  flake- and channel-based systems, unlike 'nixos-rebuild --rollback'"
    echo "  which fails on flake systems):"
    echo "      sudo nix-env --rollback -p /nix/var/nix/profiles/system"
    echo "      sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch"
    echo "  (or reboot and pick the previous generation in the boot menu.)"
    echo ""
    echo "  Then remove the wizard-generated config and runtime state:"
    echo "      rm -rf $PWD/nixos-example ~/.local/state/i3wm-x11"
    echo ""
    proceed=false
    if [ "$FORCE" = true ]; then proceed=true
    elif [ "$DRY_RUN" = false ] && [ -t 0 ]; then
        read -rp "Roll back to the previous generation now? [y/N]: " a
        [[ "$a" =~ ^[Yy]$ ]] && proceed=true
    fi
    if [ "$proceed" = true ]; then
        sudo nix-env --rollback -p /nix/var/nix/profiles/system \
            && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch \
            && ok "Rolled back to the previous generation (desktop reverted)."
        # Rolling back to a generation without Home Manager leaves the desktop's
        # dotfile store-symlinks in ~/.config (live until GC). On NixOS these
        # paths are created only by our desktop HM (the base system creates
        # none), so a store-symlink here is unambiguously ours — remove it.
        # Handles both file-symlinks (~/.zshrc, starship.toml) and directories
        # of symlinks (~/.config/i3, polybar, ...).
        _is_store_symlink() { [ -L "$1" ] && readlink "$1" | grep -q '^/nix/store'; }
        for f in "$HOME/.zshrc" "$HOME/.config"/{i3,polybar,rofi,kitty,picom,dunst,fastfetch,starship.toml}; do
            [ -e "$f" ] || [ -L "$f" ] || continue
            if _is_store_symlink "$f"; then
                rm -f "$f"
            elif [ -d "$f" ] && find "$f" -maxdepth 2 -type l -lname '/nix/store/*' -print -quit 2>/dev/null | grep -q .; then
                rm -rf "$f"   # directory populated with HM store symlinks
            fi
        done
        rm -rf "$PWD/nixos-example" "$HOME/.local/state/i3wm-x11"
        ok "Removed desktop dotfiles, wizard config, and runtime state."
    elif [ "$DRY_RUN" = true ]; then
        info "[dry-run] Would run the two rollback commands above and remove nixos-example + runtime state."
    fi
    exit 0
fi

# ---------- List mode ----------
if [ "${LIST_ONLY:-}" = true ]; then
    info "Recorded transactions in $ROLLBACK_ROOT:"
    for d in "$ROLLBACK_ROOT"/*/; do
        [ -e "$d/manifest.json" ] || continue
        id=$(jq -r .install_id "$d/manifest.json" 2>/dev/null)
        ts=$(jq -r .timestamp "$d/manifest.json" 2>/dev/null)
        distro=$(jq -r .distro "$d/manifest.json" 2>/dev/null)
        echo "  $id  ($distro, $ts)"
    done
    exit 0
fi

# ---------- Resolve manifest ----------
command -v jq >/dev/null 2>&1 || { err "jq is required to read the rollback manifest."; exit 1; }
RB_TX="$(rb_resolve_manifest "$TARGET_ID")"
if [ -z "$RB_TX" ] || [ ! -e "$RB_TX/manifest.json" ]; then
    err "No rollback manifest found. Nothing to undo (was this installed with a version that records transactions?)."
    exit 1
fi
MANIFEST="$RB_TX/manifest.json"

# Verify manifest integrity if a checksum was written.
if [ -f "$RB_TX/manifest.sha256" ]; then
    if [ "$(sha256sum "$MANIFEST" | cut -d' ' -f1)" != "$(cat "$RB_TX/manifest.sha256")" ]; then
        warn "Manifest checksum mismatch — it may have been edited. Proceeding cautiously."
    fi
fi

INSTALL_ID=$(jq -r .install_id "$MANIFEST")
BACKUP_DIR=$(jq -r .backup_dir "$MANIFEST")
echo -e "${CYAN}"
echo " ROLLBACK TRANSACTION"
echo " ╭──────────────────────────────────╮"
printf " │  ID     : %-24s│\n" "$INSTALL_ID"
printf " │  Distro : %-24s│\n" "$(jq -r .distro "$MANIFEST")"
printf " │  Date   : %-24s│\n" "$(jq -r .timestamp "$MANIFEST")"
echo " ╰──────────────────────────────────╯"
echo -e "${NC}"
[ "$DRY_RUN" = true ] && warn "DRY RUN — no changes will be made."

# ---------- 1/2. Files: detect post-install modification, then restore ----------
echo -e "\n${CYAN}>>> RESTORING FILES${NC}"
MODIFIED_ANY=false
while IFS=$'\t' read -r action path backup existed is_link recorded_sum; do
    [ -z "$path" ] && continue
    path="${path/#\~/$HOME}"
    # Detect user modification after install.
    if [ -e "$path" ] || [ -L "$path" ]; then
        cur_sum=$(_rb_checksum "$path")
        if [ "$cur_sum" != "$recorded_sum" ]; then
            warn "Modified after install: $path"
            MODIFIED_ANY=true
            if [ "$FORCE" != true ]; then
                echo "        -> skipping (use --force to restore anyway; your changes are kept)"
                continue
            fi
        fi
    fi
    if [ "$action" = "replace" ]; then
        # Restore the pre-install backup over the deployed version.
        if [ -e "$backup" ]; then
            run "rm -rf '$path'"
            run "cp -r '$backup' '$path'"
            ok "restored original: $path"
        else
            warn "backup missing for $path ($backup); removing deployed copy"
            run "rm -rf '$path'"
        fi
    else
        # "create" — the installer made it; remove it.
        run "rm -rf '$path'"
        ok "removed: $path"
    fi
done < <(jq -r '.files[] | [.action,.path,.backup,(.existed_before|tostring),(.is_symlink|tostring),.checksum_after] | @tsv' "$MANIFEST")

# ---------- Created system/user paths (Debian source builds, vendor repos, fonts) ----------
while IFS=$'\t' read -r cpath owner; do
    [ -z "$cpath" ] && continue
    cpath="${cpath/#\~/$HOME}"
    [ -e "$cpath" ] || [ -L "$cpath" ] || continue
    if [ "$owner" = "root" ]; then
        run "sudo rm -rf '$cpath'"
    else
        run "rm -rf '$cpath'"
    fi
    ok "removed created path: $cpath"
done < <(jq -r '.created_paths[]? | [.path,.owner] | @tsv' "$MANIFEST")

# ---------- 3. Services: disable only what we enabled ----------
echo -e "\n${CYAN}>>> RESTORING SERVICES${NC}"
while IFS=$'\t' read -r svc was; do
    [ -z "$svc" ] && continue
    run "sudo systemctl disable '$svc'"
    ok "disabled: $svc (was '$was' before install)"
done < <(jq -r '.services.enabled_by_us[]? | [.service,.was] | @tsv' "$MANIFEST")
[ "$(jq -r '.services.enabled_by_us | length' "$MANIFEST")" = 0 ] && info "No services were enabled by the installer."

# ---------- 4. Login shell ----------
echo -e "\n${CYAN}>>> RESTORING LOGIN SHELL${NC}"
if [ "$(jq -r .shell.changed "$MANIFEST")" = true ]; then
    before=$(jq -r .shell.before "$MANIFEST")
    run "sudo chsh -s '$before' '$USER'"
    ok "login shell restored to $before"
else
    info "Login shell was not changed by the installer."
fi

# ---------- 5. Groups: remove only groups we added ----------
echo -e "\n${CYAN}>>> RESTORING GROUPS${NC}"
mapfile -t ADDED_GROUPS < <(jq -r '.groups.added[]?' "$MANIFEST")
if [ "${#ADDED_GROUPS[@]}" -gt 0 ]; then
    for g in "${ADDED_GROUPS[@]}"; do
        run "sudo gpasswd -d '$USER' '$g'"
        ok "removed from group: $g"
    done
else
    info "No groups were added by the installer."
fi

# ---------- 6. gsettings ----------
echo -e "\n${CYAN}>>> RESTORING GSETTINGS${NC}"
if command -v gsettings >/dev/null 2>&1 && [ "$(jq -r '.gsettings | length' "$MANIFEST")" != 0 ]; then
    while IFS=$'\t' read -r key before; do
        [ -z "$key" ] && continue
        run "gsettings set org.gnome.desktop.interface '$key' \"$before\""
        ok "gsettings $key -> $before"
    done < <(jq -r '.gsettings[]? | [.key,.before] | @tsv' "$MANIFEST")
else
    info "No gsettings baseline recorded."
fi

# ---------- 7. udev rule ----------
while IFS=$'\t' read -r upath existed; do
    [ -z "$upath" ] && continue
    if [ "$existed" = "false" ]; then
        run "sudo rm -f '$upath'"
        run "sudo udevadm control --reload-rules"
        ok "removed udev rule: $upath"
    else
        warn "udev rule $upath existed before install — left untouched."
    fi
done < <(jq -r '.udev[]? | [.path,(.existed_before|tostring)] | @tsv' "$MANIFEST")

# ---------- 8. Packages: remove only what the installer installed ----------
echo -e "\n${CYAN}>>> RESTORING PACKAGES${NC}"
mapfile -t PKGS < <(jq -r '.packages.installed_by_us[]?' "$MANIFEST")
if [ "$KEEP_PACKAGES" = true ]; then
    info "--keep-packages: leaving ${#PKGS[@]} installer-installed packages in place."
elif [ "${#PKGS[@]}" -eq 0 ]; then
    info "No packages recorded as installed by the installer."
else
    info "The installer added ${#PKGS[@]} packages. These will be removed (dependencies that are still needed are kept):"
    printf '  %s\n' "${PKGS[@]}" | head -40
    proceed=true
    if [ "$DRY_RUN" = false ] && [ "$FORCE" != true ] && [ -t 0 ]; then
        read -rp "Remove these packages? [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]] || proceed=false
    fi
    if [ "$proceed" = true ]; then
        case "$DISTRO_FAMILY" in
            arch)
                run "sudo pacman -Rns --noconfirm ${PKGS[*]}" \
                    || warn "Some packages could not be removed (still required). Re-run or remove manually."
                # Clean up orphaned dependencies the installer pulled in — but
                # ONLY those, never a pre-existing orphan (scoped to all_added).
                mapfile -t ALL_ADDED < <(jq -r '.packages.all_added[]?' "$MANIFEST")
                if [ "${#ALL_ADDED[@]}" -gt 0 ] && [ "$DRY_RUN" = false ]; then
                    for _pass in 1 2 3; do
                        mapfile -t ORPHANS < <(comm -12 \
                            <(pacman -Qdtq 2>/dev/null | sort) \
                            <(printf '%s\n' "${ALL_ADDED[@]}" | sort))
                        [ "${#ORPHANS[@]}" -eq 0 ] && break
                        sudo pacman -Rns --noconfirm "${ORPHANS[@]}" 2>/dev/null || break
                        ok "removed installer-pulled orphans: ${ORPHANS[*]}"
                    done
                fi
                ;;
            debian)
                run "sudo apt-get remove --purge -y ${PKGS[*]}"
                run "sudo apt-get autoremove --purge -y"
                ;;
            *) warn "Unknown distro; skipping package removal." ;;
        esac
    else
        info "Skipped package removal."
    fi
fi

# ---------- 9. Runtime state ----------
echo -e "\n${CYAN}>>> RESTORING RUNTIME STATE${NC}"
# Preserve the rollback record itself; remove the desktop's runtime state.
if [ "$DRY_RUN" = false ]; then
    find "$HOME/.local/state/i3wm-x11" -mindepth 1 -maxdepth 1 ! -name rollback -exec rm -rf {} + 2>/dev/null
fi
ok "runtime theme/state cleared (rollback records kept in ~/.local/state/i3wm-x11/rollback)"

echo -e "\n${GREEN}"
echo "   ROLLBACK COMPLETE"
[ "$MODIFIED_ANY" = true ] && echo "   (some files were modified after install; see warnings above)"
echo "   Original configs backup: $BACKUP_DIR"
echo "   Log out / reboot for shell and group changes to take full effect."
echo -e "${NC}"
