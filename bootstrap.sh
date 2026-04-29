#!/usr/bin/env bash
# bootstrap.sh — main entry point for rocky-bootstrap.
#
# Usage:
#   ./bootstrap.sh                  # interactive wizard
#   ./bootstrap.sh <role> [...]     # run one or more roles
#   ./bootstrap.sh all              # run every role in recommended order
#   ./bootstrap.sh -h | --help
#
# Roles: base, docker, web, monitoring, laravel
#
# All output is mirrored to /var/log/bootstrap.log.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
export REPO_ROOT

# shellcheck source=scripts/common.sh
source "${SCRIPTS_DIR}/common.sh"

BOOTSTRAP_TAG="bootstrap"

# Roles, in the order `all` should run them. Order matters:
# base first (creates user, repos, firewall), then services that depend on it.
ALL_ROLES=(base docker web monitoring laravel)

# role -> script filename
role_script() {
    case "$1" in
        base)       echo "${SCRIPTS_DIR}/base.sh" ;;
        docker)     echo "${SCRIPTS_DIR}/install-docker.sh" ;;
        web)        echo "${SCRIPTS_DIR}/install-web.sh" ;;
        monitoring) echo "${SCRIPTS_DIR}/install-monitoring.sh" ;;
        laravel)    echo "${SCRIPTS_DIR}/install-laravel.sh" ;;
        *)          return 1 ;;
    esac
}

usage() {
    cat <<EOF
rocky-bootstrap — provision a Rocky Linux 9 server.

Usage:
  $(basename "$0")                 interactive wizard
  $(basename "$0") <role> [...]    run one or more roles
  $(basename "$0") all             run every role in order
  $(basename "$0") -h | --help     show this help

Roles:
  base        system update, packages, admin user, SSH hardening, firewall
  docker      Docker CE + compose plugin
  web         Nginx
  monitoring  Grafana Alloy agent (placeholder config)
  laravel     PHP 8.3, Composer, php-fpm, Nginx site stub

Environment overrides:
  ADMIN_USER=admin              admin user created/used by scripts
  TZ=UTC                        timezone applied by base.sh
  APPLY_SSH_CONFIG=no           set to "yes" to overwrite /etc/ssh/sshd_config
  APP_DIR=/var/www/laravel      app directory used by laravel role
  APP_DOMAIN=_                  nginx server_name for laravel role
  PROMETHEUS_REMOTE_WRITE_URL   used by monitoring role
  LOKI_PUSH_URL                 used by monitoring role

Logs: ${BOOTSTRAP_LOG}
EOF
}

# Confirm we have an executable script for each role.
preflight() {
    require_root
    local role script
    for role in "${ALL_ROLES[@]}"; do
        script="$(role_script "$role")"
        [[ -f "$script" ]] || die "missing role script: $script"
        [[ -x "$script" ]] || chmod +x "$script"
    done
    # Make sure the log file exists and is writable.
    : >>"$BOOTSTRAP_LOG" || die "cannot write to $BOOTSTRAP_LOG"
}

run_role() {
    local role="$1"
    local script
    script="$(role_script "$role")" || die "unknown role: $role"
    log ">>> running role: $role ($script)"
    # Run via bash so we don't depend on the +x bit and so set -e in the parent
    # doesn't swallow useful info from the child.
    if bash "$script"; then
        log "<<< role complete: $role"
    else
        local rc=$?
        err "role failed: $role (exit $rc)"
        return "$rc"
    fi
}

# Interactive menu. Lets the user pick one or more roles.
wizard() {
    cat <<EOF

==============================================
 rocky-bootstrap — interactive setup
==============================================
 Host: $(hostname)
 OS:   $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")
 Log:  ${BOOTSTRAP_LOG}
==============================================

Pick what to install. Enter:
  - a single role number (e.g. 1)
  - multiple, space-separated (e.g. 1 2 3)
  - "a" or "all" to run everything
  - "q" to quit

  1) base         (always recommended first)
  2) docker
  3) web          (Nginx)
  4) monitoring   (Grafana Alloy — edit endpoints!)
  5) laravel      (PHP 8.3 + Composer + Nginx site)
  a) all
  q) quit

EOF

    local choice
    read -r -p "Selection: " choice
    choice="${choice,,}"   # lowercase

    case "$choice" in
        q|quit|exit) log "user quit"; exit 0 ;;
        a|all)       run_all; return ;;
        "")          die "no selection" ;;
    esac

    local selected=()
    local n
    for n in $choice; do
        case "$n" in
            1) selected+=(base) ;;
            2) selected+=(docker) ;;
            3) selected+=(web) ;;
            4) selected+=(monitoring) ;;
            5) selected+=(laravel) ;;
            *) die "invalid selection: $n" ;;
        esac
    done

    run_roles "${selected[@]}"
}

# Run a list of roles, de-duplicated, with `base` always first if present.
run_roles() {
    local -a wanted=("$@")
    local -a ordered=()
    local seen=""
    local r

    # Force base to the front if it's in the list.
    for r in "${wanted[@]}"; do
        if [[ "$r" == "base" ]]; then
            ordered+=(base)
            seen="${seen}|base|"
            break
        fi
    done

    # Append the rest in the order given, skipping duplicates.
    for r in "${wanted[@]}"; do
        if [[ "$seen" != *"|$r|"* ]]; then
            ordered+=("$r")
            seen="${seen}|$r|"
        fi
    done

    log "plan: ${ordered[*]}"
    for r in "${ordered[@]}"; do
        run_role "$r"
    done
    log "all selected roles complete"
}

run_all() {
    run_roles "${ALL_ROLES[@]}"
}

main() {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            -h|--help|help) usage; exit 0 ;;
        esac
    fi

    preflight

    if [[ $# -eq 0 ]]; then
        wizard
        exit 0
    fi

    if [[ "$1" == "all" ]]; then
        run_all
        exit 0
    fi

    # Validate every arg before running anything.
    local arg
    for arg in "$@"; do
        role_script "$arg" >/dev/null || { usage; die "unknown role: $arg"; }
    done

    run_roles "$@"
}

main "$@"
