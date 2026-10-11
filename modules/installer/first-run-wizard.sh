# ANKA OS — first-login welcome (runs once per user)
#
# Language, keyboard, user and disk are chosen in the installer; this only
# welcomes the user, asks whether the AI assistant should be on, and shows
# where things are. Every answer is applied:
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

# Texts follow the language chosen in the installer.
if [[ ${LANG:-} == tr* ]]; then
  TITLE="ANKA OS"
  WELCOME="ANKA OS'e hoş geldin!\n\nBilgisayarın hazır. Birkaç saniye içinde başlıyoruz."
  AI_QUESTION="ANKA AI asistanı açılsın mı?\n\nTamamen bilgisayarında çalışır, internete veri göndermez.\nİlk soruda modelini indirir (yaklaşık 5 GB)."
  YES="Evet, aç"
  NO="Hayır"
  DONE="Hepsi bu kadar!\n\n• Uygulamalar: Discover"
  has steam && DONE+="\n• Oyunlar: Steam (Windows oyunları Proton ile çalışır)\n• Oyun Modu: giriş ekranında \"Steam\" oturumunu seç"
  has bottles && DONE+="\n• Windows programları: Bottles"
  DONE+="\n• Güncellemeler: Sistem Ayarları › ANKA Updates"
  has anka-ai && DONE+="\n• AI asistan: Alt+Boşluk, sonra  ai sorun"
else
  TITLE="ANKA OS"
  WELCOME="Welcome to ANKA OS!\n\nYour computer is ready. This takes a few seconds."
  AI_QUESTION="Turn on the ANKA AI assistant?\n\nIt runs entirely on this computer and sends nothing to the internet.\nIt downloads its model on the first question (about 5 GB)."
  YES="Yes, turn it on"
  NO="No"
  DONE="That's it!\n\n• Apps: Discover"
  has steam && DONE+="\n• Games: Steam (Windows games run through Proton)\n• Game Mode: pick the \"Steam\" session on the login screen"
  has bottles && DONE+="\n• Windows programs: Bottles"
  DONE+="\n• Updates: System Settings › ANKA Updates"
  has anka-ai && DONE+="\n• AI assistant: Alt+Space, then  ai your question"
fi

kdialog --title "$TITLE" --msgbox "$WELCOME" || true

if has anka-ai; then
  if kdialog --title "$TITLE" --yes-label "$YES" --no-label "$NO" --yesno "$AI_QUESTION"; then
    set_conf AI_MODE local
  else
    set_conf AI_MODE none
  fi
fi

kdialog --title "$TITLE" --msgbox "$DONE" || true

touch "$SENTINEL"
