#!/usr/bin/env bash
#
# Transactional rollback engine (docs/DESIGN.md §10).
#
# Two roles:
#   1. RECORD  — sourced by the installers; every mutation is journaled before
#                it happens so it can be undone. Produces a manifest.json.
#   2. RESTORE — sourced by uninstall.sh; reads a manifest and reverses exactly
#                what a given installation did, and nothing else.
#
# Safety invariants:
#   - Packages that existed before the install are never removed.
#   - Files not recorded in the manifest are never touched.
#   - Files modified by the user after install trigger a warning before any
#     overwrite/removal (checksum comparison).
#   - Only services the installer actually flipped are reverted.
#
# Requires: paths.sh (I3WM_STATE_DIR) and, at finalize/restore time, jq.

# Resolve the state dir. paths.sh may live next to this file (repo) or in the
# deployed lib dir; fall back to the literal path if neither is present.
if [ -f "$(dirname "${BASH_SOURCE[0]}")/paths.sh" ]; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
else
    I3WM_STATE_DIR="$HOME/.local/state/i3wm-x11"
fi

ROLLBACK_ROOT="$I3WM_STATE_DIR/rollback"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Recursive, order-independent checksum of a file or directory.
_rb_checksum() {
    local p="$1"
    if [ -L "$p" ]; then
        printf 'symlink:%s' "$(readlink "$p")" | sha256sum | cut -d' ' -f1
    elif [ -d "$p" ]; then
        { find "$p" -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null; } \
            | sha256sum | cut -d' ' -f1
    elif [ -e "$p" ]; then
        sha256sum "$p" | cut -d' ' -f1
    else
        echo "ABSENT"
    fi
}

# Explicitly/manually installed package set, distro-aware, sorted.
_rb_explicit_packages() {
    if command -v pacman >/dev/null 2>&1; then
        pacman -Qqe 2>/dev/null | sort
    elif command -v apt-mark >/dev/null 2>&1; then
        apt-mark showmanual 2>/dev/null | sort
    fi
}

# All installed packages (incl. dependencies), sorted. Used to scope orphan
# cleanup to exactly what the installer pulled in.
_rb_all_packages() {
    if command -v pacman >/dev/null 2>&1; then
        pacman -Qq 2>/dev/null | sort
    elif command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Package}\n' 2>/dev/null | sort
    fi
}

# ---------------------------------------------------------------------------
# RECORD side (used by installers)
# ---------------------------------------------------------------------------

# rollback_begin <distro> <installer_version> <backup_dir>
rollback_begin() {
    [ "${DRY_RUN:-false}" = true ] && return 0

    RB_ID="$(date +%Y%m%d_%H%M%S)_$$"
    RB_DIR="$ROLLBACK_ROOT/$RB_ID"
    RB_JOURNAL="$RB_DIR/journal"
    mkdir -p "$RB_JOURNAL"

    RB_DISTRO="$1"
    RB_VERSION="$2"
    RB_BACKUP_DIR="$3"

    {
        echo "install_id=$RB_ID"
        echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "distro=$RB_DISTRO"
        echo "installer_version=$RB_VERSION"
        echo "backup_dir=$RB_BACKUP_DIR"
        echo "user=$USER"
        echo "login_shell_at_start=$(getent passwd "$USER" | cut -d: -f7)"
    } > "$RB_JOURNAL/meta.txt"

    : > "$RB_JOURNAL/files.tsv"
    : > "$RB_JOURNAL/services.tsv"
    : > "$RB_JOURNAL/groups.txt"
    : > "$RB_JOURNAL/shell.txt"
    : > "$RB_JOURNAL/udev.tsv"
    : > "$RB_JOURNAL/created_paths.tsv"

    # Package baseline — explicit set (removal targets) and full set (orphan scope).
    _rb_explicit_packages > "$RB_JOURNAL/packages_before.txt"
    _rb_all_packages > "$RB_JOURNAL/packages_all_before.txt"

    # gsettings baseline (the i3 session mutates these at runtime; record the
    # pre-install values so uninstall can restore the desktop appearance).
    : > "$RB_JOURNAL/gsettings.tsv"
    if command -v gsettings >/dev/null 2>&1; then
        local key
        for key in gtk-theme icon-theme color-scheme cursor-theme; do
            local val
            val=$(gsettings get org.gnome.desktop.interface "$key" 2>/dev/null) || continue
            printf '%s\t%s\n' "$key" "$val" >> "$RB_JOURNAL/gsettings.tsv"
        done
    fi

    export RB_ID RB_DIR RB_JOURNAL RB_DISTRO RB_VERSION RB_BACKUP_DIR
}

