# ANKA OS — Agent Hot State

Son güncelleme: 2026-10-11

## Nerede kaldık

- Tüm flake çıktıları güncel nixos-unstable ile değerlendiriliyor; `flake.lock` eklendi.
- ANKA artık `nixosModules.default` + `lib.mkSystem` olarak dışa aktarılıyor;
  varsayılanlar `profiles/default.nix` içinde (`lib.mkDefault`).
- Kurulum programı yeniden yazıldı: `iso/calamares/` + `ankainstall` job'u,
  `/etc/nixos`'u ANKA flake'i olarak kurar (bkz. `docs/installer.md`).
- `hardware.enableAllFirmware` açıldı (AMD GPU, Wi-Fi, mikrokod).
- Güncelleme sistemi yeniden yazıldı: `anka-update` (status/check/apply/rollback),
  stable = en yeni vX.Y.Z etiketi, unstable = main. KCM derlenmiyordu (ECM sürümü,
  QML `ui/` konumu) — düzeltildi; `nix flake check` artık KCM ve anka-update'i derliyor.
- Repo herkese açık (biyusku/anka-os).

## Sıradaki işler

- AI daemon: `services/anka-ai/anka-ai/daemon.py` `/var/log/anka`'ya yazmaya çalışırken çöküyor;
  intent/router/MCP parçaları birbirine bağlı değil.
- "Hafif" profil (7B model, Steam vb. kapalı) ve kurulumda profil seçimi.
- SteamOS özellikleri: Jovian-NixOS (Oyun Modu), scx_lavd, NTSYNC.
- ISO'yu gerçek donanımda / QEMU'da uçtan uca test et.
