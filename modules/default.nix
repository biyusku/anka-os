# ANKA OS — every ANKA module in one place.
# Imported by `nixosModules.default` in flake.nix; the values ANKA ships
# with live in ../profiles/default.nix.
{ ... }:

{
  imports = [
    # ── System base ───────────────────────────────────────────────────────
    ./system/boot.nix
    ./system/kernel.nix
    ./system/filesystem.nix
    ./system/network.nix
    ./system/security.nix

    # ── Desktop, hardware, apps ───────────────────────────────────────────
    ./desktop
    ./gpu
    ./apps

    # ── Gaming & performance ──────────────────────────────────────────────
    ./gaming
    ./performance

    # ── Compatibility ─────────────────────────────────────────────────────
    ./compat/windows.nix
    ./compat/media.nix
    ./adobe/default.nix

    # ── AI layer ──────────────────────────────────────────────────────────
    ./ai

    # ── Look & accessibility ──────────────────────────────────────────────
    ./branding
    ./accessibility

    # ── Updates & first-run wizard ────────────────────────────────────────
    ./update/default.nix
    ./update/version.nix
    ./installer/default.nix
  ];
}