# rollback_record_file <action> <dest> <backup_path|-> <existed_before:true|false>
# The checksum is filled in at finalize (not here), because the installer may
# write more into a deployed directory afterwards (e.g. scripts/themes into
# ~/.config/i3, or theme_switcher's dunstrc.d drop-in) — the rollback baseline
# must be the FINAL post-install state, not the moment of first deploy.
rollback_record_file() {
    [ "${DRY_RUN:-false}" = true ] && return 0
    [ -z "${RB_JOURNAL:-}" ] && return 0
    local action="$1" dest="$2" backup="$3" existed="$4"
    local is_link="false"
    [ -L "$dest" ] && is_link="true"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$action" "$dest" "$backup" "$existed" "$is_link" "PENDING" >> "$RB_JOURNAL/files.tsv"
}

# rollback_enable_service <service>  — enables only if not already enabled,
# and records it so uninstall disables exactly what we flipped.
rollback_enable_service() {
    local svc="$1"
    local was
    was=$(systemctl is-enabled "$svc" 2>/dev/null || echo "unknown")
    if [ "$was" = "enabled" ]; then
        return 0  # already on before us — never touch on rollback
    fi
    if [ "${DRY_RUN:-false}" = true ]; then
        return 0
    fi
    if sudo systemctl enable "$svc" 2>>"${LOG_FILE:-/dev/null}"; then
        [ -n "${RB_JOURNAL:-}" ] && printf '%s\t%s\n' "$svc" "$was" >> "$RB_JOURNAL/services.tsv"
    fi
}

# rollback_record_shell <before> <after>
rollback_record_shell() {
    [ "${DRY_RUN:-false}" = true ] && return 0
    [ -z "${RB_JOURNAL:-}" ] && return 0
    printf '%s\t%s\n' "$1" "$2" > "$RB_JOURNAL/shell.txt"
}

# rollback_record_group <group>  — record a group we newly added the user to.
rollback_record_group() {
    [ "${DRY_RUN:-false}" = true ] && return 0
    [ -z "${RB_JOURNAL:-}" ] && return 0
    echo "$1" >> "$RB_JOURNAL/groups.txt"
}

# rollback_record_udev <path> <existed_before:true|false>
rollback_record_udev() {
    [ "${DRY_RUN:-false}" = true ] && return 0
    [ -z "${RB_JOURNAL:-}" ] && return 0
    printf '%s\t%s\n' "$1" "$2" >> "$RB_JOURNAL/udev.tsv"
}

# rollback_record_created_path <path> <owner:user|root>
# For durable artifacts made outside deploy_config / the package manager
# (e.g. Debian source-built binaries, vendor apt repos, downloaded fonts).
# Only records paths that did not exist before, so rollback never removes a
# pre-existing file.
rollback_record_created_path() {
    [ "${DRY_RUN:-false}" = true ] && return 0
    [ -z "${RB_JOURNAL:-}" ] && return 0
    local path="$1" owner="${2:-user}"
    printf '%s\t%s\n' "$path" "$owner" >> "$RB_JOURNAL/created_paths.tsv"
}

# Required top-level manifest fields (single source of truth for validation).
RB_REQUIRED_FIELDS='["install_id","timestamp","distro","installer_version","backup_dir","metadata","shell","packages","services","groups","udev","gsettings","created_paths","files"]'

# Print a hard rollback error to stderr and the install log (if any).
_rb_fail() {
    echo "[ROLLBACK-ERROR] $1" >&2
    [ -n "${LOG_FILE:-}" ] && echo "[ROLLBACK-ERROR] $(date): $1" >> "$LOG_FILE"
    return 0
}

