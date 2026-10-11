# ANKA OS

> Windows-compatible · Mac-level simplicity · Linux-light · AI-native
>
> *"Eski bir laptop, yeni bir hayat."* — An old laptop, a new life.

ANKA is a desktop operating system built on [NixOS](https://nixos.org) and
KDE Plasma 6: install it like any OS, play Windows games through Steam and
Proton, run Windows programs with Bottles, and keep the whole system
reproducible and rollback-safe underneath.

## What you get

| | |
|---|---|
| **Installer** | Graphical (Calamares): language, keyboard, user, *ANKA* or *ANKA Hafif*, disk (Btrfs with snapshots, optional encryption). Graphics drivers are detected automatically. |
| **Games** | Steam with GE-Proton, Game Mode (a console-style Steam session on the login screen), GameMode, MangoHud, Lutris, Heroic. |
| **Windows apps** | Wine, Bottles, umu-launcher, NTFS drives. |
| **Light & fast** | Prebuilt Zen kernel + Valve's `scx_lavd` scheduler, zram, earlyoom. *ANKA Hafif* leaves out the large extras for older computers. |
| **Simple** | One welcome screen, updates from System Settings › ANKA Updates, the ANKA look from boot splash to desktop. |
| **AI assistant** | On-device (Ollama, no data leaves the computer), `anka-ai "question"`; MCP servers for AI tools. |
| **Safe updates** | Every update is a new system generation; roll back from System Settings or the boot menu. |

## Get ANKA

ISOs are built by GitHub Actions for every release (`v*` tags): one per GPU
family for the live session — the installed system detects the GPU itself.

Build one yourself (Linux with [Nix](https://nixos.org/download)):

```bash
make build-iso             # AMD / generic → result-iso/iso/anka-amd.iso
make test-iso-uefi         # boot it in QEMU (UEFI)
nix build .#iso-nvidia     # NVIDIA live session → result/iso/anka-nvidia.iso
nix build .#iso-intel      # Intel live session  → result/iso/anka-intel.iso
```

## After installing

```bash
anka-update status          # installed / newest version
sudo anka-update apply      # update (same as System Settings › ANKA Updates)
sudo anka-update rollback   # back to the version before the last update
```

The machine's own settings live in `/etc/nixos/configuration.nix`
(written by the installer); ANKA's defaults can be overridden there, e.g.
`anka.profile = "light";` or `anka.gaming.gameMode.default = true;`.
Apply with `sudo nixos-rebuild switch --flake /etc/nixos#anka`.

## Repository

```
flake.nix            nixosModules.default, lib.mkSystem, ISOs, checks
profiles/            ANKA's defaults (default.nix) and the light profile
modules/             system, desktop, gpu, gaming, compat, performance,
                     ai, branding, update, installer (first-login welcome)
iso/                 live ISO + the ANKA installer (iso/calamares)
services/anka-ai/    AI daemon, CLI and MCP servers
docs/                installer.md, update-system.md, branding.md
```

`nix flake check` evaluates every configuration, evaluates a matrix of
option combinations, and builds ANKA's own packages; the installer has
Python unit tests (`python3 -m unittest discover -s iso/calamares/tests`).

## Türkçe

ANKA, NixOS ve KDE Plasma 6 üzerine kurulu bir masaüstü işletim sistemi:
Windows kadar destekli, Mac kadar sade, Linux kadar hafif. Kurulumda
*ANKA* (her şey dahil) veya *ANKA Hafif* (eski/küçük bilgisayarlar için)
seçilir; ekran kartı otomatik algılanır. Oyunlar Steam + Proton ile, Windows
programları Bottles ile çalışır; giriş ekranındaki "Steam" oturumu SteamOS
tarzı Oyun Modu'dur. Güncellemeler Sistem Ayarları › ANKA Updates'ten
yapılır ve her güncelleme geri alınabilir. Ayrıntılar: `docs/`.
