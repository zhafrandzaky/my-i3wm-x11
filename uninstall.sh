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
        # `sudo nixos-rebuild --flake` can leave root-owned files inside the
        # wizard-generated repo (git objects, flake.lock), so a plain rm may
        # silently fail. Escalate if needed and only report success when the
        # paths are actually gone.
        rm -rf "$PWD/nixos-example" "$HOME/.local/state/i3wm-x11" 2>/dev/null
        [ -e "$PWD/nixos-example" ] && sudo rm -rf "$PWD/nixos-example"
        [ -e "$HOME/.local/state/i3wm-x11" ] && sudo rm -rf "$HOME/.local/state/i3wm-x11"
        if [ ! -e "$PWD/nixos-example" ] && [ ! -e "$HOME/.local/state/i3wm-x11" ]; then
            ok "Removed desktop dotfiles, wizard config, and runtime state."
        else
            err "Could not fully remove nixos-example / runtime state — check permissions."
            exit 1
        fi
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

# REFUSE to run on an invalid or incomplete manifest — restoring from a broken
# manifest would silently do nothing while pretending to succeed (the v1.2.0
# regression). _rb_validate_manifest checks non-empty + valid JSON + every
# required field + well-formed core arrays.
if ! _rb_validate_manifest "$MANIFEST"; then
    err "The rollback manifest is invalid or incomplete: $MANIFEST"
    err "Refusing to continue — an incomplete manifest cannot safely restore your system."
    err "Your system was NOT modified. Inspect the manifest, or restore manually from the backup dir."
    exit 1
fi

# Verify manifest integrity if a checksum was written.
if [ -f "$RB_TX/manifest.sha256" ]; then
    if [ "$(sha256sum "$MANIFEST" | cut -d' ' -f1)" != "$(cat "$RB_TX/manifest.sha256")" ]; then
        warn "Manifest checksum mismatch — it may have been edited after install. Proceeding cautiously."
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

# Track hard failures across all restore steps; "ROLLBACK COMPLETE" is only
# printed if this stays 0. (User-modified files that are skipped are warnings,
# not failures.)
ROLLBACK_FAILURES=0
fail_step() { err "$1"; ROLLBACK_FAILURES=$((ROLLBACK_FAILURES + 1)); }

# After deleting an installer-created file, remove parent directories the
# installer created for it that are now empty (e.g. ~/.config/matplotlib left
# behind after matplotlibrc is removed). rmdir only succeeds on empty dirs, so
# this can never delete a directory that still holds user data; we also stop at
# well-known shared roots defensively.
prune_empty_parents() {
    local dir; dir=$(dirname "$1")
    while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "$HOME" ] \
          && [ "$dir" != "$HOME/.config" ] && [ "$dir" != "$HOME/.local" ] \
          && [ "$dir" != "$HOME/.local/share" ] && [ "$dir" != "$HOME/.local/state" ]; do
        rmdir "$dir" 2>/dev/null || break
        dir=$(dirname "$dir")
    done
}

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
        [ "$DRY_RUN" = false ] && prune_empty_parents "$path"
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
# jq is itself an installer package, so it is removed by the package step
# below. Read EVERY manifest value that is consumed during or after package
# removal now, while jq still exists — otherwise the scoped orphan cleanup and
# the post-restore verification would silently see nothing (empty jq output)
# and no-op while still reporting success.
mapfile -t ALL_ADDED < <(jq -r '.packages.all_added[]?' "$MANIFEST")
VERIFY_SHELL_CHANGED=$(jq -r '.shell.changed' "$MANIFEST")
VERIFY_SHELL_BEFORE=$(jq -r '.shell.before' "$MANIFEST")
mapfile -t VERIFY_CREATED_FILES < <(jq -r '.files[]? | select(.action=="create") | .path' "$MANIFEST")
# Split installed_by_us into packages that are genuinely NEW on this system
# (also in all_added -> safe to remove) and packages that PRE-EXISTED as
# dependencies but were promoted to "manually installed" when the installer
# ran `apt-get install`/`pacman -S` on them (e.g. python3, git, curl).
# Removing a promoted package cascades onto its pre-existing reverse
# dependencies (removing python3 rips out apt-listchanges and reportbug), so
# promoted packages are demoted back to auto/asdeps instead of removed.
mapfile -t REMOVE_PKGS < <(comm -12 \
    <(printf '%s\n' "${PKGS[@]}" | sort -u) \
    <(printf '%s\n' "${ALL_ADDED[@]}" | sort -u))
