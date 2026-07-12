#!/usr/bin/env bash
set -euo pipefail

FLAKE_PATH="${ANKA_FLAKE_PATH:-/etc/anka}"
AUTO_APPLY="${ANKA_AUTO_APPLY:-false}"
NOTIFY="${ANKA_NOTIFY:-true}"

notify() {
    if [[ "$NOTIFY" == "true" ]] && command -v notify-send &>/dev/null; then
        notify-send --app-name="ANKA Updates" --icon=system-software-update "$1" "$2" || true
    fi
}

cmd="${1:-check}"

case "$cmd" in
    check)
        echo "Checking for ANKA OS updates..."
        latest=$(curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/biyusku/anka-os/releases/latest" \
            | grep '"tag_name"' | sed 's/.*"v\?\([^"]*\)".*/\1/')

        current=""
        if [[ -f /etc/anka/VERSION ]]; then
            current=$(cat /etc/anka/VERSION | tr -d '[:space:]')
        fi

        if [[ -z "$latest" ]]; then
            echo "Could not fetch latest release."
            exit 0
        fi

        if [[ "$latest" == "$current" ]]; then
            echo "System is up to date ($current)."
            exit 0
        fi

        echo "Update available: $current -> $latest"
        notify "ANKA Update Available" "Version $latest is ready to install."

        if [[ "$AUTO_APPLY" == "true" ]]; then
            exec "$0" apply
        fi
        ;;

    apply)
        echo "Applying ANKA OS update..."
        notify "ANKA Update" "Starting system update, please wait..."

        nixos-rebuild switch \
            --flake "${FLAKE_PATH}#anka" \
            --option accept-flake-config true \
            2>&1

        new_version=""
        if [[ -f /etc/anka/VERSION ]]; then
            new_version=$(cat /etc/anka/VERSION | tr -d '[:space:]')
        fi

        echo "Update complete. Version: ${new_version:-unknown}"
        notify "ANKA Update Complete" "System updated to version ${new_version:-unknown}."
        ;;

    rollback)
        echo "Rolling back to previous NixOS generation..."
        notify "ANKA Rollback" "Rolling back system, please wait..."

        nixos-rebuild switch --rollback 2>&1

        echo "Rollback complete."
        notify "ANKA Rollback Complete" "System rolled back successfully."
        ;;

    *)
        echo "Usage: $0 {check|apply|rollback}" >&2
        exit 1
        ;;
esac