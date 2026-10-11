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
- Varsayılan kernel Zen (CachyOS her kurulumda kernel + LLVM-22 rustc derletiyordu) +
  scx_lavd; NTSYNC zen'de dahili.
- AI paketi derleniyor ve çalışıyor (uçtan uca D-Bus testi); MCP sunucuları fastmcp 3'e
  uyarlandı ve paketlendi; NVIDIA'dan CUDA toolkit, AMD'den ROCm kaldırıldı; Ollama Vulkan.

## Sıradaki işler

- AI: daemon çalışıyor ama intent/router/memory/voice/confirmation_gate hâlâ bağlı değil;
  bir arayüz (plasmoid / KRunner) yok, sadece `anka-ai` terminal komutu var.
- Sihirbaz (`modules/installer/first-run-wizard.sh`) seçimleri çoğunlukla uygulanmıyor
  (sadece AI_MODE okunuyor).
- "Hafif" profil (7B model, Steam vb. kapalı) ve kurulumda profil seçimi.
- SteamOS özellikleri: Jovian-NixOS (Oyun Modu). (scx_lavd ve NTSYNC tamam.)
- ISO'yu gerçek donanımda / QEMU'da uçtan uca test et.
