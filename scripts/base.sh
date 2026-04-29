#!/usr/bin/env bash
# scripts/base.sh — base system setup.
#
# Order of operations (matters!):
#   1. require_root
#   2. disable SELinux (config + runtime)
#   3. create ~/.Projects
#   4. dnf upgrade --refresh
#   5. install epel-release + enable CRB        ← must be before any EPEL pkgs
#   6. install bulk packages from packages.txt
#   7. install dev/ops tools (mod_ssl, jq, ripgrep, btop, etc.)
#   8. fzf from upstream git (rpm version is older)
#   9. zoxide (upstream installer)
#   10. eza (upstream release tarball)
#   11. timezone
#   12. chrony with .ie NTP servers
#   13. enable firewalld + fail2ban
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

# Architecture for prebuilt binaries (eza). Override on arm64 hosts.
EZA_ARCH="${EZA_ARCH:-x86_64-unknown-linux-gnu}"

# ---------------------------------------------------------------------------
# Step: SELinux
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Step: ~/.Projects
# ---------------------------------------------------------------------------
step_add_projects_dir() {
    local home_dir="${HOME:-/root}"
    local projects="${home_dir}/.Projects"
    if [[ -d "$projects" ]]; then
        log "projects dir already exists: $projects"
    else
        log "creating projects dir: $projects"
        install -d -m 0755 "$projects"
    fi
}

# ---------------------------------------------------------------------------
# Step: system update
# ---------------------------------------------------------------------------
step_update_system() {
    log "updating system packages (dnf upgrade)"
    dnf -y upgrade --refresh
}

# ---------------------------------------------------------------------------
# Step: EPEL + CRB
# Must run BEFORE any package install that pulls from EPEL
# (htop, fail2ban, btop, fzf, jq, ripgrep all live there).
# ---------------------------------------------------------------------------
step_install_epel() {
    dnf_install epel-release dnf-plugins-core

    # CRB (CodeReady Builder) is Rocky's PowerTools equivalent — required by
    # several EPEL build-dependencies. Idempotent: config-manager is a no-op
    # when the repo is already enabled.
    if dnf repolist --enabled 2>/dev/null | awk '{print $1}' | grep -qx crb; then
        log "CRB repo already enabled"
    else
        log "enabling CRB repo"
        dnf config-manager --set-enabled crb
    fi

    log "refreshing dnf metadata"
    dnf -y makecache
}

# ---------------------------------------------------------------------------
# Step: bulk packages from packages.txt
# ---------------------------------------------------------------------------
step_install_core_packages() {
    log "reading package list from $PACKAGES_FILE"
    mapfile -t pkgs < <(read_package_list)
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        warn "package list is empty, skipping"
        return 0
    fi
    dnf_install "${pkgs[@]}"
}

# ---------------------------------------------------------------------------
# Step: dev/ops tools batch
# These come from baseos + EPEL + CRB, hence the dependency on step_install_epel.
# Duplicates with packages.txt are harmless — dnf_install skips installed pkgs.
# ---------------------------------------------------------------------------
step_install_dev_tools() {
    dnf_install \
        git \
        mod_ssl \
        fzf \
        jq \
        ripgrep \
        tree \
        unzip \
        tar \
        btop \
        bind-utils \
        vim-enhanced \
        wget
}

# ---------------------------------------------------------------------------
# Step: fzf from upstream git
# The EPEL fzf package is older and does not include the latest keybinding
# / completion scripts. We remove it and install via the upstream installer.
# The installer is idempotent — re-running won't duplicate ~/.bashrc entries.
# ---------------------------------------------------------------------------
step_install_fzf_from_source() {
    if pkg_installed fzf; then
        log "removing rpm fzf in favour of upstream build"
        dnf -y remove fzf
    fi

    local home_dir="${HOME:-/root}"
    local fzf_dir="${home_dir}/.fzf"

    if [[ -d "${fzf_dir}/.git" ]]; then
        log "fzf already cloned at ${fzf_dir}; pulling latest"
        git -C "$fzf_dir" pull --ff-only || warn "fzf git pull failed (continuing)"
    else
        log "cloning fzf into ${fzf_dir}"
        git clone --depth 1 https://github.com/junegunn/fzf.git "$fzf_dir"
    fi

    # --all answers yes to: enable key bindings, enable completion, update rc.
    # The installer detects existing config blocks and won't duplicate them.
    log "running fzf installer (--all)"
    "${fzf_dir}/install" --all
}

