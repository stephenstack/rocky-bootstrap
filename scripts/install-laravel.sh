#!/usr/bin/env bash
# scripts/install-laravel.sh — Laravel toolchain only.
#
# Installs the things you need to *develop or scaffold* Laravel apps on this
# host. Does NOT configure a web server, php-fpm pool, or app directory —
# bring your own deployment shape (Apache + mod_php, nginx + php-fpm, lamp
# role, Docker, etc).
#
# Steps:
#   1. enable the PHP 8.3 module stream
#   2. install PHP CLI + the extensions Laravel needs
#   3. install Composer to /usr/local/bin/composer
#   4. install the Laravel installer globally (composer require laravel/installer)
#
# Idempotent: re-running just verifies state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="laravel"

PHP_STREAM="${PHP_STREAM:-php:8.3}"

# Where Composer drops `global` packages — the laravel installer ends up at
# ${COMPOSER_HOME}/vendor/bin/laravel.
COMPOSER_HOME="${COMPOSER_HOME:-${HOME:-/root}/.config/composer}"

# ---------------------------------------------------------------------------
step_enable_php_module() {
    if dnf module list --enabled php 2>/dev/null | grep -q "^php\s*${PHP_STREAM#php:}"; then
        log "php module stream already enabled: $PHP_STREAM"
    else
        log "enabling php module stream: $PHP_STREAM"
        dnf -y module reset php
        dnf -y module enable "$PHP_STREAM"
    fi
}

# ---------------------------------------------------------------------------
step_install_php() {
    # CLI + the extensions Laravel's docs call out as required/recommended.
    # No php-fpm — that's a deployment concern, not a toolchain one.
    dnf_install \
        php php-cli php-common \
        php-mysqlnd php-pgsql \
        php-mbstring php-xml php-bcmath php-intl \
        php-gd php-zip php-opcache php-pdo \
        php-curl php-sodium
}

# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
step_install_laravel_installer() {
    # Allow root to run composer global require — required when bootstrapping
    # a fresh box as root without a dedicated dev user yet.
    export COMPOSER_ALLOW_SUPERUSER=1
    export COMPOSER_HOME

    local laravel_bin="${COMPOSER_HOME}/vendor/bin/laravel"
    if [[ -x "$laravel_bin" ]]; then
        log "laravel installer already present: $($laravel_bin --version 2>/dev/null | head -n1)"
        return 0
    fi

    log "installing laravel installer (composer global require laravel/installer)"
    composer global require laravel/installer

    log "laravel installer at: $laravel_bin"
    log "ensure ${COMPOSER_HOME}/vendor/bin is on \$PATH (the bashrc role handles this)"
}

# ---------------------------------------------------------------------------
main() {
    require_root
    log "===== install-laravel.sh starting ====="
    step_enable_php_module
    step_install_php
    step_install_composer
    step_install_laravel_installer
    log "===== install-laravel.sh complete ====="
    log "Scaffold a new app with: laravel new <project>   (or: composer create-project laravel/laravel <project>)"
}

main "$@"
