#!/usr/bin/env bash
# scripts/base.sh — base system setup.
#
# - Verify running as root
# - Disable SELinux (config + runtime, modeled on /home/install.sh)
# - Create ~/.Projects in the invoking user's home
# - Update the system
# - Install packages from packages.txt
# - Set timezone (default Europe/Dublin)
# - Configure chrony with .ie NTP servers (TCD + ie.pool.ntp.org)
# - Enable + start firewalld, fail2ban
#
# Idempotent: re-running just verifies the state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="base"

# --- tunables (override via env) ---
# Default region is Europe/Dublin (Ireland) with .ie NTP servers.
# Override TZ and NTP_SERVERS via env if deploying outside IE.
TZ="${TZ:-Europe/Dublin}"
# Space-separated list of chrony "server <host> iburst" entries.
NTP_SERVERS="${NTP_SERVERS:-ie.pool.ntp.org ntp1.tcd.ie ntp2.tcd.ie}"
CHRONY_CONF="/etc/chrony.conf"

step_disable_selinux() {
    # Modeled on /home/install.sh f_disable_selinux: flip the config to disabled
    # and drop runtime enforcement immediately. A reboot is still required for
    # the kernel to fully unload SELinux — we warn but do not auto-reboot,
    # because this script is part of a larger bootstrap chain.

    if [[ ! -f /etc/selinux/config ]]; then
        log "SELinux config not present; nothing to disable"
        return 0
    fi

    local current
    current="$(grep -E '^SELINUX=' /etc/selinux/config | cut -d= -f2 || true)"
    log "current SELinux config: ${current:-unknown}"

    if [[ "$current" != "disabled" ]]; then
        log "setting SELINUX=disabled in /etc/selinux/config"
        backup_once /etc/selinux/config
        sed -i 's|^SELINUX=.*|SELINUX=disabled|' /etc/selinux/config
    else
        log "SELinux already disabled in config"
    fi

    if command -v setenforce >/dev/null 2>&1; then
        local mode
        mode="$(getenforce 2>/dev/null || echo 'Disabled')"
        if [[ "$mode" != "Disabled" && "$mode" != "Permissive" ]]; then
            log "dropping SELinux to permissive for current runtime"
            setenforce 0 || warn "setenforce 0 failed (continuing)"
        else
            log "SELinux runtime already $mode"
        fi
    fi

    warn "SELinux disabled. A reboot is required for the kernel to fully unload it."
}

step_add_projects_dir() {
    # Create ~/.Projects in the invoking user's home (root, since require_root
    # gates entry to this script).
    local home_dir="${HOME:-/root}"
    local projects="${home_dir}/.Projects"
    if [[ -d "$projects" ]]; then
        log "projects dir already exists: $projects"
    else
        log "creating projects dir: $projects"
        install -d -m 0755 "$projects"
    fi
}

step_update_system() {
    log "updating system packages (dnf upgrade)"
    dnf -y upgrade --refresh
}

step_install_core_packages() {
    log "reading package list from $PACKAGES_FILE"
    mapfile -t pkgs < <(read_package_list)
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        warn "package list is empty, skipping"
        return 0
    fi
    dnf_install "${pkgs[@]}"
}

step_set_timezone() {
    # Default deployment region is Ireland (Europe/Dublin).
    # Override by exporting TZ before running, e.g. TZ=Europe/London.
    local current
    current="$(timedatectl show -p Timezone --value 2>/dev/null || echo '')"
    if [[ "$current" != "$TZ" ]]; then
        log "setting timezone to $TZ (was: $current)"
        timedatectl set-timezone "$TZ"
    else
        log "timezone already set to $TZ"
    fi
}

step_configure_chrony() {
    # Install + configure chrony with .ie NTP servers (Trinity College Dublin
    # + the Ireland pool). Override the server list with NTP_SERVERS=... if
    # deploying outside Ireland.
    dnf_install chrony

    log "writing chrony config with servers: ${NTP_SERVERS}"
    backup_once "$CHRONY_CONF"

    # Build a fresh minimal config — keep it small and predictable. The Rocky
    # default config has a lot of commentary we don't need to preserve.
    {
        echo "# Managed by rocky-bootstrap (scripts/base.sh)"
        echo "# Region: ${TZ} — using Ireland NTP servers by default"
        for s in ${NTP_SERVERS}; do
            echo "server ${s} iburst"
        done
        echo "driftfile /var/lib/chrony/drift"
        echo "makestep 1.0 3"
        echo "rtcsync"
        echo "logdir /var/log/chrony"
    } >"$CHRONY_CONF"

    svc_enable chronyd
    svc_restart chronyd

    # Quick visibility into time sync state — non-fatal if it fails.
    log "chrony tracking:"
    chronyc tracking 2>&1 | sed 's/^/    /' || true
    log "chrony sources:"
    chronyc sources -v 2>&1 | sed 's/^/    /' || true
}

step_enable_services() {
    # chronyd is enabled by step_configure_chrony — don't duplicate here.

    # Firewall.
    svc_enable firewalld

    # Make sure SSH stays open (firewalld default zone allows it, but be explicit).
    if ! firewall-cmd --permanent --query-service=ssh >/dev/null 2>&1; then
        log "adding ssh service to firewalld"
        firewall-cmd --permanent --add-service=ssh >/dev/null
        firewall-cmd --reload >/dev/null
    fi

    # fail2ban — config left at distro defaults; tune later as needed.
    svc_enable fail2ban
}

main() {
    require_root
    log "===== base.sh starting ====="
    step_disable_selinux
    step_add_projects_dir
    step_update_system
    step_install_core_packages
    step_set_timezone
    step_configure_chrony
    step_enable_services
    log "===== base.sh complete ====="
}

main "$@"
