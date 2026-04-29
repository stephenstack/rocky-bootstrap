#!/usr/bin/env bash
# scripts/install-motd.sh — fancy login banner for /etc/profile.d/login.sh.
#
# Designed to run LAST in the bootstrap order so it can detect what's been
# installed by the other roles (nginx, php, docker, mariadb, redis, alloy, ...)
# and only show the relevant lines in the banner.
#
# Steps:
#   - Install figlet (EPEL) for the ASCII hostname banner
#   - Drop the curated login.sh template at /etc/profile.d/login.sh
#   - Disable the legacy /etc/motd installed by previous bootstraps
#
# Idempotent: re-running just refreshes the script in place.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="motd"

PROFILE_D_TARGET="/etc/profile.d/login.sh"

step_install_figlet() {
    # figlet renders the hostname banner. Lives in EPEL on Rocky 9.
    # If EPEL hasn't been enabled (i.e. the user runs `motd` without `base`),
    # try to install anyway — dnf will tell them what's wrong.
    dnf_install figlet || warn "figlet install failed; banner will fall back to plain text"
}

step_deploy_login_script() {
    local src="${FILES_DIR}/login.sh"
    [[ -f "$src" ]] || die "missing $src"

    if [[ -f "$PROFILE_D_TARGET" ]] && cmp -s "$src" "$PROFILE_D_TARGET"; then
        log "login.sh already up to date at $PROFILE_D_TARGET"
        return 0
    fi

    backup_once "$PROFILE_D_TARGET"
    install -m 0755 -o root -g root "$src" "$PROFILE_D_TARGET"
    log "deployed login banner to $PROFILE_D_TARGET"
}

step_clear_static_motd() {
    # An earlier version of base.sh installed a static /etc/motd. The new
    # /etc/profile.d/login.sh is dynamic and renders its own banner, so the
    # static one is redundant. Empty it (don't delete — some auditing tools
    # expect the file to exist).
    if [[ -s /etc/motd ]]; then
        backup_once /etc/motd
        : >/etc/motd
        log "cleared static /etc/motd (now rendered by login.sh)"
    fi
}

step_smoke_test() {
    # Render the banner once into the bootstrap log so you can verify what
    # users will see on their next login. Doesn't actually log them in.
    log "preview of login banner (output below):"
    bash -i -c "source $PROFILE_D_TARGET" 2>&1 | sed 's/^/    /' || true
}

main() {
    require_root
    log "===== install-motd.sh starting ====="
    step_install_figlet
    step_deploy_login_script
    step_clear_static_motd
    step_smoke_test
    log "===== install-motd.sh complete ====="
    log "Banner will appear on the next interactive login."
}

main "$@"
