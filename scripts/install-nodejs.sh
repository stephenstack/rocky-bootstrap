#!/usr/bin/env bash
# scripts/install-nodejs.sh — install Node.js (latest LTS) via NodeSource.
#
# - Queries nodejs.org/dist/index.json to find the latest LTS major (so we
#   don't have to bump a hardcoded "22.x" every six months)
# - Adds the matching NodeSource RPM repo
# - Installs `nodejs` (npm comes bundled)
# - Skips reinstall if `node` is already on the right major version
#
# Override: export NODE_MAJOR_OVERRIDE=20 (or any integer) to pin a specific
# major version instead of the auto-detected LTS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="nodejs"

NODE_MAJOR_OVERRIDE="${NODE_MAJOR_OVERRIDE:-}"
NODESOURCE_BASE="${NODESOURCE_BASE:-https://rpm.nodesource.com}"
NODE_DIST_INDEX="${NODE_DIST_INDEX:-https://nodejs.org/dist/index.json}"

# Will be populated by step_detect_latest_lts.
LATEST_LTS_MAJOR=""
NODE_NEEDS_INSTALL=1

# ---------------------------------------------------------------------------
step_detect_latest_lts() {
    if [[ -n "$NODE_MAJOR_OVERRIDE" ]]; then
        LATEST_LTS_MAJOR="$NODE_MAJOR_OVERRIDE"
        log "NODE_MAJOR_OVERRIDE set; using major version: ${LATEST_LTS_MAJOR}"
        return 0
    fi

    need_cmd curl
    log "querying ${NODE_DIST_INDEX} for latest LTS major version"

    # The index is sorted newest-first. An entry with `lts != false` is an LTS
    # release; the very first such entry is the latest LTS.
    if command -v jq >/dev/null 2>&1; then
        LATEST_LTS_MAJOR="$(curl -fsSL "$NODE_DIST_INDEX" \
            | jq -r '[.[] | select(.lts != false)][0].version' \
            | sed 's/^v//' | cut -d. -f1)"
    else
        # Fallback parser if jq isn't present yet — base.sh installs it, but
        # this role might be invoked standalone. Best-effort regex match on
        # the first record that has a non-false lts codename.
        warn "jq not found; using fallback parser (less reliable — install jq via base role)"
        LATEST_LTS_MAJOR="$(curl -fsSL "$NODE_DIST_INDEX" \
            | grep -oE '\{"version":"v[0-9]+\.[0-9]+\.[0-9]+","[^}]*"lts":"[^"]+"' \
            | head -n1 \
            | grep -oE 'v[0-9]+' | head -n1 | tr -d 'v')"
    fi

    if [[ -z "${LATEST_LTS_MAJOR:-}" || ! "$LATEST_LTS_MAJOR" =~ ^[0-9]+$ ]]; then
        die "could not determine latest Node.js LTS major version (got: '${LATEST_LTS_MAJOR}')"
    fi
    log "latest Node.js LTS major: ${LATEST_LTS_MAJOR}"
}

# ---------------------------------------------------------------------------
step_check_existing() {
    if ! command -v node >/dev/null 2>&1; then
        log "node not installed; will install"
        NODE_NEEDS_INSTALL=1
        return 0
    fi

    local current_major
    current_major="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
    log "node already present: $(node --version 2>/dev/null) (major ${current_major})"

    if [[ "$current_major" == "$LATEST_LTS_MAJOR" ]]; then
        log "already on the target major (${LATEST_LTS_MAJOR}); skipping reinstall"
        NODE_NEEDS_INSTALL=0
    else
        log "current major ${current_major} != target ${LATEST_LTS_MAJOR}; upgrading"
        NODE_NEEDS_INSTALL=1
    fi
}

# ---------------------------------------------------------------------------
step_install_node() {
    if [[ "$NODE_NEEDS_INSTALL" != "1" ]]; then
        return 0
    fi

    local setup_url="${NODESOURCE_BASE}/setup_${LATEST_LTS_MAJOR}.x"
    log "running NodeSource setup script: ${setup_url}"
    # Setup script imports the GPG key, drops a repo file, and runs `dnf clean`.
    # It expects to run as root — we already require_root in main().
    curl -fsSL "$setup_url" | bash -

    log "installing nodejs via dnf"
    dnf install -y nodejs
}

# ---------------------------------------------------------------------------
step_smoke_test() {
    log "node version: $(node --version 2>&1 || echo 'n/a')"
    log "npm version:  $(npm --version 2>&1 || echo 'n/a')"
}

# ---------------------------------------------------------------------------
main() {
    require_root
    log "===== install-nodejs.sh starting ====="
    step_detect_latest_lts
    step_check_existing
    step_install_node
    step_smoke_test
    log "===== install-nodejs.sh complete ====="
}

main "$@"