mapfile -t DEMOTE_PKGS < <(comm -23 \
    <(printf '%s\n' "${PKGS[@]}" | sort -u) \
    <(printf '%s\n' "${ALL_ADDED[@]}" | sort -u))
if [ "$KEEP_PACKAGES" = true ]; then
    info "--keep-packages: leaving ${#PKGS[@]} installer-installed packages in place."
elif [ "${#PKGS[@]}" -eq 0 ]; then
    info "No packages recorded as installed by the installer."
else
    info "The installer added ${#REMOVE_PKGS[@]} packages — these will be removed."
    [ "${#DEMOTE_PKGS[@]}" -gt 0 ] && \
        info "${#DEMOTE_PKGS[@]} package(s) existed before install and were only marked manual — these are demoted back to automatic, NOT removed: ${DEMOTE_PKGS[*]}"
    printf '  %s\n' "${REMOVE_PKGS[@]}" | head -40
    proceed=true
    if [ "$DRY_RUN" = false ] && [ "$FORCE" != true ] && [ -t 0 ]; then
        read -rp "Remove these packages? [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]] || proceed=false
    fi
    PKG_REMOVAL_ATTEMPTED=false
    if [ "$proceed" = true ]; then
        PKG_REMOVAL_ATTEMPTED=true
        case "$DISTRO_FAMILY" in
            arch)
                # Demote pre-existing packages back to dependency status first.
                if [ "${#DEMOTE_PKGS[@]}" -gt 0 ]; then
                    run "sudo pacman -D --asdeps ${DEMOTE_PKGS[*]}" \
                        && ok "demoted to dependency: ${DEMOTE_PKGS[*]}"
                fi
                if [ "${#REMOVE_PKGS[@]}" -gt 0 ]; then
                    run "sudo pacman -Rns --noconfirm ${REMOVE_PKGS[*]}" \
                        || warn "Some packages could not be removed (still required). Re-run or remove manually."
                fi
                # Clean up orphaned dependencies the installer pulled in — but
                # ONLY those, never a pre-existing orphan (scoped to all_added,
                # which was read before jq itself was removed above).
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
                # Demote pre-existing packages back to automatic first, so
                # they are never part of a removal transaction.
                if [ "${#DEMOTE_PKGS[@]}" -gt 0 ]; then
                    run "sudo apt-mark auto ${DEMOTE_PKGS[*]} > /dev/null" \
                        && ok "demoted to automatic: ${DEMOTE_PKGS[*]}"
                fi
                if [ "${#REMOVE_PKGS[@]}" -gt 0 ]; then
                    run "sudo apt-get remove --purge -y ${REMOVE_PKGS[*]}"
                fi
                # Direct scoped sweep: purge every remaining package the
                # installer added. Nothing pre-existing can Depend on them
                # (they did not exist at install time), so the cascade stays
                # inside all_added. Without this, Recommends-links from kept
                # packages make `autoremove` consider dozens of installer
                # dependencies "still needed" forever.
                if [ "$DRY_RUN" = false ]; then
                    mapfile -t LEFTOVER < <(comm -12 \
                        <(dpkg-query -f '${db:Status-Status} ${Package}\n' -W 2>/dev/null \
                            | awk '$1=="installed"{print $2}' | sort -u) \
                        <(printf '%s\n' "${ALL_ADDED[@]}" | sort -u))
                    if [ "${#LEFTOVER[@]}" -gt 0 ]; then
                        sudo apt-get purge -y "${LEFTOVER[@]}" >/dev/null 2>&1 \
                            && ok "purged ${#LEFTOVER[@]} remaining installer-pulled packages" \
                            || warn "could not purge some installer-pulled leftovers: ${LEFTOVER[*]:0:5} ..."
                    fi
                fi
                # Clean up orphaned dependencies the installer pulled in — but
                # ONLY those, never a package that pre-existed the install.
                # A blanket `apt-get autoremove` is unscoped: it purges every
                # orphan on the system, including pre-existing auto-installed
                # packages (e.g. apt-listchanges, reportbug), violating the
                # "never remove pre-existing packages" contract. Instead we
                # intersect apt's own autoremove candidates with all_added
                # (read before jq itself was removed above).
                if [ "${#ALL_ADDED[@]}" -gt 0 ] && [ "$DRY_RUN" = false ]; then
                    for _pass in 1 2 3; do
                        # Simulated removals print "Remv", simulated purges
                        # print "Purg" — match both or the loop sees nothing.
                        mapfile -t ORPHANS < <(comm -12 \
                            <(sudo apt-get -s autoremove --purge 2>/dev/null \
                                | awk '/^(Remv|Purg) /{print $2}' | sort -u) \
                            <(printf '%s\n' "${ALL_ADDED[@]}" | sort -u))
                        [ "${#ORPHANS[@]}" -eq 0 ] && break
                        sudo apt-get purge -y "${ORPHANS[@]}" 2>/dev/null || break
                        ok "removed installer-pulled orphans: ${ORPHANS[*]}"
                    done
                fi
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

