# anka-update — check for, apply and roll back ANKA OS updates.
#
# An installed machine's /etc/nixos is a flake with ANKA as its `anka` input
# (written by the installer). Updating ANKA means pointing that input at a
# newer ANKA, locking it and rebuilding:
#
#   stable channel   → the newest vX.Y.Z release tag (main until the first release)
#   unstable channel → the main branch
#
# Usage: anka-update status [--json]   what is installed / available (no root needed)
#        anka-update check             status + desktop notification (+ apply when autoApply)
#        anka-update apply             update to the newest ANKA for the channel
#        anka-update rollback          go back to the ANKA used before the last update
#
# Settings come from /etc/anka/update.conf (written by modules/update).
# Packaged with writeShellApplication (errexit, nounset, pipefail, shellcheck).

CONFIG=${ANKA_UPDATE_CONFIG:-/etc/anka/update.conf}
FLAKE_DIR=/etc/nixos
REPO=biyusku/anka-os
CHANNEL=stable
NOTIFY=true
AUTO_APPLY=false
STATE_DIR=/var/lib/anka-update
VERSION_FILE=/etc/anka/VERSION
# shellcheck source=/dev/null
if [[ -r $CONFIG ]]; then source "$CONFIG"; fi

FLAKE_NIX=$FLAKE_DIR/flake.nix
FLAKE_LOCK=$FLAKE_DIR/flake.lock
BACKUP_DIR=$STATE_DIR/previous
REPO_URL=https://github.com/$REPO
NIX=(nix --extra-experimental-features "nix-command flakes")

die() {
  echo "anka-update: $*" >&2
  exit 1
}

require_root() {
  [[ $EUID -eq 0 ]] || die "run as root (sudo anka-update $1)"
}

require_anka_flake() {
  [[ -f $FLAKE_LOCK ]] || die "$FLAKE_LOCK not found — this machine was not installed with the ANKA installer"
  [[ -n $(current_rev) ]] || die "$FLAKE_LOCK has no locked 'anka' input"
}

# ── What is installed ─────────────────────────────────────────────────────────

current_rev() {
  jq -r '.nodes[.nodes[.root].inputs.anka].locked.rev // empty' "$FLAKE_LOCK"
}

# Human version from the VERSION file of the running ANKA (ANKA_VERSION=x.y.z)
current_version() {
  sed -n 's/^ANKA_VERSION=//p' "$VERSION_FILE" 2>/dev/null | head -n1
}

# ── What is available ────────────────────────────────────────────────────────

# Prints "<name> <commit>" of the newest ANKA for the channel.
latest() {
  local release=""
  if [[ $CHANNEL == stable ]]; then
    # Annotated tags list their commit on the peeled "^{}" line.
    release=$(git ls-remote --tags "$REPO_URL" 'v*' | awk '
      { name = $2; sub("^refs/tags/", "", name)
        if (name ~ /\^\{\}$/) { sub(/\^\{\}$/, "", name); peeled[name] = $1 } else { plain[name] = $1 } }
      END { for (n in plain) if (n ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) print n, (n in peeled ? peeled[n] : plain[n]) }' |
      sort -V | tail -n1)
  fi
  if [[ -n $release ]]; then
    echo "$release"
  else
    echo "main $(git ls-remote "$REPO_URL" refs/heads/main | cut -f1)"
  fi
}

# flake.nix reference for a name printed by latest()
flake_url() {
  if [[ $1 == main ]]; then
    echo "github:$REPO"
  else
    echo "github:$REPO/$1"
  fi
}

# Is <target> newer than <current>? Asks GitHub so a machine that is already
# ahead of the newest release (installed from main) is never downgraded.
is_newer() {
  local current=$1 target=$2 status
  [[ $current != "$target" ]] || return 1
  status=$(curl -fsS --max-time 20 "https://api.github.com/repos/$REPO/compare/$current...$target" |
    jq -r '.status // empty') || status=""
  case $status in
    ahead | diverged) return 0 ;;
    behind | identical) return 1 ;;
    *) return 0 ;; # GitHub unreachable: the commits differ, offer the update
  esac
}

# Sets STATUS_* variables.
compute_status() {
  require_anka_flake
  STATUS_CURRENT_REV=$(current_rev)
  STATUS_CURRENT="$(current_version) (${STATUS_CURRENT_REV:0:7})"
  read -r STATUS_LATEST STATUS_LATEST_REV < <(latest) || true
  [[ -n ${STATUS_LATEST_REV:-} ]] || die "could not reach $REPO_URL"
  if [[ $STATUS_LATEST == main ]]; then
    STATUS_LATEST_LABEL="main (${STATUS_LATEST_REV:0:7})"
  else
    STATUS_LATEST_LABEL=$STATUS_LATEST
  fi
  if is_newer "$STATUS_CURRENT_REV" "$STATUS_LATEST_REV"; then
    STATUS_UPDATE=true
  else
    STATUS_UPDATE=false
  fi
}

status_json() {
  jq -n \
    --arg current "$STATUS_CURRENT" \
    --arg currentRev "$STATUS_CURRENT_REV" \
    --arg latest "$STATUS_LATEST_LABEL" \
    --arg latestRev "$STATUS_LATEST_REV" \
    --arg channel "$CHANNEL" \
    --arg repo "$REPO" \
    --argjson updateAvailable "$STATUS_UPDATE" \
    --arg checkedAt "$(date -Iseconds)" \
    '$ARGS.named'
}