# ---------------------------------------------------------------------------
# Step: zoxide (smarter `cd`)
# ---------------------------------------------------------------------------
step_install_zoxide() {
    if command -v zoxide >/dev/null 2>&1; then
        log "zoxide already installed: $(zoxide --version 2>/dev/null | head -n1)"
        return 0
    fi
    log "installing zoxide via upstream installer"
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
}

# ---------------------------------------------------------------------------
# Step: eza (modern `ls` replacement)
# Pulled directly from GitHub releases — no Rocky/EPEL package available.
# ---------------------------------------------------------------------------
step_install_eza() {
    if command -v eza >/dev/null 2>&1; then
        log "eza already installed: $(eza --version 2>/dev/null | head -n1)"
        return 0
    fi

    log "downloading latest eza release for ${EZA_ARCH}"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN

    local url="https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}.tar.gz"
    curl -fsSL -o "${tmp}/eza.tar.gz" "$url"
    tar -xzf "${tmp}/eza.tar.gz" -C "$tmp"
    install -m 0755 "${tmp}/eza" /usr/local/bin/eza
    log "eza version: $(eza --version 2>&1 | head -n1)"
}

# ---------------------------------------------------------------------------
# Step: timezone
# ---------------------------------------------------------------------------
step_set_timezone() {
    local current
    current="$(timedatectl show -p Timezone --value 2>/dev/null || echo '')"
    if [[ "$current" != "$TZ" ]]; then
        log "setting timezone to $TZ (was: $current)"
        timedatectl set-timezone "$TZ"
    else
        log "timezone already set to $TZ"
    fi
}

# ---------------------------------------------------------------------------
# Step: chrony / NTP
# ---------------------------------------------------------------------------
step_configure_chrony() {
    # Install + configure chrony with .ie NTP servers (Trinity College Dublin
    # + the Ireland pool). Override the server list with NTP_SERVERS=... if
    # deploying outside Ireland.
    dnf_install chrony

    backup_once "$CHRONY_CONF"

    # Render desired config to a temp file; only swap + restart if it actually
    # changed. This makes re-runs a true no-op (no log spam, no service blip).
    local tmp
    tmp="$(mktemp)"
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
    } >"$tmp"

    if [[ -f "$CHRONY_CONF" ]] && cmp -s "$tmp" "$CHRONY_CONF"; then
        log "chrony config unchanged; not restarting"
        svc_enable chronyd
        rm -f "$tmp"
    else
        log "writing chrony config with servers: ${NTP_SERVERS}"
        install -m 0644 "$tmp" "$CHRONY_CONF"
        rm -f "$tmp"
        svc_enable chronyd
        svc_restart chronyd
    fi

    # Quick visibility into time sync state — non-fatal if it fails.
    log "chrony tracking:"
    chronyc tracking 2>&1 | sed 's/^/    /' || true
    log "chrony sources:"
    chronyc sources -v 2>&1 | sed 's/^/    /' || true
}

# ---------------------------------------------------------------------------
# Step: services + firewall
# ---------------------------------------------------------------------------
step_enable_services() {
    # chronyd is enabled by step_configure_chrony — don't duplicate here.

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

# ---------------------------------------------------------------------------
main() {
    require_root
    log "===== base.sh starting ====="
    step_disable_selinux
    step_add_projects_dir
    step_update_system
    step_install_epel              # before any EPEL packages
    step_install_core_packages
    step_install_dev_tools
    step_install_fzf_from_source
    step_install_zoxide
    step_install_eza
    step_set_timezone
    step_configure_chrony
    step_enable_services
    log "===== base.sh complete ====="
}

main "$@"