# _rb_validate_manifest <file>  -> 0 if the file is a complete, valid manifest.
# Checks: exists, non-empty, valid JSON, all required fields present, non-empty
# install_id, and packages/files are the expected shapes.
_rb_validate_manifest() {
    local f="$1"
    [ -f "$f" ] || { _rb_fail "manifest missing: $f"; return 1; }
    [ -s "$f" ] || { _rb_fail "manifest is empty: $f"; return 1; }
    if ! jq -e . "$f" >/dev/null 2>&1; then
        _rb_fail "manifest is not valid JSON: $f"; return 1
    fi
    if ! jq -e --argjson req "$RB_REQUIRED_FIELDS" \
            '. as $o | all($req[]; . as $k | $o | has($k))' "$f" >/dev/null 2>&1; then
        _rb_fail "manifest is missing required fields: $f"; return 1
    fi
    if ! jq -e '(.install_id|type=="string" and length>0)
                and (.packages.installed_by_us|type=="array")
                and (.packages.all_added|type=="array")
                and (.files|type=="array")' "$f" >/dev/null 2>&1; then
        _rb_fail "manifest has malformed core fields: $f"; return 1
    fi
    return 0
}

# rollback_finalize  — diff packages, assemble+validate manifest.json, mark
# 'latest'. Returns non-zero if the manifest could not be built or is invalid,
# so the installer can abort instead of leaving a broken (un-rollbackable) state.
rollback_finalize() {
    [ "${DRY_RUN:-false}" = true ] && return 0
    [ -z "${RB_JOURNAL:-}" ] && return 0

    _rb_explicit_packages > "$RB_JOURNAL/packages_after.txt"
    comm -13 "$RB_JOURNAL/packages_before.txt" "$RB_JOURNAL/packages_after.txt" \
        > "$RB_JOURNAL/packages_installed.txt"
    _rb_all_packages > "$RB_JOURNAL/packages_all_after.txt"
    comm -13 "$RB_JOURNAL/packages_all_before.txt" "$RB_JOURNAL/packages_all_after.txt" \
        > "$RB_JOURNAL/packages_all_installed.txt"

    # Fill in checksums now, reflecting each recorded path's FINAL post-install
    # state (see rollback_record_file). This is the baseline uninstall compares
    # against to detect genuine post-install user modifications.
    if [ -s "$RB_JOURNAL/files.tsv" ]; then
        local tmp="$RB_JOURNAL/files.tsv.tmp"; : > "$tmp"
        local action dest backup existed is_link _sum
        while IFS=$'\t' read -r action dest backup existed is_link _sum; do
            [ -z "$dest" ] && continue
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$action" "$dest" "$backup" "$existed" "$is_link" "$(_rb_checksum "$dest")" >> "$tmp"
        done < "$RB_JOURNAL/files.tsv"
        mv "$tmp" "$RB_JOURNAL/files.tsv"
    fi

    # jq is mandatory for a usable manifest — never silently skip it.
    if ! command -v jq >/dev/null 2>&1; then
        _rb_fail "jq is not installed — cannot build the rollback manifest."
        return 1
    fi

    # Defensive: every --rawfile target must exist (rollback_begin creates them,
    # but guard against a partially-initialized journal).
    local jf
    for jf in files.tsv services.tsv groups.txt shell.txt udev.tsv gsettings.tsv \
              created_paths.tsv packages_installed.txt packages_all_installed.txt; do
        [ -f "$RB_JOURNAL/$jf" ] || : > "$RB_JOURNAL/$jf"
    done

    # Build into a temp file, check jq's exit status, then validate before
    # committing — a failed jq must never leave a truncated manifest in place.
    local out="$RB_DIR/manifest.json.tmp" errf="$RB_DIR/manifest.err"
    if ! _rb_build_manifest_json > "$out" 2> "$errf"; then
        _rb_fail "manifest generation (jq) failed: $(tr '\n' ' ' < "$errf")"
        rm -f "$out"; return 1
    fi
    if ! _rb_validate_manifest "$out"; then
        _rb_fail "generated manifest failed validation; not installing it."
        rm -f "$out"; return 1
    fi
    mv "$out" "$RB_DIR/manifest.json"
    rm -f "$errf"
    sha256sum "$RB_DIR/manifest.json" | cut -d' ' -f1 > "$RB_DIR/manifest.sha256"
    ln -sfn "$RB_DIR" "$ROLLBACK_ROOT/latest"
    return 0
}

