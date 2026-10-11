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

- Hafif profil + kurulumda "ANKA / ANKA Hafif" seçimi; ilk açılış sihirbazı sadeleşti
  (karşılama + AI aç/kapa + ipuçları, iki kez açılma hatası giderildi).
- GE-Proton artık nixpkgs proton-ge-bin (aktivasyonda curl + `exit 0` kaldırıldı);
  Flathub ağ hazır olunca servisle ekleniyor; SDL_VIDEODRIVER=wayland,x11.
- Tam sistem derlemesi (AMD, sanal makine): gerçek derleme hatası yok; sadece
  sandbox proxy'sinin engellediği indirmeler (Steam, Discord, firmware) başarısız.

- Oyun Modu: giriş ekranında "Steam" oturumu (gamescope); `gameMode.default` ile konsol gibi açılış.
- Görünüm (`modules/branding`): ANKA duvar kâğıdı (artwork/gen_wallpaper.py), logo,
  "ANKA OS" adı + Plymouth logosu, Breeze Dark + kırmızı vurgu, SDDM/kilit ekranı arka planı.

- Performans: earlyoom hiç çalışmıyordu (argüman hatası) → düzeltildi; zram swappiness 180;
  governor "auto"; olmayan sysctl'ler ve her zaman açık 64-quantum PipeWire kaldırıldı.
- İsteğe bağlı özellikler tek tek açılıp değerlendirildi: erişilebilirlik, USBGuard, SSH,
  fail2ban açıldığında sistem derlenmiyordu → düzeltildi. Test: extendModules ile
  `anka.<seçenek> = …` ekleyip toplevel.drvPath değerlendir.

## Sıradaki işler

- AI: daemon çalışıyor ama intent/router/memory/voice/confirmation_gate hâlâ bağlı değil;
  bir arayüz (plasmoid / KRunner) yok, sadece `anka-ai` terminal komutu var.
- SteamOS özellikleri: Jovian-NixOS (Oyun Modu). (scx_lavd ve NTSYNC tamam.)
- ISO'yu gerçek donanımda / QEMU'da uçtan uca test et.
