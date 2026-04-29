#!/usr/bin/env bash
# scripts/common.sh — shared helpers sourced by every role script.
#
# Provides:
#   log / warn / err / die  — consistent stdout + /var/log/bootstrap.log output
#   require_root            — abort if not running as uid 0
#   pkg_installed           — true if an rpm package is installed
#   dnf_install             — install only packages that aren't already there
#   svc_enable              — enable + start a systemd unit if not already running
#   need_cmd                — die with a helpful message if a command is missing
#
# This file is sourced, not executed. Do not add `set -euo pipefail` here —
# the parent script controls shell options. Functions inherit them.

# Idempotent guard — if already sourced, do nothing.
if [[ "${__BOOTSTRAP_COMMON_SOURCED:-}" == "1" ]]; then
    return 0
fi
__BOOTSTRAP_COMMON_SOURCED=1

# --- paths ---
BOOTSTRAP_LOG="${BOOTSTRAP_LOG:-/var/log/bootstrap.log}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FILES_DIR="${REPO_ROOT}/files"
PACKAGES_FILE="${REPO_ROOT}/packages.txt"

# --- logging ---
# All log lines go to stdout AND get appended to BOOTSTRAP_LOG.
# Timestamped, with a tag so you can grep per-role.
_log() {
    local level="$1"; shift
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local line="[${ts}] [${level}] [${BOOTSTRAP_TAG:-bootstrap}] $*"
    printf '%s\n' "$line"
    # Best-effort log file write; don't fail the script if /var/log isn't writable yet.
    printf '%s\n' "$line" >>"$BOOTSTRAP_LOG" 2>/dev/null || true
}
log()  { _log "INFO"  "$@"; }
warn() { _log "WARN"  "$@" >&2; }
err()  { _log "ERROR" "$@" >&2; }
die()  { err "$@"; exit 1; }

# --- preflight ---
require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "Must run as root (uid 0). Try: sudo $0"
    fi
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# --- package helpers ---
pkg_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

# Install one or more packages, skipping any that are already present.
# Usage: dnf_install pkg1 pkg2 ...
dnf_install() {
    local to_install=()
    local pkg
    for pkg in "$@"; do
        if pkg_installed "$pkg"; then
            log "package already installed: $pkg"
        else
            to_install+=("$pkg")
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        return 0
    fi

    log "installing: ${to_install[*]}"
    dnf install -y "${to_install[@]}"
}

# --- systemd helpers ---
svc_enable() {
    local unit="$1"
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        log "service already enabled: $unit"
    else
        log "enabling service: $unit"
        systemctl enable "$unit"
    fi

    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        log "service already running: $unit"
    else
        log "starting service: $unit"
        systemctl start "$unit"
    fi
}

svc_restart() {
    local unit="$1"
    log "restarting service: $unit"
    systemctl restart "$unit"
}

# --- file helpers ---
# Backup a file once (won't overwrite an existing .bootstrap-bak).
backup_once() {
    local target="$1"
    if [[ -f "$target" && ! -f "${target}.bootstrap-bak" ]]; then
        cp -a "$target" "${target}.bootstrap-bak"
        log "backed up $target -> ${target}.bootstrap-bak"
    fi
}

# Read packages.txt, stripping comments and blank lines.
read_package_list() {
    [[ -f "$PACKAGES_FILE" ]] || die "package list not found: $PACKAGES_FILE"
    sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$PACKAGES_FILE"
}
