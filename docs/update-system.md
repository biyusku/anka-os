# ANKA OS Update System

Technical documentation for the automated update pipeline.

## Architecture Overview

```
GitHub (anka-os/anka)
         │
         │  push to main / tag v*
         ▼
  GitHub Actions ──────────────────────────────────────┐
  build-iso.yml                                        │
  ├── build iso-amd                                    │
  ├── build iso-nvidia                                 │
  └── build iso-intel                                  │
         │                                             │
         ▼                                             ▼
    Cachix cache                              GitHub Release
  (anka-os.cachix.org)                   (ISO artifacts)

Installed system (daily at 03:30)
         │
  anka-update-check.timer
         │
  anka-update-check.service
  ├── reads /etc/anka-version
  ├── queries GitHub API for latest release
  ├── if newer: sends D-Bus desktop notification
  └── if autoApply=true: starts anka-apply-update.service

  anka-apply-update.service (manual or auto)
  ├── nixos-rebuild switch --flake github:anka-os/anka
  ├── success: updates /etc/anka-version, sends notification
  └── failure: sends error notification (system is unchanged)

KDE System Settings > ANKA Updates (KCM)
  ├── shows current / available version
  ├── "Güncelle" button → pkexec systemctl start anka-apply-update
  ├── live log via journalctl
  └── "Önceki Sürüme Dön" → nixos-rebuild switch --rollback
```

## GitHub Actions Workflows

### build-iso.yml

Triggers on:
- `push` to `main`
- `push` of tags matching `v*` (produces a GitHub Release)
- `pull_request` targeting `main`
- `workflow_dispatch` (manual)
- Weekly schedule (Mondays 09:00 UTC) — runs `update-flake-lock` job only

Jobs:

**build-iso** (matrix: amd / nvidia / intel)
1. Checkout source
2. Install Nix with `nix-command flakes` experimental features
3. Push build outputs to Cachix
4. `nix flake check --no-build`
5. `nix build .#packages.x86_64-linux.iso-<variant>`
6. Upload ISO as a workflow artifact (14-day retention)
7. On tag push: create a GitHub Release with the ISO attached

**update-flake-lock**
1. Runs `DeterminateSystems/update-flake-lock`
2. Opens a PR titled `chore: update flake.lock`
3. Labels the PR `dependencies` and `automated`

### test.yml

Triggers on `pull_request` and `push` to `main`.

Runs:
- `nix flake check` — evaluates all NixOS configurations
- `nix build .#packages.x86_64-linux.iso-amd --dry-run` — validates derivation graph
- `nix build .#nixosConfigurations.anka.config.system.build.toplevel --dry-run`

## Cachix Setup (for contributors)

1. Create a free account at https://app.cachix.org
2. Create a cache named `anka-os`
3. Copy the public key shown in the cache settings
4. Replace the placeholder in `flake.nix`:
   ```nix
   nixConfig.extra-trusted-public-keys = [
     "anka-os.cachix.org-1:<YOUR_REAL_PUBLIC_KEY_HERE>"
   ];
   ```
5. Add the signing key to your GitHub repository secrets as `CACHIX_AUTH_TOKEN`
6. Users can enable the cache locally with:
   ```bash
   cachix use anka-os
   ```

## Building the KCM Module

Requirements: CMake >= 3.20, Qt6, KF6 (ECM, CoreAddons, I18n, KCMUtils).

```bash
cd modules/update/kcm
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build -j$(nproc)
sudo cmake --install build
```

On NixOS with the flake, the KCM can be added to the system packages derivation
referencing the `kcm/` directory directly in a `stdenv.mkDerivation`.

## Update Commands

**Check for updates (CLI)**
```bash
anka-update-notify --check
```

**Apply update manually**
```bash
sudo nixos-rebuild switch --flake github:anka-os/anka
```

**Roll back to the previous generation**
```bash
sudo nixos-rebuild switch --rollback
# or via the bootloader: select the previous entry at boot
```

**List available generations**
```bash
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

## Updating the VERSION File

The `VERSION` file at the repository root drives `/etc/anka-version` and the
`system.nixos.label` bootloader entry.

Steps for a new release:

1. Update `VERSION`:
   ```bash
   echo "0.2.0" > VERSION
   ```
2. Commit and tag:
   ```bash
   git add VERSION
   git commit -m "chore(release): bump version to 0.2.0"
   git tag -s v0.2.0 -m "Release v0.2.0"
   git push origin main --tags
   ```
3. The `build-iso.yml` workflow triggers automatically and creates a GitHub Release.
4. Generate a changelog with git-cliff:
   ```bash
   git cliff --tag v0.2.0 -o CHANGELOG.md
   ```

## NixOS Module Options

| Option | Type | Default | Description |
|---|---|---|---|
| `anka.update.enable` | bool | `true` | Enable update check system |
| `anka.update.channel` | enum | `"stable"` | `"stable"` or `"nightly"` |
| `anka.update.schedule` | str | `"*-*-* 03:30:00"` | systemd calendar expression |
| `anka.update.repoUrl` | str | `"github:anka-os/anka"` | Flake URL for `nixos-rebuild` |
| `anka.update.autoApply` | bool | `false` | Auto-apply when update found |