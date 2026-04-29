#!/usr/bin/env bash
# scripts/install-starship.sh — Starship prompt + FiraCode Nerd Font.
#
# - Install fontconfig + unzip + wget if missing
# - Download FiraCode Nerd Font into /usr/local/share/fonts (system-wide)
#   so any user on the box benefits, then refresh fontconfig cache
# - Install Starship via the official installer (unattended -y)
# - Drop the curated starship.toml at $HOME/.config/starship/starship.toml
# - Wire `starship init bash` into ~/.bashrc (idempotent — guarded by markers)
#
# Notes:
#   - Fonts on a server are mostly cosmetic — rendering happens in the
#     terminal of whoever connects. Installing them here is convenient if
#     you also use this box as a workstation.
#   - The starship installer drops the binary into /usr/local/bin/starship.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="starship"

# --- tunables (override via env) ---
NERD_FONT_VERSION="${NERD_FONT_VERSION:-v3.2.1}"
NERD_FONT_NAME="${NERD_FONT_NAME:-FiraCode}"
FONT_INSTALL_DIR="${FONT_INSTALL_DIR:-/usr/local/share/fonts/${NERD_FONT_NAME,,}-nerd}"
STARSHIP_BIN="${STARSHIP_BIN:-/usr/local/bin/starship}"
STARSHIP_CONFIG_DIR="${STARSHIP_CONFIG_DIR:-${HOME:-/root}/.config/starship}"
BASHRC="${BASHRC:-${HOME:-/root}/.bashrc}"

# Markers used to keep the bashrc append idempotent.
BASHRC_MARK_BEGIN="# >>> rocky-bootstrap: starship >>>"
BASHRC_MARK_END="# <<< rocky-bootstrap: starship <<<"

# ---------------------------------------------------------------------------
step_install_dependencies() {
    # fontconfig provides fc-cache. unzip + wget needed for the font fetch.
    dnf_install fontconfig unzip wget curl
}

# ---------------------------------------------------------------------------
step_install_nerd_font() {
    # Idempotent: skip if any FiraCode Nerd Font ttf is already present in
    # the install dir. Use the v3 zip (smaller, no -windows-compat-* dupes).
    if [[ -d "$FONT_INSTALL_DIR" ]] \
       && find "$FONT_INSTALL_DIR" -maxdepth 1 -name '*.ttf' -print -quit | grep -q .; then
        log "${NERD_FONT_NAME} Nerd Font already installed at ${FONT_INSTALL_DIR}"
        return 0
    fi

    log "installing ${NERD_FONT_NAME} Nerd Font ${NERD_FONT_VERSION} into ${FONT_INSTALL_DIR}"
    install -d -m 0755 "$FONT_INSTALL_DIR"

    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN

    local url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/${NERD_FONT_NAME}.zip"
    log "downloading: ${url}"
    curl -fsSL -o "${tmp}/font.zip" "$url"

    log "extracting font archive"
    unzip -q -o "${tmp}/font.zip" -d "$FONT_INSTALL_DIR"

    # Strip Windows-compat dupes if the archive shipped them — keeps the dir tidy.
    find "$FONT_INSTALL_DIR" -name '*Windows Compatible*' -delete 2>/dev/null || true

    log "refreshing fontconfig cache"
    fc-cache -f "$FONT_INSTALL_DIR" >/dev/null 2>&1 || fc-cache -f >/dev/null
}

# ---------------------------------------------------------------------------
step_install_starship() {
    if [[ -x "$STARSHIP_BIN" ]] || command -v starship >/dev/null 2>&1; then
        log "starship already installed: $(starship --version 2>/dev/null | head -n1)"
        return 0
    fi

    log "installing starship via upstream installer (unattended)"
    # -y skips the interactive confirmation; -b forces the install dir.
    curl -fsSL https://starship.rs/install.sh \
        | sh -s -- -y -b /usr/local/bin
    log "starship version: $(starship --version 2>/dev/null | head -n1)"
}

# ---------------------------------------------------------------------------
step_deploy_starship_config() {
    install -d -m 0755 "$STARSHIP_CONFIG_DIR"
    local src="${FILES_DIR}/starship.toml"
    local dst="${STARSHIP_CONFIG_DIR}/starship.toml"
    [[ -f "$src" ]] || die "missing $src"

    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        log "starship.toml already up to date at $dst"
        return 0
    fi

    backup_once "$dst"
    install -m 0644 "$src" "$dst"
    log "deployed starship config to $dst"
}

# ---------------------------------------------------------------------------
step_wire_bashrc() {
    # Append a marked block to ~/.bashrc that initialises starship and exports
    # STARSHIP_CONFIG. Re-runs are safe — we replace the existing block in place
    # if it's already there, so the file never grows on repeated runs.

    [[ -f "$BASHRC" ]] || touch "$BASHRC"

    if grep -qF "$BASHRC_MARK_BEGIN" "$BASHRC"; then
        log "starship block already present in $BASHRC; refreshing in place"
        # Delete the existing block so we can re-append the latest version.
        # Use sed to wipe everything between the markers (inclusive).
        sed -i "\#${BASHRC_MARK_BEGIN}#,\#${BASHRC_MARK_END}#d" "$BASHRC"
    else
        log "appending starship init block to $BASHRC"
    fi

    {
        echo ""
        echo "$BASHRC_MARK_BEGIN"
        echo "# Managed by rocky-bootstrap (scripts/install-starship.sh)"
        echo "export STARSHIP_CONFIG=\"\$HOME/.config/starship/starship.toml\""
        echo 'if command -v starship >/dev/null 2>&1; then'
        echo '    eval "$(starship init bash)"'
        echo 'fi'
        echo "$BASHRC_MARK_END"
    } >>"$BASHRC"
}

# ---------------------------------------------------------------------------
main() {
    require_root
    log "===== install-starship.sh starting ====="
    step_install_dependencies
    step_install_nerd_font
    step_install_starship
    step_deploy_starship_config
    step_wire_bashrc

    # Source ~/.bashrc so the rest of this run sees STARSHIP_CONFIG / PATH
    # changes. Note: this only affects THIS script's process — the user's
    # interactive shell still has to source it themselves (or open a new shell).
    # Guard with `|| true` because a strict-mode bashrc could trip set -e.
    if [[ -f "$BASHRC" ]]; then
        log "sourcing $BASHRC (effect limited to this script's shell)"
        # shellcheck disable=SC1090
        source "$BASHRC" || warn "source $BASHRC returned non-zero (continuing)"
    fi

    log "===== install-starship.sh complete ====="
    log "Open a new shell (or 'source ~/.bashrc') in YOUR terminal to see the prompt."
    log "Set your terminal font to '${NERD_FONT_NAME} Nerd Font' to render glyphs correctly."
}

main "$@"
