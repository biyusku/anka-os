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
├── nixosConfigurations.anka          → Varsayılan masaüstü kurulumu
├── nixosConfigurations.anka-iso      → AMD ISO
├── nixosConfigurations.anka-iso-nvidia → NVIDIA ISO
├── nixosConfigurations.anka-iso-intel  → Intel ISO
└── packages.x86_64-linux.{iso, iso-amd, iso-nvidia, iso-intel}
```

**Bağımlılıklar:**
- `nixpkgs` (unstable)
- `home-manager` — kullanıcı dotfile yönetimi
- `chaotic-nyx` — CachyOS kernel + overlays
- `disko` — declarative disk bölümleme

---

## Modül Yapısı (`modules/`)

| Modül | Amaç |
|---|---|
| `system/boot.nix` | systemd-boot, Plymouth, timeout |
| `system/kernel.nix` | CachyOS BORE kernel |
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
| `adobe/` | Adobe uyumluluk katmanı (opt-in) |
| `update/` | Güncelleme sistemi + KDE KCM |
| `installer/` | First-run wizard |

---

## AI Katmanı

### Mimari

```
Kullanıcı (ses/metin)
    │
    ▼
voice_pipeline.py  ←→  faster-whisper (STT) + Kokoro/espeak (TTS)
    │
    ▼
daemon.py (D-Bus: org.anka.AI)
    │
    ├── intent.py       → İki kademeli intent sınıflandırma
    │   ├── Tier 1: Keyword-based (sub-ms, LLM yok)
    │   └── Tier 2: Claude Haiku structured output (belirsiz sorgular)
    │
    ├── router.py       → PII tespiti + kompleksite sınıflandırma
    │   ├── PII var → her zaman local
    │   ├── simple → local
    │   ├── medium → local-first (cloud fallback)
    │   └── complex → cloud
    │
    ├── memory.py       → Konuşma geçmişi yönetimi
    │
    └── MCP Sunucuları (8 adet)
        ├── mcp_filesystem.py  → Dosya sistemi erişimi
        ├── mcp_desktop.py     → Masaüstü kontrolü
        ├── mcp_network.py     → Ağ yönetimi
        ├── mcp_process.py     → Süreç yönetimi
        ├── mcp_audio.py       → Ses kontrolü
        ├── mcp_system.py      → Sistem yönetimi
        ├── mcp_diagnostics.py → Tanılama (read-only)
        └── mcp_package.py     → Paket yönetimi
```

### Önemli Detaylar

- **D-Bus servisi:** `org.anka.AI` — `Ask()`, `GetStatus()`, `ClearHistory()` metodları
- **Varsayılan model:** `qwen2.5:7b` (Ollama üzerinden)
- **Ses:** Whisper (STT) + Kokoro API / espeak-ng fallback (TTS)
- **Config:** `~/.config/anka/`
- **Log:** `/var/log/anka/ai-daemon.log`
- **Data:** `/var/lib/anka-ai`
- **MCP config:** `/etc/anka/mcp/servers.json`

### Intent Kategorileri (örnekler)

`VOLUME_CONTROL`, `BRIGHTNESS`, `APP_LAUNCH`, `FILE_OPERATION`, `SYSTEM_INFO`, vb.
Her intent: `handler` (module.function yolu), `requires_llm`, `llm_tier`, `is_destructive` alanlarını taşır.

---

## Güncelleme Sistemi

```
GitHub push/tag → GitHub Actions
                  ├── build-iso (amd/nvidia/intel matrix)
                  ├── Cachix cache push
                  └── GitHub Release (ISO artifacts)

Kurulu sistem (her gün 03:30)
→ anka-update-check.timer/service
  ├── /etc/anka-version okur
  ├── GitHub API'den son sürümü sorgular
  ├── Yeniyse: D-Bus masaüstü bildirimi
  └── autoApply=true ise: anka-apply-update.service başlatır

KDE KCM (System Settings > ANKA Updates)
  ├── Mevcut/yeni sürüm gösterimi
  ├── "Güncelle" butonu → pkexec systemctl start anka-apply-update
  ├── journalctl canlı log
  └── "Önceki Sürüme Dön" → nixos-rebuild --rollback
```

**Modül opsiyonları:**

| Opsiyon | Default | Açıklama |
|---|---|---|
| `anka.update.enable` | `true` | Güncelleme sistemi |
| `anka.update.channel` | `"stable"` | `stable` veya `nightly` |
| `anka.update.schedule` | `"*-*-* 03:30:00"` | systemd takvim |
| `anka.update.autoApply` | `false` | Otomatik güncelleme |

---

## ISO Varyantları

| Varyant | Komut | Açıklama |
|---|---|---|
| AMD (default) | `nix build .#iso-amd` | Genel / AMD GPU |
| NVIDIA | `nix build .#iso-nvidia` | NVIDIA proprietary |
| Intel | `nix build .#iso-intel` | Intel open-source |

---

## Teknik İsimler (Referans)

- D-Bus: `org.anka.AI`
- Systemd: `anka-ai.service`, `anka-update.service`
- MCP prefix: `anka-mcp-*`
- Kullanıcı grubu: `anka-users`, `anka-mcp`
- Config: `~/.config/anka/`
- Cachix: `anka-os.cachix.org`

---

## Varsayılan Host Konfigürasyonu Özeti

- Boot: systemd-boot + Plymouth, 3s timeout
- Kernel: CachyOS BORE
- FS: Btrfs + subvolumes + tmpfs
- Desktop: KDE Plasma 6 + Wayland
- GPU: AMD (değiştirilebilir: nvidia / intel+nvidia)
- AI: qwen2.5:7b, ses aktif, MCP aktif
- Performance: zram (lz4, %50), schedutil governor, earlyoom
- Compat: Windows (GE-Proton, Bottles, NTFS) + media codecs
- Update: stable channel, notify-only (autoApply=false)