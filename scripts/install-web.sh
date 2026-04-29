#!/usr/bin/env bash
# scripts/install-web.sh — Nginx web server.
#
# Installs Nginx from the Rocky AppStream, enables it, opens http/https
# in firewalld, and drops a placeholder index page so you can verify it works.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="web"

WEBROOT="${WEBROOT:-/usr/share/nginx/html}"

step_install_nginx() {
    dnf_install nginx
}

step_open_firewall() {
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        warn "firewalld not installed; skipping firewall changes"
        return 0
    fi
    if ! systemctl is-active --quiet firewalld; then
        warn "firewalld not running; skipping firewall changes"
        return 0
    fi

    local svc
    for svc in http https; do
        if firewall-cmd --permanent --query-service="$svc" >/dev/null 2>&1; then
            log "firewalld: $svc already allowed"
        else
            log "firewalld: allowing $svc"
            firewall-cmd --permanent --add-service="$svc" >/dev/null
        fi
    done
    firewall-cmd --reload >/dev/null
}

step_selinux_webroot() {
    # Make sure the default webroot has the right SELinux context.
    # The default install ships correct contexts, so this is mostly a guard
    # for when WEBROOT is overridden.
    if command -v semanage >/dev/null 2>&1 && [[ "$WEBROOT" != "/usr/share/nginx/html" ]]; then
        if ! semanage fcontext -l | grep -q "${WEBROOT}(/.*)?"; then
            log "adding SELinux fcontext for $WEBROOT"
            semanage fcontext -a -t httpd_sys_content_t "${WEBROOT}(/.*)?"
        fi
        restorecon -Rv "$WEBROOT" >/dev/null || true
    fi
}

step_drop_index() {
    if [[ ! -d "$WEBROOT" ]]; then
        install -d -m 0755 "$WEBROOT"
    fi
    local index="${WEBROOT}/index.html"
    if [[ ! -f "$index" || ! -s "$index" ]] \
       || grep -q 'nginx default' "$index" 2>/dev/null \
       || grep -q '<title>Test Page' "$index" 2>/dev/null; then
        log "writing placeholder index at $index"
        cat >"$index" <<HTML
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>It works</title></head>
<body style="font-family: sans-serif; max-width: 40em; margin: 4em auto;">
  <h1>Nginx is up</h1>
  <p>Provisioned by rocky-bootstrap on $(hostname).</p>
</body>
</html>
HTML
    else
        log "index.html already customised; leaving it alone"
    fi
}

step_enable_nginx() {
    svc_enable nginx
}

main() {
    require_root
    log "===== install-web.sh starting ====="
    step_install_nginx
    step_drop_index
    step_selinux_webroot
    step_open_firewall
    step_enable_nginx
    log "===== install-web.sh complete ====="
}

main "$@"
