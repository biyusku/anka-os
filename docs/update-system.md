# ANKA OS Update System

How installed machines get new versions of ANKA.

## How it works

An installed machine's `/etc/nixos` is a flake with ANKA as its `anka` input
(written by the installer, see `docs/installer.md`):

```nix
inputs.anka.url = "github:biyusku/anka-os";        # unstable: main branch
inputs.anka.url = "github:biyusku/anka-os/v0.2.0"; # stable: a release tag
```

Updating ANKA = pointing that input at a newer ANKA, locking it and rebuilding.
All of it is done by one tool, `anka-update` (`modules/update/anka-update.sh`):

```
anka-update status [--json]   installed vs. newest version (no root needed)
anka-update check             status + desktop notification (+ apply if autoApply)
sudo anka-update apply        update to the newest ANKA for the channel
sudo anka-update rollback     back to the ANKA used before the last update
```

| Channel | Follows |
|---|---|
| `stable` (default) | the newest `vX.Y.Z` tag; `main` until the first release |
| `unstable` | the `main` branch |

`apply`:
1. finds the newest version (`git ls-remote`, no API rate limits),
2. asks GitHub's compare API whether it is actually newer, so a machine that is
   already ahead of the newest release is never downgraded,
3. backs up `flake.nix` / `flake.lock` to `/var/lib/anka-update/previous`,
4. rewrites `inputs.anka.url`, runs `nix flake update anka` and
   `nixos-rebuild switch --flake /etc/nixos#anka`,
5. on failure restores both files (the running system is unchanged).

`rollback` restores the backed-up files and rebuilds. The boot menu still lists
every earlier generation as a last resort (it is hidden: hold Space — Shift or
Esc with GRUB — while the computer starts).

## Pieces

```
modules/update/default.nix      options, /etc/anka/update.conf, systemd units
modules/update/anka-update.sh   the tool (writeShellApplication → shellcheck at build)
modules/update/kcm/             System Settings › ANKA Updates (Qt6/KF6)
```

systemd units (all `Type=oneshot`):

| Unit | Runs | Started by |
|---|---|---|
| `anka-update-check` | `anka-update check` | timer: 5 min after boot, then every `checkInterval` |
| `anka-apply-update` | `anka-update apply` | the KCM (`pkexec systemctl start …`) |
| `anka-rollback` | `anka-update rollback` | the KCM |

The units that rebuild have `restartIfChanged = false`, so the switch they
run cannot restart (and kill) them. Notifications are sent to every logged-in
user's session bus, once per new version.

The KCM reads `anka-update status --json` and shows the journal of the two
units after an update or rollback.

## Options

| Option | Default | Description |
|---|---|---|
| `anka.update.enable` | `true` (profile) | Update tooling, timer and KCM |
| `anka.update.channel` | `"stable"` | `"stable"` or `"unstable"` |
| `anka.update.repo` | `"biyusku/anka-os"` | GitHub owner/repo |
| `anka.update.checkInterval` | `"6h"` | Time between checks |
| `anka.update.autoApply` | `false` | Apply updates without asking |
| `anka.update.notifyUser` | `true` | Desktop notification on new versions |
| `anka.update.flakePath` | `"/etc/nixos"` | The machine's system flake |

## Releasing a new version

1. Bump `ANKA_VERSION` in `VERSION`.
2. Commit, tag and push:
   ```bash
   git tag -s v0.2.0 -m "Release v0.2.0"
   git push origin main --tags
   ```
3. `build-iso.yml` builds the ISOs and creates the GitHub Release.
   Machines on the `stable` channel see the update at their next check.
4. Changelog: `git cliff --tag v0.2.0 -o CHANGELOG.md`

## CI

- `test.yml`: `nix flake check` evaluates every configuration and **builds**
  the `checks` (anka-update, the KCM); installer unit tests run separately.
- `build-iso.yml`: ISOs for amd / nvidia / intel; releases on `v*` tags;
  weekly `flake.lock` update PR.

## Cachix (for maintainers)

1. Create a cache named `anka-os` at https://app.cachix.org
2. Put its public key in `flake.nix` (`nixConfig.extra-trusted-public-keys`)
3. Add the auth token to the repository secrets as `CACHIX_AUTH_TOKEN`