# ── Notifications ─────────────────────────────────────────────────────────────

# Desktop notification for every logged-in user (this usually runs as root
# from a system service, which has no session bus of its own).
notify() {
  [[ $NOTIFY == true ]] || return 0
  local bus uid user
  if [[ $EUID -ne 0 ]]; then
    notify-send --app-name=ANKA --icon=system-software-update "$1" "$2" || true
    return 0
  fi
  for bus in /run/user/*/bus; do
    [[ -S $bus ]] || continue
    uid=$(basename "$(dirname "$bus")")
    user=$(id -nu "$uid" 2>/dev/null) || continue
    runuser -u "$user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
      notify-send --app-name=ANKA --icon=system-software-update "$1" "$2" || true
  done
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_status() {
  compute_status
  if [[ ${1:-} == --json ]]; then
    status_json
    return 0
  fi
  echo "Installed: ANKA $STATUS_CURRENT"
  echo "Channel:   $CHANNEL"
  echo "Newest:    $STATUS_LATEST_LABEL"
  if [[ $STATUS_UPDATE == true ]]; then
    echo "An update is available: sudo anka-update apply"
  else
    echo "ANKA is up to date."
  fi
}

cmd_check() {
  compute_status
  if [[ $EUID -eq 0 ]]; then
    mkdir -p "$STATE_DIR"
    status_json >"$STATE_DIR/status.json"
  fi
  if [[ $STATUS_UPDATE != true ]]; then
    echo "ANKA is up to date."
    return 0
  fi
  echo "Update available: $STATUS_LATEST_LABEL"
  # Notify once per new version, not on every check.
  if [[ $(cat "$STATE_DIR/notified" 2>/dev/null) != "$STATUS_LATEST_REV" ]]; then
    notify "ANKA güncellemesi hazır" "ANKA $STATUS_LATEST_LABEL yüklenebilir. Sistem Ayarları → ANKA Güncellemeleri"
    if [[ $EUID -eq 0 ]]; then echo "$STATUS_LATEST_REV" >"$STATE_DIR/notified"; fi
  fi
  if [[ $AUTO_APPLY == true ]]; then
    cmd_apply
  fi
}

cmd_apply() {
  require_root apply
  compute_status
  if [[ $STATUS_UPDATE != true ]]; then
    echo "ANKA is up to date."
    return 0
  fi
  grep -qE '^[[:space:]]*inputs\.anka\.url[[:space:]]*=' "$FLAKE_NIX" ||
    die "$FLAKE_NIX has no 'inputs.anka.url = \"...\";' line to update"

  local url
  url=$(flake_url "$STATUS_LATEST")
  echo "Updating ANKA to $STATUS_LATEST_LABEL ($url)"
  notify "ANKA güncelleniyor" "ANKA $STATUS_LATEST_LABEL kuruluyor, bilgisayarını kapatma."

  mkdir -p "$BACKUP_DIR"
  cp "$FLAKE_NIX" "$FLAKE_LOCK" "$BACKUP_DIR/"
  sed -i -E "s|^([[:space:]]*inputs\.anka\.url[[:space:]]*=[[:space:]]*)\"[^\"]*\";|\1\"$url\";|" "$FLAKE_NIX"

  if "${NIX[@]}" flake update anka --flake "$FLAKE_DIR" &&
    nixos-rebuild switch --flake "$FLAKE_DIR#anka"; then
    echo "$STATUS_LATEST_REV" >"$STATE_DIR/notified"
    rm -f "$STATE_DIR/status.json"
    echo "ANKA updated to $STATUS_LATEST_LABEL."
    notify "ANKA güncellendi" "ANKA $STATUS_LATEST_LABEL kuruldu."
  else
    cp "$BACKUP_DIR/flake.nix" "$BACKUP_DIR/flake.lock" "$FLAKE_DIR/"
    notify "ANKA güncellemesi başarısız" "Sistem değiştirilmedi. Ayrıntılar: journalctl -u anka-apply-update"
    die "update failed; $FLAKE_DIR restored"
  fi
}

cmd_rollback() {
  require_root rollback
  [[ -f $BACKUP_DIR/flake.lock ]] || die "no earlier ANKA version recorded"
  local undo
  undo=$(mktemp -d)
  cp "$FLAKE_NIX" "$FLAKE_LOCK" "$undo/"
  cp "$BACKUP_DIR/flake.nix" "$BACKUP_DIR/flake.lock" "$FLAKE_DIR/"
  echo "Rolling back ANKA to $(jq -r '.nodes[.nodes[.root].inputs.anka].locked.rev[0:7]' "$FLAKE_LOCK")"
  if nixos-rebuild switch --flake "$FLAKE_DIR#anka"; then
    rm -rf "$BACKUP_DIR" "$undo"
    rm -f "$STATE_DIR/status.json"
    notify "ANKA geri alındı" "Önceki ANKA sürümüne dönüldü."
  else
    cp "$undo/flake.nix" "$undo/flake.lock" "$FLAKE_DIR/"
    rm -rf "$undo"
    die "rollback failed; pick an older entry in the boot menu instead"
  fi
}

case ${1:-status} in
  status) cmd_status "${2:-}" ;;
  check) cmd_check ;;
  apply) cmd_apply ;;
  rollback) cmd_rollback ;;
  *)
    echo "Usage: anka-update {status [--json]|check|apply|rollback}" >&2
    exit 2
    ;;
esac
