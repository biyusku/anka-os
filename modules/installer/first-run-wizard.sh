# ANKA OS — first-login welcome (runs once per user)
#
# Language, keyboard, user and disk are chosen in the installer; this only
# welcomes the user in one window (anka-ui welcome, pkgs/anka-ui), asks
# whether the AI assistant should be on and shows where things are.
# The answer is applied:
#   AI_MODE=local|none in ~/.config/anka/setup.conf is read by anka-ai.
#
# Packaged with writeShellApplication (errexit, nounset, pipefail, shellcheck).

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/anka"
SETUP_CONF="$CONFIG_DIR/setup.conf"
SENTINEL="$CONFIG_DIR/setup-done"

# Already welcomed (also honour the sentinel of earlier ANKA versions).
if [[ -e $SENTINEL || -e $HOME/.anka-setup-done ]]; then
  exit 0
fi
mkdir -p "$CONFIG_DIR"

# Set KEY=VALUE in setup.conf, replacing an earlier value.
set_conf() {
  touch "$SETUP_CONF"
  sed -i "/^$1=/d" "$SETUP_CONF"
  echo "$1=$2" >>"$SETUP_CONF"
}

# Only mention what this installation has (the light profile has no AI or Bottles).
has() { command -v "$1" >/dev/null; }
args=()
has anka-ai && args+=(--ai)
has steam && args+=(--steam)
has bottles && args+=(--bottles)

status=0
anka-ui welcome "${args[@]}" || status=$?

case $status in
  10) set_conf AI_MODE local ;;
  11) set_conf AI_MODE none ;;
  0) ;;
  *) exit "$status" ;;  # the window didn't open: try again next login
esac

touch "$SENTINEL"
