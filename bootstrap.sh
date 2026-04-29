#!/usr/bin/env bash
# bootstrap.sh — main entry point for rocky-bootstrap.
#
# Two ways to run:
#
# 1) Local clone:
#      ./bootstrap.sh                  # interactive wizard
#      ./bootstrap.sh base             # single role
#      ./bootstrap.sh all              # everything
#
# 2) Remote (curl-pipe — fetches the rest of the repo on demand):
#      curl -fsSL https://raw.githubusercontent.com/stephenstack/rocky-bootstrap/main/bootstrap.sh \
#        | sudo bash -s -- base
#
# Roles: base, docker, web, monitoring, laravel
# All output is mirrored to /var/log/bootstrap.log.

set -euo pipefail

# --- self-fetch config ---
# Where to grab the rest of the repo from when invoked via curl-pipe.
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/stephenstack/rocky-bootstrap/main}"
# Where to materialise the repo on the target host.
BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-/opt/rocky-bootstrap}"
# Set BOOTSTRAP_REFRESH=1 to wipe the on-disk cache before fetching.
# Useful when iterating: `curl ... | BOOTSTRAP_REFRESH=1 sudo -E bash -s -- base`
BOOTSTRAP_REFRESH="${BOOTSTRAP_REFRESH:-0}"

# Files this script needs to operate. Order matters only for `ensure_repo`'s
# progress output — runtime ordering happens later via role_script().
REPO_FILES=(
    scripts/common.sh
    scripts/base.sh
    scripts/install-docker.sh
    scripts/install-monitoring.sh
    scripts/install-laravel.sh
    scripts/install-nodejs.sh
    scripts/install-bashrc.sh
    scripts/install-starship.sh
    scripts/install-motd.sh
    scripts/install-lamp.sh
    packages.txt
    files/sshd_config
    files/motd
    files/bashrc
    files/starship.toml
    files/login.sh
)

# Order rationale:
#   - bashrc deploys ~/.bashrc cleanly first, so subsequent roles can append to it
#   - starship runs after bashrc to append its init block at the end
#   - motd runs LAST so it can interrogate which services are installed
ALL_ROLES=(base docker monitoring laravel nodejs bashrc starship motd)

# OPTIONAL_ROLES are valid role names that are NOT part of `bootstrap.sh all`.
# Usually because they conflict with another role (e.g. lamp brings its own
# Apache + php-fpm + MariaDB and would clash with `web` and `laravel`).
OPTIONAL_ROLES=(lamp)

# --- bootstrapping ---

# Resolve the directory this script lives in, OR empty string if we were
# piped to bash (no BASH_SOURCE, no $0 path on disk).
self_dir() {
    local src="${BASH_SOURCE[0]:-}"
    if [[ -n "$src" && -f "$src" ]]; then
        (cd "$(dirname "$src")" && pwd)
        return 0
    fi
    echo ""
}

