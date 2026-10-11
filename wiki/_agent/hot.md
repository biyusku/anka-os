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
- Görünüm (`modules/branding`, ayrıntı `docs/branding.md`): Mac sadeliğinde baştan sona —
  gizli açılış menüsü (Windows varsa 5 sn), Plymouth `anka` (logo + ince çubuk), aynı
  ksplash, Inter, ANKA renk şeması (grafit + kırmızı, `colors.nix`), üst çubuk + yüzen dock
  (LnF layout JS), sağda pencere düğmeleri, canlı USB için GRUB/syslinux teması.
- `pkgs/anka-ui`: karşılama (kdialog yerine tek pencere, çıkış kodu 10/11 = AI aç/kapa) ve
  KRunner AI yanıt penceresi (stdin'den yanıt). ANKA Updates KCM sadeleştirildi.
- Ekran görüntüsü testi: QML'ler offscreen Qt ile render edilip incelendi (kalıcı test yok).

- Performans: earlyoom hiç çalışmıyordu (argüman hatası) → düzeltildi; zram swappiness 180;
  governor "auto"; olmayan sysctl'ler ve her zaman açık 64-quantum PipeWire kaldırıldı.
- İsteğe bağlı özellikler tek tek açılıp değerlendirildi: erişilebilirlik, USBGuard, SSH,
  fail2ban açıldığında sistem derlenmiyordu → düzeltildi. Test: extendModules ile
  `anka.<seçenek> = …` ekleyip toplevel.drvPath değerlendir.

- `checks.option-matrix`: 18 seçenek kombinasyonu (`nix flake check` ile) değerlendirilir;
  yeni isteğe bağlı özellik eklerken buraya bir varyant ekle.
- README yeniden yazıldı. Repoda LICENSE dosyası yok (karar kullanıcıda).

## Sıradaki işler

- AI: daemon + KRunner + yanıt penceresi çalışıyor; intent/router/memory/voice/confirmation_gate
  hâlâ bağlı değil.
- SteamOS özellikleri: Jovian-NixOS (Oyun Modu). (scx_lavd ve NTSYNC tamam.)
- ISO'yu gerçek donanımda / QEMU'da uçtan uca test et.
