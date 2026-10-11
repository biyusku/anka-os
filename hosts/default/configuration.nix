# ANKA OS — reference machine
# CI evaluates this host (`nixosConfigurations.anka`) to check that ANKA
# builds. Real installs don't use it: the installer writes the machine's own
# /etc/nixos (hardware-configuration.nix + configuration.nix) and builds it
# with `anka.lib.mkSystem`, which pulls in the same modules and profile.
{ config, lib, pkgs, inputs, ... }:

{
  # This host has no hardware-configuration.nix, so let ANKA declare the
  # Btrfs subvolume mounts itself.
  anka.filesystem.manageMounts = true;

  # ── Primary user ──────────────────────────────────────────────────────
  users.users.anka = {
    isNormalUser  = true;
    description   = "ANKA User";
    extraGroups   = [
      "wheel"          # sudo
      "networkmanager" # NM without password
      "video"          # GPU / DRI access
      "audio"          # audio (PipeWire)
      "gamemode"       # GameMode
      "anka-mcp"       # MCP server access (for AI daemon)
    ];
    initialPassword = "anka";   # CHANGE AFTER FIRST LOGIN
  };

  # ── Home Manager — user-level configuration ───────────────────────────
  home-manager = {
    useGlobalPkgs   = true;
    useUserPackages = true;
    users.anka    = import ./home.nix;
  };

  # ── State version — do NOT change after first install ────────────────
  system.stateVersion = "24.11";
}
