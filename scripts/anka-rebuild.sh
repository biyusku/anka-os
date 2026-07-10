#!/usr/bin/env bash
set -euo pipefail

# ANKA OS Rebuild Helper
# nixos-rebuild switch'i kolaylaştırır

ACTION="${1:-switch}"
HOST="${2:-default}"

echo "==> ANKA OS Rebuild"
echo "    Host: $HOST"
echo "    Action: $ACTION"

case "$ACTION" in
  switch)
    sudo nixos-rebuild switch --flake ".#$HOST" --show-trace
    echo "==> Sistem güncellendi!"
    ;;
  boot)
    sudo nixos-rebuild boot --flake ".#$HOST"
    echo "==> Sonraki açılışta uygulanacak."
    ;;
  test)
    sudo nixos-rebuild test --flake ".#$HOST"
    echo "==> Test build hazır (kalıcı değil)."
    ;;
  build)
    nixos-rebuild build --flake ".#$HOST"
    echo "==> Build tamamlandı."
    ;;
  rollback)
    sudo nixos-rebuild switch --rollback
    echo "==> Önceki nesile dönüldü."
    ;;
  *)
    echo "Kullanım: anka-rebuild [switch|boot|test|build|rollback] [host]"
    exit 1
    ;;
esac