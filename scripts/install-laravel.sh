#!/usr/bin/env bash
# scripts/install-laravel.sh — PHP 8.3 + Composer + Nginx site stub.
#
# Sets up a Rocky 9 host as a Laravel application server:
#   - enables the PHP 8.3 module stream
#   - installs PHP and the extensions Laravel needs
#   - installs Composer to /usr/local/bin/composer
#   - configures php-fpm to listen on a unix socket
#   - drops an /etc/nginx/conf.d/laravel.conf site stub pointing at /var/www/laravel/public
#   - creates the app directory owned by the admin user
#
# Does NOT pull or scaffold a Laravel app — you do that yourself with
# `composer create-project` or by cloning your repo into /var/www/laravel.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="laravel"

ADMIN_USER="${ADMIN_USER:-admin}"
APP_DIR="${APP_DIR:-/var/www/laravel}"
APP_DOMAIN="${APP_DOMAIN:-_}"   # nginx server_name; "_" matches anything
PHP_STREAM="${PHP_STREAM:-php:8.3}"

step_enable_php_module() {
    # `dnf module reset` + `enable` is idempotent and safe to re-run.
    if dnf module list --enabled php 2>/dev/null | grep -q "^php\s*${PHP_STREAM#php:}"; then
        log "php module stream already enabled: $PHP_STREAM"
    else
        log "enabling php module stream: $PHP_STREAM"
        dnf -y module reset php
        dnf -y module enable "$PHP_STREAM"
    fi
}

step_install_php() {
    dnf_install php php-fpm php-cli php-common \
                php-mysqlnd php-pgsql \
                php-mbstring php-xml php-bcmath php-intl \
                php-gd php-zip php-opcache php-pdo \
                php-curl php-sodium
}

step_install_composer() {
    local target="/usr/local/bin/composer"
    if [[ -x "$target" ]]; then
        log "composer already installed: $($target --version 2>/dev/null | head -n1)"
        return 0
    fi
    log "installing composer"
    local installer
    installer="$(mktemp)"
    curl -fsSL https://getcomposer.org/installer -o "$installer"
    php "$installer" --install-dir=/usr/local/bin --filename=composer
    rm -f "$installer"
    chmod 0755 "$target"
}

step_configure_php_fpm() {
    # Run php-fpm as the admin user so artisan / queue workers / file writes match.
    local pool="/etc/php-fpm.d/www.conf"
    [[ -f "$pool" ]] || die "missing $pool"

    backup_once "$pool"

    # Use a unix socket (default on Rocky is a TCP listen on 127.0.0.1:9000).
    sed -i \
        -e "s|^user = .*|user = ${ADMIN_USER}|" \
        -e "s|^group = .*|group = ${ADMIN_USER}|" \
        -e "s|^listen = .*|listen = /run/php-fpm/laravel.sock|" \
        -e "s|^;\?listen.owner = .*|listen.owner = nginx|" \
        -e "s|^;\?listen.group = .*|listen.group = nginx|" \
        -e "s|^;\?listen.mode = .*|listen.mode = 0660|" \
        "$pool"

    svc_enable php-fpm
    svc_restart php-fpm
}

step_create_app_dir() {
    if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
        die "admin user '$ADMIN_USER' does not exist; run base.sh first"
    fi

    install -d -m 0755 -o "$ADMIN_USER" -g "$ADMIN_USER" "$APP_DIR"
    install -d -m 0755 -o "$ADMIN_USER" -g "$ADMIN_USER" "${APP_DIR}/public"

    # SELinux: let nginx + php-fpm read/write the app tree.
    if command -v semanage >/dev/null 2>&1; then
        if ! semanage fcontext -l 2>/dev/null | grep -q "${APP_DIR}(/.*)?"; then
            log "adding SELinux fcontext for $APP_DIR"
            semanage fcontext -a -t httpd_sys_rw_content_t "${APP_DIR}(/.*)?" || true
        fi
        restorecon -Rv "$APP_DIR" >/dev/null || true
    fi

    # Stub index so you can verify nginx -> php-fpm wiring before deploying real code.
    local stub="${APP_DIR}/public/index.php"
    if [[ ! -f "$stub" ]]; then
        cat >"$stub" <<'PHP'
<?php
echo "Laravel host ready — replace this with your app.\n";
echo "PHP " . PHP_VERSION . " on " . gethostname() . "\n";
PHP
        chown "$ADMIN_USER:$ADMIN_USER" "$stub"
    fi
}

step_nginx_site() {
    if ! command -v nginx >/dev/null 2>&1; then
        warn "nginx not installed; skipping site config (install nginx manually if you need HTTP)"
        return 0
    fi

    local site="/etc/nginx/conf.d/laravel.conf"
    if [[ -f "$site" ]]; then
        log "nginx site config already exists: $site (leaving it alone)"
        return 0
    fi

    log "writing $site"
    cat >"$site" <<EOF
server {
    listen 80;
    server_name ${APP_DOMAIN};
    root ${APP_DIR}/public;
    index index.php index.html;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php-fpm/laravel.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

    # Disable the stock default to avoid two server_name _ blocks fighting.
    if [[ -f /etc/nginx/conf.d/default.conf ]]; then
        backup_once /etc/nginx/conf.d/default.conf
        mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
    fi

    log "validating nginx config"
    nginx -t
    svc_restart nginx
}

main() {
    require_root
    log "===== install-laravel.sh starting ====="
    step_enable_php_module
    step_install_php
    step_install_composer
    step_configure_php_fpm
    step_create_app_dir
    step_nginx_site
    log "===== install-laravel.sh complete ====="
    log "Next: deploy your app into ${APP_DIR} (composer create-project, git clone, etc.)"
}

main "$@"
