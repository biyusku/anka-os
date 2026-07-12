#!/usr/bin/env bash
# ANKA OS — System rebuild / update helper
# Called by systemd services; do not run directly as a regular user.
#
# Usage: anka-rebuild.sh <check|apply|rollback>
#
# Environment (set by systemd unit):
#   ANKA_FLAKE_PATH   – path to the checked-out ANKA flake  (default: /etc/anka)
#   ANKA_AUTO_APPLY   – "true" to apply without prompting    (default: false)
#   ANKA_NOTIFY       – "true" to send KDE notifications     (default: true)

set -euo pipefail

FLAKE_PATH="${ANKA_FLAKE_PATH:-/etc/anka}"
AUTO_APPLY="${ANKA_AUTO_APPLY:-false}"
NOTIFY="${ANKA_NOTIFY:-true}"
NOTIFIER="${FLAKE_PATH}/scripts/kde-notifier.py"
VERSION_FILE="${FLAKE_PATH}/VERSION"
LOG_DIR="/var/log/anka"
LOG_FILE="${LOG_DIR}/update.log"

mkdir -p "$LOG_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

notify() {
    local action="$1" data="$2"
    if [[ "$NOTIFY" == "true" ]] && [[ -x "$NOTIFIER" ]]; then
        python3 "$NOTIFIER" "$action" "$data" 2>>"$LOG_FILE" || true
    fi
}

current_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        echo "unknown"
    fi
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_check() {
    log "Checking for ANKA updates (flake: ${FLAKE_PATH})"

    # Get revision of the local lock file (what is currently deployed)
    local local_rev
    local_rev=$(nix flake metadata "$FLAKE_PATH" \
        --no-update-lock-file --json 2>>"$LOG_FILE" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('revision','')[:12])" \
        2>/dev/null || echo "")

    # Get revision of the upstream (fetch latest lock)
    local remote_rev
    remote_rev=$(nix flake metadata "$FLAKE_PATH" \
        --json 2>>"$LOG_FILE" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('revision','')[:12])" \
        2>/dev/null || echo "")

    local current
    current=$(current_version)

    log "Local revision : ${local_rev:-unknown}"
    log "Remote revision: ${remote_rev:-unknown}"
    log "Current version: $current"

    if [[ -n "$remote_rev" ]] && [[ "$remote_rev" != "$local_rev" ]]; then
        log "Update available: $local_rev -> $remote_rev"
        notify "available" "{\"current\": \"$current\", \"available\": \"$remote_rev\"}"

        if [[ "$AUTO_APPLY" == "true" ]]; then
            log "Auto-apply enabled — starting update"
            cmd_apply
        fi
    else
        log "System is up to date (rev: ${local_rev:-unknown})"
    fi
}

cmd_apply() {
    log "Starting ANKA system update..."

    local current
    current=$(current_version)

    if nixos-rebuild switch --flake "${FLAKE_PATH}#anka" 2>&1 | tee -a "$LOG_FILE"; then
        local new_version
        new_version=$(current_version)
        log "Update complete: $current -> $new_version"
        notify "complete" "$new_version"
    else
        local exit_code=$?
        log "Update failed (exit code: $exit_code) — see $LOG_FILE"
        notify "failed" "nixos-rebuild exited with code $exit_code. See $LOG_FILE for details."
        exit "$exit_code"
    fi
}

cmd_rollback() {
    log "Rolling back to previous ANKA generation..."

    if nixos-rebuild switch --rollback 2>&1 | tee -a "$LOG_FILE"; then
        local version
        version=$(current_version)
        log "Rollback complete — now on: $version"
        notify "complete" "rollback-to-$version"
    else
        local exit_code=$?
        log "Rollback failed (exit code: $exit_code)"
        notify "failed" "Rollback exited with code $exit_code. See $LOG_FILE."
        exit "$exit_code"
    fi
}

# ── Entrypoint ────────────────────────────────────────────────────────────────

ACTION="${1:-check}"

case "$ACTION" in
    check)    cmd_check    ;;
    apply)    cmd_apply    ;;
    rollback) cmd_rollback ;;
    *)
        echo "Usage: anka-rebuild.sh <check|apply|rollback>" >&2
        exit 1
        ;;
esac