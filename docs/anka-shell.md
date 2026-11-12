# ANKA Shell

ANKA's own desktop: **Hyprland** draws the windows, **Quickshell** (QML)
draws everything around them — top bar, dock, panels. The goal is a desktop
that feels as finished as macOS while idling at roughly half of Plasma's
memory (~400–600 MB instead of ~1.2 GB).

It is opt-in and installed next to Plasma, so Plasma stays a fallback:

```nix
# /etc/nixos/configuration.nix
anka.desktop.shell.enable = true;    # "ANKA" appears on the login screen
anka.desktop.shell.default = true;   # …and is picked by default
```

## Layout

| File | What |
|---|---|
| `modules/desktop/shell/default.nix` | session, packages, generated configs |
| `modules/desktop/shell/hyprland.conf` | compositor defaults: gaps, rounding, blur, animations, keys |
| `modules/desktop/shell/hypridle.conf` | lock after 5 min, screen off after 7 |
| `modules/desktop/shell/hyprlock.conf` | lock screen |
| `modules/desktop/shell/qml/` | the shell; `shell.qml` is the entry point, `theme.js` the design tokens |

Users get a `~/.config/hypr/hyprland.conf` that sources
`/etc/anka/hypr/hyprland.conf`, so ANKA updates keep applying and their own
settings go below that line.

## Keys

| Key | Action |
|---|---|
| Super + Space | app launcher |
| Super + Return | terminal |
| Super + E / B | files / browser |
| Super + Q | close window |
| Super + F / V | fullscreen / float |
| Super + L | lock |
| Super + 1…5 | workspace (Shift: move window there) |

## Roadmap

1. **Foundation** (this) — session, wallpaper, top bar (logo, workspaces,
   active window, clock), dock (pinned apps, hover zoom, running dots), lock
   and idle.
2. **Control centre** — Wi-Fi, Bluetooth, volume and brightness sliders,
   Night Light, Do Not Disturb (NetworkManager, BlueZ and PipeWire through
   Quickshell's services).
3. **Notifications** — Quickshell notification server, a notification centre
   with calendar.
4. **Launcher** — ANKA's own (replaces fuzzel), with ANKA AI answers.
5. **Blur behind the shell** — Hyprland layer rules for the `anka-*`
   namespaces.
6. **Identity** — ANKA icon set, wallpapers, one font scale, motion guide.
7. **Settings** — ANKA's own settings app for what the KDE pages cover today.

Design is inspired by macOS but never copied: ANKA's own icons, wallpaper
and name; no Apple artwork or marks.
