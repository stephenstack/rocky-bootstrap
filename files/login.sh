#!/bin/bash
# /etc/profile.d/login.sh — managed by rocky-bootstrap (scripts/install-motd.sh).
#
# Runs on every interactive login. Renders an ASCII banner from the current
# hostname (figlet, falls back to plain text) and then a conditional service
# summary — each line only shows up if the corresponding command/unit exists.

# Bail out for non-interactive shells (cron, scp, ansible, etc.) — they don't
# want a banner shoved into stdout.
case $- in
    *i*) ;;
    *)   return 0 ;;
esac

# --- colors ---
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
RESET="\033[0m"

# --- helpers ---
_svc_status() {
    # Echo "running" / "stopped" with colour. Silent if systemctl is missing.
    local unit="$1"
    if command -v systemctl >/dev/null 2>&1 \
       && systemctl is-active --quiet "$unit" 2>/dev/null; then
        printf "%brunning%b" "$GREEN" "$RESET"
    else
        printf "%bstopped%b" "$RED" "$RESET"
    fi
}

_row() {
    # Print "Label: value" with consistent label padding.
    printf "${BLUE}%-9s${RESET} %b\n" "$1" "$2"
}

# --- banner ---
clear

HOST="$(hostname -s 2>/dev/null || hostname)"

printf "%b" "$CYAN"
if command -v figlet >/dev/null 2>&1; then
    figlet -f standard "$HOST" 2>/dev/null || printf "  %s\n" "$HOST"
else
    printf "  %s\n" "$HOST"
fi
printf "%b\n" "$RESET"

OS_PRETTY="Rocky Linux"
if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    OS_PRETTY="$(. /etc/os-release; echo "${PRETTY_NAME:-Rocky Linux}")"
fi

printf "%bWelcome to %b%s%b %b— %s%b\n" \
    "$YELLOW" "$GREEN" "${HOST^^}" "$RESET" "$WHITE" "$OS_PRETTY" "$RESET"
echo "--------------------------------------------------"

# --- system info ---
_row "Hostname:" "$(hostname)"
_row "Uptime:"   "$(uptime -p 2>/dev/null || echo 'n/a')"
_row "Load:"     "$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ //')"
_row "CPU:"      "$(lscpu 2>/dev/null | awk -F': +' '/Model name/{print $2; exit}')"
_row "Memory:"   "$(free -h 2>/dev/null | awk '/Mem:/ {print $3 "/" $2}')"
_row "Disk:"     "$(df -h / 2>/dev/null | awk 'NR==2{print $3 "/" $2 " (" $5 " used)"}')"
_row "Kernel:"   "$(uname -r)"

# --- conditional service info ---
# Only render lines for things that are actually installed on this host.

if command -v nginx >/dev/null 2>&1; then
    NGINX_VER="$(nginx -v 2>&1 | awk -F'/' '{print $2}')"
    _row "Nginx:" "$NGINX_VER — $(_svc_status nginx)"
fi

if command -v httpd >/dev/null 2>&1; then
    APACHE_VER="$(httpd -v 2>/dev/null | awk '/Server version/{print $3}')"
    _row "Apache:" "$APACHE_VER — $(_svc_status httpd)"
fi

if command -v php >/dev/null 2>&1; then
    PHP_VER="$(php -r 'echo PHP_VERSION;' 2>/dev/null)"
    _row "PHP:" "$PHP_VER"
fi

if command -v php-fpm >/dev/null 2>&1; then
    _row "php-fpm:" "$(_svc_status php-fpm)"
fi

if command -v docker >/dev/null 2>&1; then
    DOCKER_VER="$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
    _row "Docker:" "$DOCKER_VER — $(_svc_status docker)"
fi

if command -v mariadb >/dev/null 2>&1; then
    DB_VER="$(mariadb --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
    _row "MariaDB:" "${DB_VER:-installed} — $(_svc_status mariadb)"
fi

if command -v redis-cli >/dev/null 2>&1; then
    REDIS_VER="$(redis-cli --version 2>/dev/null | awk '{print $2}')"
    _row "Redis:" "$REDIS_VER — $(_svc_status redis)"
fi

if command -v alloy >/dev/null 2>&1; then
    _row "Alloy:" "$(_svc_status alloy)"
fi

if command -v supervisord >/dev/null 2>&1; then
    _row "Supervd:" "$(_svc_status supervisord)"
fi

echo "--------------------------------------------------"

# Switch to /var/www/html if it exists — convenient default for web hosts.
if [[ -d /var/www/html ]]; then
    cd /var/www/html || true
    printf "${CYAN}Working directory:${RESET} %s\n" "$(pwd)"
fi

# Hint depends on what's installed.
if command -v nginx >/dev/null 2>&1; then
    printf "${CYAN}Tip:${RESET} 'systemctl status nginx' to check the web server.\n"
elif command -v httpd >/dev/null 2>&1; then
    printf "${CYAN}Tip:${RESET} 'systemctl status httpd' to check Apache.\n"
fi

# Drop the helper functions out of the user's shell so they don't pollute
# the namespace after login.
unset -f _svc_status _row

echo
