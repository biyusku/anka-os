# ANKA OS — Agent Hot State

Son güncelleme: 2026-10-11

## Nerede kaldık

- Tüm flake çıktıları güncel nixos-unstable ile değerlendiriliyor; `flake.lock` eklendi.
- ANKA artık `nixosModules.default` + `lib.mkSystem` olarak dışa aktarılıyor;
  varsayılanlar `profiles/default.nix` içinde (`lib.mkDefault`).
- Kurulum programı yeniden yazıldı: `iso/calamares/` + `ankainstall` job'u,
  `/etc/nixos`'u ANKA flake'i olarak kurar (bkz. `docs/installer.md`).
- `hardware.enableAllFirmware` açıldı (AMD GPU, Wi-Fi, mikrokod).

## Sıradaki işler

- Güncelleme sistemi: `modules/update/` hâlâ `/etc/anka`'yı flake sanıyor;
  `/etc/nixos` + `nix flake update anka` akışına geçmeli. VERSION karşılaştırması bozuk.
- AI daemon: `services/anka-ai/anka-ai/daemon.py` `/var/log/anka`'ya yazmaya çalışırken çöküyor;
  intent/router/MCP parçaları birbirine bağlı değil.
- "Hafif" profil (7B model, Steam vb. kapalı) ve kurulumda profil seçimi.
- SteamOS özellikleri: Jovian-NixOS (Oyun Modu), scx_lavd, NTSYNC.
- ISO'yu gerçek donanımda / QEMU'da uçtan uca test et.