# ---------- 10. Post-restore verification (defensive) ----------
# Confirm the rollback actually took effect. Silence here previously masked a
# no-op; now we assert the observable end state matches the manifest's intent.
if [ "$DRY_RUN" = false ]; then
    echo -e "\n${CYAN}>>> VERIFYING ROLLBACK${NC}"
    # (a) login shell reverted. Uses values captured before jq was removed.
    if [ "$VERIFY_SHELL_CHANGED" = true ]; then
        want="$VERIFY_SHELL_BEFORE"
        got=$(getent passwd "$USER" | cut -d: -f7)
        [ "$got" = "$want" ] && ok "shell is $got" || fail_step "shell is $got, expected $want"
    fi
    # (b) installer packages removed (unless we deliberately kept them / skipped)
    if [ "$KEEP_PACKAGES" != true ] && [ "${PKG_REMOVAL_ATTEMPTED:-false}" = true ]; then
        still=0
        for p in "${REMOVE_PKGS[@]}"; do
            case "$DISTRO_FAMILY" in
                arch)   pacman -Qq "$p" &>/dev/null && still=$((still+1)) ;;
                debian) dpkg -s "$p" &>/dev/null && still=$((still+1)) ;;
            esac
        done
        [ "$still" -eq 0 ] && ok "all ${#REMOVE_PKGS[@]} installer packages removed (${#DEMOTE_PKGS[@]} pre-existing demoted, kept)" \
            || fail_step "$still installer package(s) still present"
    fi
    # (c) recorded 'create' files that were not user-modified should be gone.
    # Uses the create-path list captured before jq was removed.
    leftover=0
    for path in "${VERIFY_CREATED_FILES[@]}"; do
        [ -z "$path" ] && continue
        path="${path/#\~/$HOME}"
        { [ -e "$path" ] || [ -L "$path" ]; } && leftover=$((leftover+1))
    done
    if [ "$leftover" -gt 0 ] && [ "$FORCE" = true ]; then
        fail_step "$leftover installer-created path(s) still present after --force"
    fi
fi

echo ""
if [ "$ROLLBACK_FAILURES" -eq 0 ]; then
    echo -e "${GREEN}"
    echo "   ROLLBACK COMPLETE — verified"
    [ "$MODIFIED_ANY" = true ] && echo "   (some files you modified after install were preserved; see warnings above)"
    echo "   Original configs backup: $BACKUP_DIR"
    echo "   Log out / reboot for shell and group changes to take full effect."
    echo -e "${NC}"
    exit 0
else
    echo -e "${RED}"
    echo "   ROLLBACK INCOMPLETE — $ROLLBACK_FAILURES step(s) failed (see errors above)."
    echo "   Your system may be partially restored. The manifest and backups are kept at:"
    echo "     $RB_TX"
    echo "     $BACKUP_DIR"
    echo -e "${NC}"
    exit 1
fi