# Emits the manifest JSON to stdout. Returns jq's exit status so the caller can
# detect failure. Every $var used in the program MUST have a matching --arg or
# --rawfile binding (the v1.2.0 regression was a missing --rawfile pkgs_all_raw).
_rb_build_manifest_json() {
    local m="$RB_JOURNAL/meta.txt"
    local install_id timestamp distro installer_version backup_dir login_shell_at_start
    install_id=$(grep '^install_id=' "$m" | cut -d= -f2-)
    timestamp=$(grep '^timestamp=' "$m" | cut -d= -f2-)
    distro=$(grep '^distro=' "$m" | cut -d= -f2-)
    installer_version=$(grep '^installer_version=' "$m" | cut -d= -f2-)
    backup_dir=$(grep '^backup_dir=' "$m" | cut -d= -f2-)
    login_shell_at_start=$(grep '^login_shell_at_start=' "$m" | cut -d= -f2-)

    jq -n \
        --arg id "$install_id" \
        --arg ts "$timestamp" \
        --arg distro "$distro" \
        --arg ver "$installer_version" \
        --arg backup "$backup_dir" \
        --arg shell0 "$login_shell_at_start" \
        --rawfile files_raw "$RB_JOURNAL/files.tsv" \
        --rawfile services_raw "$RB_JOURNAL/services.tsv" \
        --rawfile groups_raw "$RB_JOURNAL/groups.txt" \
        --rawfile shell_raw "$RB_JOURNAL/shell.txt" \
        --rawfile udev_raw "$RB_JOURNAL/udev.tsv" \
        --rawfile gsettings_raw "$RB_JOURNAL/gsettings.tsv" \
        --rawfile created_raw "$RB_JOURNAL/created_paths.tsv" \
        --rawfile pkgs_raw "$RB_JOURNAL/packages_installed.txt" \
        --rawfile pkgs_all_raw "$RB_JOURNAL/packages_all_installed.txt" '
        def lines: split("\n") | map(select(length>0));
        def tsv($n): lines | map(split("\t")) | map(select(length>=$n));
        {
          install_id: $id,
          timestamp: $ts,
          distro: $distro,
          installer_version: $ver,
          backup_dir: $backup,
          metadata: { schema: 1, generated_by: "rollback.sh" },
          shell: ( ($shell_raw | tsv(2)) | if length>0 then {changed:true, before:.[0][0], after:.[0][1]} else {changed:false, before:$shell0} end ),
          packages: { installed_by_us: ($pkgs_raw | lines), all_added: ($pkgs_all_raw | lines) },
          services: { enabled_by_us: ($services_raw | tsv(2) | map({service:.[0], was:.[1]})) },
          groups: { added: ($groups_raw | lines) },
          udev: ($udev_raw | tsv(2) | map({path:.[0], existed_before:(.[1]=="true")})),
          gsettings: ($gsettings_raw | tsv(2) | map({key:.[0], before:.[1]})),
          created_paths: ($created_raw | tsv(2) | map({path:.[0], owner:.[1]})),
          files: ($files_raw | tsv(6) | map({
                    action:.[0], path:.[1], backup:.[2],
                    existed_before:(.[3]=="true"), is_symlink:(.[4]=="true"),
                    checksum_after:.[5]
                  }))
        }'
}

# ---------------------------------------------------------------------------
# RESTORE side (used by uninstall.sh)
# ---------------------------------------------------------------------------

# rb_resolve_manifest [id]  -> echoes the transaction dir, or empty.
rb_resolve_manifest() {
    local id="$1"
    if [ -n "$id" ] && [ -d "$ROLLBACK_ROOT/$id" ]; then
        echo "$ROLLBACK_ROOT/$id"; return 0
    fi
    if [ -L "$ROLLBACK_ROOT/latest" ] && [ -e "$ROLLBACK_ROOT/latest/manifest.json" ]; then
        readlink -f "$ROLLBACK_ROOT/latest"; return 0
    fi
    # fall back to the newest transaction with a manifest
    local d
    for d in $(ls -1dt "$ROLLBACK_ROOT"/*/ 2>/dev/null); do
        [ -e "$d/manifest.json" ] && { echo "${d%/}"; return 0; }
    done
    echo ""
}
