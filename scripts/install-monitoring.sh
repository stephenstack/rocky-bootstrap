#!/usr/bin/env bash
# scripts/install-monitoring.sh — Grafana Alloy agent (placeholder).
#
# Adds the Grafana RPM repo, installs `alloy`, and writes a starter config
# at /etc/alloy/config.alloy that scrapes the local node_exporter.
#
# This is intentionally a starter — edit the config to point at your real
# Prometheus / Loki / Tempo endpoints before considering it production-ready.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="monitoring"

GRAFANA_REPO_FILE="/etc/yum.repos.d/grafana.repo"

# Edit these to match your stack before running anywhere real.
PROMETHEUS_REMOTE_WRITE_URL="${PROMETHEUS_REMOTE_WRITE_URL:-http://prometheus.example.internal:9090/api/v1/write}"
LOKI_PUSH_URL="${LOKI_PUSH_URL:-http://loki.example.internal:3100/loki/api/v1/push}"

step_add_grafana_repo() {
    if [[ -f "$GRAFANA_REPO_FILE" ]]; then
        log "grafana repo already configured"
        return 0
    fi
    log "adding grafana RPM repo"
    cat >"$GRAFANA_REPO_FILE" <<'REPO'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
REPO
    rpm --import https://rpm.grafana.com/gpg.key 2>/dev/null || true
}

step_install_alloy() {
    dnf_install alloy
}

step_write_config() {
    local cfg="/etc/alloy/config.alloy"
    install -d -m 0755 /etc/alloy
    if [[ -f "$cfg" ]]; then
        log "alloy config already exists; leaving it alone (delete to regenerate)"
        return 0
    fi

    log "writing starter alloy config to $cfg"
    cat >"$cfg" <<EOF
// Starter Alloy config written by rocky-bootstrap.
// Edit endpoints + auth before relying on this in production.

logging {
  level  = "info"
  format = "logfmt"
}

// --- Host metrics ---------------------------------------------------------
prometheus.exporter.unix "host" { }

prometheus.scrape "host" {
  targets    = prometheus.exporter.unix.host.targets
  forward_to = [prometheus.remote_write.default.receiver]
}

prometheus.remote_write "default" {
  endpoint {
    url = "${PROMETHEUS_REMOTE_WRITE_URL}"
    // basic_auth { username = ""; password = "" }  // uncomment + fill in
  }
}

// --- Journald logs --------------------------------------------------------
loki.source.journal "system" {
  forward_to    = [loki.write.default.receiver]
  relabel_rules = loki.relabel.system.rules
  labels        = { job = "systemd-journal", host = constants.hostname }
}

loki.relabel "system" {
  forward_to = []
  rule {
    source_labels = ["__journal__systemd_unit"]
    target_label  = "unit"
  }
}

loki.write "default" {
  endpoint {
    url = "${LOKI_PUSH_URL}"
  }
}
EOF
}

step_enable_alloy() {
    svc_enable alloy
}

main() {
    require_root
    log "===== install-monitoring.sh starting ====="
    step_add_grafana_repo
    step_install_alloy
    step_write_config
    step_enable_alloy
    warn "Alloy is running with PLACEHOLDER endpoints."
    warn "Edit /etc/alloy/config.alloy and run: systemctl restart alloy"
    log "===== install-monitoring.sh complete ====="
}

main "$@"