# Make sure we have a working copy of the repo on disk. Idempotent: only
# downloads files that are missing. Safe to re-run.
ensure_repo() {
    local sd
    sd="$(self_dir)"

    # If we're sitting next to the repo already, use it in place.
    if [[ -n "$sd" && -f "${sd}/scripts/common.sh" && -f "${sd}/packages.txt" ]]; then
        REPO_ROOT="$sd"
        return 0
    fi

    # Otherwise we were piped — fetch the repo.
    if ! command -v curl >/dev/null 2>&1; then
        echo "[bootstrap] curl not found; cannot self-fetch repo" >&2
        echo "[bootstrap] install curl first: dnf install -y curl" >&2
        exit 1
    fi

    if [[ "$BOOTSTRAP_REFRESH" == "1" && -d "$BOOTSTRAP_DIR" ]]; then
        echo "[bootstrap] BOOTSTRAP_REFRESH=1 — wiping ${BOOTSTRAP_DIR}"
        rm -rf "$BOOTSTRAP_DIR"
    fi

    echo "[bootstrap] piped invocation — fetching repo to ${BOOTSTRAP_DIR}"
    install -d -m 0755 "${BOOTSTRAP_DIR}/scripts" "${BOOTSTRAP_DIR}/files"

    # Cache-bust GitHub's Fastly CDN by appending a per-run timestamp and
    # asking curl to send no-cache headers. Without this, raw.githubusercontent.com
    # can serve a stale copy for up to ~5 minutes after a push.
    local cb="?cb=$(date +%s)"
    local rel dst
    for rel in "${REPO_FILES[@]}"; do
        dst="${BOOTSTRAP_DIR}/${rel}"
        if [[ "$BOOTSTRAP_REFRESH" != "1" && -f "$dst" && -s "$dst" ]]; then
            echo "[bootstrap]   skip (cached on disk): ${rel}"
            continue
        fi
        echo "[bootstrap]   fetch: ${rel}"
        install -d -m 0755 "$(dirname "$dst")"
        curl -fsSL \
             -H 'Cache-Control: no-cache' \
             -H 'Pragma: no-cache' \
             "${REPO_RAW_BASE}/${rel}${cb}" -o "${dst}" \
            || { echo "[bootstrap] failed to fetch ${rel}" >&2; exit 1; }
    done
    chmod +x "${BOOTSTRAP_DIR}/bootstrap.sh" 2>/dev/null || true
    chmod +x "${BOOTSTRAP_DIR}"/scripts/*.sh

    REPO_ROOT="${BOOTSTRAP_DIR}"
}

ensure_repo
export REPO_ROOT
SCRIPTS_DIR="${REPO_ROOT}/scripts"

# shellcheck source=scripts/common.sh
source "${SCRIPTS_DIR}/common.sh"

BOOTSTRAP_TAG="bootstrap"

# --- role dispatch ---

role_script() {
    case "$1" in
        base)       echo "${SCRIPTS_DIR}/base.sh" ;;
        docker)     echo "${SCRIPTS_DIR}/install-docker.sh" ;;
        monitoring) echo "${SCRIPTS_DIR}/install-monitoring.sh" ;;
        laravel)    echo "${SCRIPTS_DIR}/install-laravel.sh" ;;
        nodejs)     echo "${SCRIPTS_DIR}/install-nodejs.sh" ;;
        bashrc)     echo "${SCRIPTS_DIR}/install-bashrc.sh" ;;
        starship)   echo "${SCRIPTS_DIR}/install-starship.sh" ;;
        motd)       echo "${SCRIPTS_DIR}/install-motd.sh" ;;
        lamp)       echo "${SCRIPTS_DIR}/install-lamp.sh" ;;
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

Curl-pipe form:
  curl -fsSL ${REPO_RAW_BASE}/bootstrap.sh | sudo bash -s -- base
  curl -fsSL ${REPO_RAW_BASE}/bootstrap.sh | sudo bash -s -- all

Roles:
  base        SELinux off, projects dir, packages, EU/Dublin TZ + .ie NTP, firewalld, fail2ban
  docker      Docker CE + compose plugin
  monitoring  Grafana Alloy agent (placeholder config)
  laravel     PHP 8.3, Composer, php-fpm, Nginx site stub
  nodejs      Node.js (latest LTS auto-detected) via NodeSource
  bashrc      Curated ~/.bashrc (PATH, NVM, fzf, eza, zoxide, aliases)
  starship    Starship prompt + FiraCode Nerd Font + ~/.bashrc wiring
  motd        Dynamic login banner (figlet + conditional service summary)

Optional roles (NOT part of 'all' — call explicitly):
  lamp        Upstream rConfig LAMP installer (Apache + PHP + MariaDB + Redis)
              Conflicts with 'web' and 'laravel' — run on its own host.

Environment overrides:
  TZ=Europe/Dublin              timezone applied by base.sh
  NTP_SERVERS="ie.pool.ntp.org ntp1.tcd.ie ntp2.tcd.ie"  chrony servers
  REPO_RAW_BASE=...             override the raw.githubusercontent base URL
  BOOTSTRAP_DIR=/opt/rocky-bootstrap  where to materialise the repo
  BOOTSTRAP_REFRESH=1           wipe cache + bust CDN before re-fetching
  APP_DIR=/var/www/laravel      app directory used by laravel role
  APP_DOMAIN=_                  nginx server_name for laravel role
  NODE_MAJOR_OVERRIDE=22        pin nodejs to a specific major (default: latest LTS)
  PROMETHEUS_REMOTE_WRITE_URL   used by monitoring role
  LOKI_PUSH_URL                 used by monitoring role
  RCONFIG_DBPASS=...            unattended MariaDB setup for lamp role

Repo cache: ${REPO_ROOT}
Logs:       ${BOOTSTRAP_LOG}
EOF
}

preflight() {
    require_root
    local role script
    for role in "${ALL_ROLES[@]}" "${OPTIONAL_ROLES[@]}"; do
        script="$(role_script "$role")"
        [[ -f "$script" ]] || die "missing role script: $script"
        [[ -x "$script" ]] || chmod +x "$script"
    done
    : >>"$BOOTSTRAP_LOG" || die "cannot write to $BOOTSTRAP_LOG"
}

run_role() {
    local role="$1"
    local script
    script="$(role_script "$role")" || die "unknown role: $role"
    log ">>> running role: $role ($script)"
    if bash "$script"; then
        log "<<< role complete: $role"
    else
        local rc=$?
        err "role failed: $role (exit $rc)"
        return "$rc"
    fi
}

wizard() {
    cat <<EOF

==============================================
 rocky-bootstrap — interactive setup
==============================================
 Host: $(hostname)
 OS:   $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")
 Repo: ${REPO_ROOT}
 Log:  ${BOOTSTRAP_LOG}
==============================================

Pick what to install. Enter:
  - a single role number (e.g. 1)
  - multiple, space-separated (e.g. 1 2 3)
  - "a" or "all" to run everything
  - "q" to quit

  1) base         (always recommended first)
  2) docker
  3) monitoring   (Grafana Alloy — edit endpoints!)
  4) laravel      (PHP 8.3 + Composer + php-fpm)
  5) nodejs       (Node.js latest LTS via NodeSource)
  6) bashrc       (curated ~/.bashrc — run before starship)
  7) starship     (Starship prompt + FiraCode Nerd Font)
  8) motd         (login banner — run last for full service detection)
  9) lamp         (rConfig LAMP installer — conflicts with laravel)
  a) all          (excludes lamp)
  q) quit

EOF

    local choice
    read -r -p "Selection: " choice
    choice="${choice,,}"

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
            3) selected+=(monitoring) ;;
            4) selected+=(laravel) ;;
            5) selected+=(nodejs) ;;
            6) selected+=(bashrc) ;;
            7) selected+=(starship) ;;
            8) selected+=(motd) ;;
            9) selected+=(lamp) ;;
            *) die "invalid selection: $n" ;;
        esac
    done

    run_roles "${selected[@]}"
}

run_roles() {
    local -a wanted=("$@")
    local -a ordered=()
    local seen=""
    local r

    for r in "${wanted[@]}"; do
        if [[ "$r" == "base" ]]; then
            ordered+=(base)
            seen="${seen}|base|"
            break
        fi
    done

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

    # No args:
    #   - With a tty: launch the interactive wizard.
    #   - Without a tty (curl-pipe, ansible exec, etc.): refuse to guess.
    #     Running 'all' implicitly is too destructive to be a sensible default,
    #     and the wizard can't read input from a closed stdin.
    if [[ $# -eq 0 ]]; then
        if [[ -t 0 ]]; then
            wizard
            exit 0
        fi

        cat >&2 <<EOF
[bootstrap] no roles specified, and stdin is not a terminal.
[bootstrap] refusing to run 'all' implicitly — too destructive for a silent default.

To run a specific role via curl-pipe, pass it after '-s --':

    curl -fsSL ${REPO_RAW_BASE}/bootstrap.sh | sudo bash -s -- base
    curl -fsSL ${REPO_RAW_BASE}/bootstrap.sh | sudo bash -s -- base nodejs bashrc starship
    curl -fsSL ${REPO_RAW_BASE}/bootstrap.sh | sudo bash -s -- all

To use the interactive wizard, download first then run:

    curl -fsSL ${REPO_RAW_BASE}/bootstrap.sh -o /tmp/bootstrap.sh
    sudo bash /tmp/bootstrap.sh
EOF
        exit 2
    fi

    if [[ "$1" == "all" ]]; then
        run_all
        exit 0
    fi

    local arg
    for arg in "$@"; do
        role_script "$arg" >/dev/null || { usage; die "unknown role: $arg"; }
    done

    run_roles "$@"
}

main "$@"
