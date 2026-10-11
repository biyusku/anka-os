# ANKA OS — Proje Genel Bakış

## Nedir?

ANKA OS, NixOS tabanlı, herkese açık bir masaüstü işletim sistemidir.
Hedef: Eski/düşük özellikli donanımlara Windows uyumluluğu, Mac estetiği ve Linux performansı sunmak.
Slogan: _"Eski bir laptop, yeni bir hayat."_

**İsim:** Türk mitolojisindeki Zümrüdüanka'dan (phoenix) — eski donanımı yeniden doğuran OS metaforu.

---

## Mimari Özet

```
flake.nix
├── nixosModules.default              → ANKA: modules/ + profiles/default.nix + chaotic/home-manager/disko
├── lib.mkSystem { modules = [...]; } → ANKA sistemi kurar (kurulan makinelerin /etc/nixos flake'i bunu kullanır)
├── nixosConfigurations.anka          → Referans makine (hosts/default, CI değerlendirir)
├── nixosConfigurations.anka-iso      → AMD ISO
├── nixosConfigurations.anka-iso-nvidia → NVIDIA ISO
├── nixosConfigurations.anka-iso-intel  → Intel ISO
└── packages.x86_64-linux.{iso, iso-amd, iso-nvidia, iso-intel}
```

- `modules/default.nix` — tüm ANKA modüllerini içe aktarır
- `profiles/default.nix` — ANKA'nın varsayılan ayarları (hepsi `lib.mkDefault`)
- `flake.lock` — tüm girdiler sabitlenmiştir; güncelleme `nix flake update` ile yapılır
- Kurulum programı: `iso/calamares/` → ayrıntılar `docs/installer.md`

**Bağımlılıklar:**
- `nixpkgs` (unstable)
- `home-manager` — kullanıcı dotfile yönetimi
- `chaotic-nyx` — CachyOS kernel (isteğe bağlı; yerelde derlenir)
- `disko` — declarative disk bölümleme

---

## Modül Yapısı (`modules/`)

| Modül | Amaç |
|---|---|
| `system/boot.nix` | systemd-boot, Plymouth, timeout |
| `system/kernel.nix` | Zen kernel (varsayılan, hazır derlenmiş) / CachyOS (isteğe bağlı) |
| `system/filesystem.nix` | Btrfs + subvolumes + tmpfs |
| `system/network.nix` | NetworkManager, mDNS, Bluetooth |
| `system/security.nix` | AppArmor, firewall, kernel hardening |
| `desktop/` | KDE Plasma 6, Wayland |
| `gaming/` | Steam, Gamescope, Lutris, Heroic, Discord |
| `gpu/` | AMD / NVIDIA / Intel driver seçimi |
| `apps/` | Flatpak, Firefox, Konsole |
| `ai/` | Ollama + ANKA AI daemon + MCP sunucuları |
| `performance/` | zram, governor, THP, earlyoom, AMD tweaks |
| `compat/windows.nix` | GE-Proton, umu-launcher, Bottles, NTFS |
| `compat/media.nix` | DVD, VAAPI, HW decode, media codecs |
| `accessibility/` | Orca, büyük fontlar (opt-in) |
| `update/` | Güncelleme sistemi + KDE KCM |
| `installer/` | First-run wizard |

---

## AI Katmanı

### Bugün çalışan

```
anka-ai "soru"  ──D-Bus──▶  daemon.py (org.anka.AI, kullanıcı oturumu)  ──HTTP──▶  Ollama
```

- **D-Bus servisi:** `org.anka.AI` — `Ask()`, `GetStatus()`, `ClearHistory()`, `SetModel()`
- **Terminal:** `anka-ai` (durum) / `anka-ai "soru"`
- **Model:** `qwen2.5:7b`, ilk soruda arka planda indirilir (açılışta indirilmez)
- **Hızlandırma:** ekran kartı varsa Ollama Vulkan ile çalışır (`anka.ai.acceleration`)
- **Kapatma:** sihirbazda "Hayır" → `~/.config/anka/setup.conf` içinde `AI_MODE=none`
- **Log:** `journalctl --user -u anka-ai`
- **MCP:** 8 sunucu `anka-mcp-<ad>` komutları olarak kurulu; liste `/etc/anka/mcp/servers.json`
  (standart `mcpServers` biçimi — Claude Desktop / Claude Code gibi istemcilerde kullanılabilir)

### Planlanan (henüz bağlı değil)

`intent.py` (niyet sınıflandırma), `router.py` (kişisel veriyi yerelde tutan yerel/bulut
yönlendirme), `memory.py` (uzun süreli hafıza), `confirmation_gate.py` (tehlikeli işlem
onayı), `voice_pipeline.py` (ses). Ayrıntılar: `services/anka-ai/anka-ai/README.md`

---

## Varsayılan Host Konfigürasyonu Özeti

- Boot: systemd-boot + Plymouth, 3s timeout
- Kernel: Zen (hazır derlenmiş) + scx_lavd zamanlayıcı (Valve)
- FS: Btrfs + subvolumes + tmpfs
- Desktop: KDE Plasma 6 + Wayland
- GPU: AMD (değiştirilebilir: nvidia / intel+nvidia)
- AI: qwen2.5:7b (ilk soruda iner), Vulkan hızlandırma, MCP aktif
- Performance: zram (lz4, %50), schedutil governor, earlyoom
- Compat: Windows (GE-Proton, Bottles, NTFS) + media codecs
- Update: stable channel, notify-only (autoApply=false)