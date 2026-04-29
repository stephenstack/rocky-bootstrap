#!/usr/bin/env bash
# scripts/install-docker.sh — Docker CE + Compose plugin on Rocky 9.
#
# Adds the official Docker CE repo, installs the engine, enables the service,
# and (optionally) adds the admin user to the `docker` group.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="docker"

ADMIN_USER="${ADMIN_USER:-admin}"
DOCKER_REPO_URL="https://download.docker.com/linux/centos/docker-ce.repo"

step_remove_legacy_docker() {
    # Rocky 9 may ship `podman-docker` or older `docker` packages.
    # Remove only if present — never fail if they aren't.
    local legacy=(docker docker-client docker-client-latest docker-common \
                  docker-latest docker-latest-logrotate docker-logrotate \
                  docker-engine podman-docker)
    local found=()
    for p in "${legacy[@]}"; do
        if pkg_installed "$p"; then
            found+=("$p")
        fi
    done
    if [[ ${#found[@]} -gt 0 ]]; then
        log "removing legacy packages: ${found[*]}"
        dnf -y remove "${found[@]}"
    else
        log "no legacy docker packages present"
    fi
}

step_add_docker_repo() {
    if [[ -f /etc/yum.repos.d/docker-ce.repo ]]; then
        log "docker-ce repo already configured"
        return 0
    fi
    need_cmd dnf-3 || true   # not strictly required, but sanity-check dnf is present
    log "adding docker-ce repo"
    dnf-3 config-manager --add-repo "$DOCKER_REPO_URL" 2>/dev/null \
        || dnf config-manager --add-repo "$DOCKER_REPO_URL"
}

step_install_docker() {
    dnf_install docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin
}

step_enable_docker() {
    svc_enable docker
}

step_add_user_to_docker_group() {
    if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
        warn "admin user '$ADMIN_USER' does not exist; skipping group add. Run base.sh first."
        return 0
    fi
    if id -nG "$ADMIN_USER" | tr ' ' '\n' | grep -qx docker; then
        log "$ADMIN_USER already in docker group"
    else
        log "adding $ADMIN_USER to docker group"
        usermod -aG docker "$ADMIN_USER"
        warn "$ADMIN_USER must log out and back in for docker group to apply"
    fi
}

step_smoke_test() {
    log "docker version: $(docker --version 2>/dev/null || echo 'n/a')"
    log "compose version: $(docker compose version 2>/dev/null || echo 'n/a')"
}

main() {
    require_root
    log "===== install-docker.sh starting ====="
    step_remove_legacy_docker
    step_add_docker_repo
    step_install_docker
    step_enable_docker
    step_add_user_to_docker_group
    step_smoke_test
    log "===== install-docker.sh complete ====="
}

main "$@"
