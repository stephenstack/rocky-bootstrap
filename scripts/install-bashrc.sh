#!/usr/bin/env bash
# scripts/install-bashrc.sh — deploy curated ~/.bashrc.
#
# Drops files/bashrc to $HOME/.bashrc.
#
# Idempotent:
#   - Diffs first; only writes when content differs
#   - backup_once preserves the original ~/.bashrc as ~/.bashrc.bootstrap-bak
#   - Preserves the starship marked block (managed by install-starship.sh)
#     across re-runs, so it doesn't matter what order the two roles ran in
#
# Recommended order in bootstrap.sh: bashrc BEFORE starship — that way the
# starship block lives at the END of ~/.bashrc rather than getting embedded
# mid-file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

BOOTSTRAP_TAG="bashrc"

BASHRC_TARGET="${BASHRC_TARGET:-${HOME:-/root}/.bashrc}"

# Markers used by install-starship.sh — keep in sync with that script.
STARSHIP_MARK_BEGIN="# >>> rocky-bootstrap: starship >>>"
STARSHIP_MARK_END="# <<< rocky-bootstrap: starship <<<"

# Extract a previously-installed starship marked block, if any, into $1.
# Writes an empty file if no block is found.
extract_starship_block() {
    local out="$1"
    if [[ -f "$BASHRC_TARGET" ]] && grep -qF "$STARSHIP_MARK_BEGIN" "$BASHRC_TARGET"; then
        log "preserving existing starship block from $BASHRC_TARGET"
        sed -n "\#${STARSHIP_MARK_BEGIN}#,\#${STARSHIP_MARK_END}#p" "$BASHRC_TARGET" >"$out"
    else
        : >"$out"
    fi
}

step_deploy_bashrc() {
    local src="${FILES_DIR}/bashrc"
    [[ -f "$src" ]] || die "missing $src"

    local saved tmp
    saved="$(mktemp)"
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$saved' '$tmp'" RETURN

    extract_starship_block "$saved"

    # Compose: template body, then preserved starship block (if any).
    cat "$src" >"$tmp"
    if [[ -s "$saved" ]]; then
        printf "\n" >>"$tmp"
        cat "$saved" >>"$tmp"
    fi

    if [[ -f "$BASHRC_TARGET" ]] && cmp -s "$tmp" "$BASHRC_TARGET"; then
        log "bashrc already up to date at $BASHRC_TARGET"
        return 0
    fi

    backup_once "$BASHRC_TARGET"
    install -m 0644 "$tmp" "$BASHRC_TARGET"

    # If we're deploying for a non-root user (BASHRC_TARGET overridden), make
    # sure they own the result.
    local target_owner
    target_owner="$(stat -c '%U:%G' "$(dirname "$BASHRC_TARGET")" 2>/dev/null || echo 'root:root')"
    if [[ "$target_owner" != "root:root" ]]; then
        chown "$target_owner" "$BASHRC_TARGET"
    fi

    log "deployed bashrc to $BASHRC_TARGET (starship block preserved if it existed)"
}

main() {
    require_root
    log "===== install-bashrc.sh starting ====="
    step_deploy_bashrc
    log "===== install-bashrc.sh complete ====="
    log "Open a new shell or 'source ~/.bashrc' in YOUR terminal to apply."
}

main "$@"
