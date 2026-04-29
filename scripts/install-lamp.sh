#!/usr/bin/env bash
# scripts/install-lamp.sh — delegate to the upstream rConfig LAMP installer.
#
# Downloads rconfig8_centos9.sh and runs it end-to-end. By design, this
# duplicates work that other roles (base, web, laravel) already do — SELinux
# disable, dnf upgrade, package installs, etc. The user explicitly wants the
# upstream installer to run in full so the resulting environment matches what
# the rConfig 8 docs describe.
#
# This role is NOT included in `bootstrap.sh all` — it conflicts with the
# `web` (nginx) and `laravel` (php-fpm) roles. Run it explicitly:
#     ./bootstrap.sh lamp
#
# Env tunables:
#     RCONFIG_DBPASS=<password>   set to skip the interactive
#                                 mariadb-secure-installation wizard
#     RCONFIG_INSTALL_URL=...     override the upstream installer URL
#     RCONFIG_INSTALL_DIR=...     where to drop the installer + its log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="lamp"

RCONFIG_INSTALL_URL="${RCONFIG_INSTALL_URL:-https://dl.rconfig.com/downloads/rconfig8_centos9.sh}"
RCONFIG_INSTALL_DIR="${RCONFIG_INSTALL_DIR:-${REPO_ROOT}/vendor}"
RCONFIG_INSTALLER="${RCONFIG_INSTALLER:-${RCONFIG_INSTALL_DIR}/rconfig-install.sh}"
RCONFIG_DBPASS="${RCONFIG_DBPASS:-}"

step_fetch_installer() {
    install -d -m 0755 "$RCONFIG_INSTALL_DIR"

    log "downloading rConfig installer from: $RCONFIG_INSTALL_URL"
    # Always re-download — the upstream script may have changed since the
    # last run, and re-running is the user's stated intent.
    curl -fsSL "$RCONFIG_INSTALL_URL" -o "$RCONFIG_INSTALLER"
    chmod 0755 "$RCONFIG_INSTALLER"
    log "saved to: $RCONFIG_INSTALLER"
}

step_run_installer() {
    log "===== running upstream rConfig installer ====="
    log "duplicate work (SELinux, dnf upgrade, etc.) is expected and intentional"
    log "installer will write its own log to: ${RCONFIG_INSTALL_DIR}/install.log"

    local args=(--no-color)
    if [[ -n "$RCONFIG_DBPASS" ]]; then
        log "RCONFIG_DBPASS set; running unattended (mariadb-secure-installation will be automated)"
        args+=("$RCONFIG_DBPASS")
    else
        warn "RCONFIG_DBPASS not set — mariadb-secure-installation will run interactively"
        warn "if running via curl-pipe with no tty, set RCONFIG_DBPASS to avoid hanging"
    fi

    # cd into the installer's directory so its relative LOGFILE=install.log
    # lands in a predictable place. Run in a subshell so cwd doesn't leak.
    (
        cd "$RCONFIG_INSTALL_DIR"
        bash "$RCONFIG_INSTALLER" "${args[@]}"
    )
}

main() {
    require_root
    log "===== install-lamp.sh starting ====="
    need_cmd curl
    step_fetch_installer
    step_run_installer
    log "===== install-lamp.sh complete ====="
    log "Note: the upstream installer may have replaced /etc/profile.d/login.sh."
    log "Re-run the 'motd' role afterwards to restore the dynamic banner."
}

main "$@"
