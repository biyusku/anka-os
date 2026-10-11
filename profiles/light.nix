# ANKA OS — "Hafif" (light) profile, for older or smaller computers.
#
# Same desktop, drivers, Steam and Proton; leaves out the large extras.
# Everything left out can still be installed later from Discover (Flathub).
# Priority 900 wins over the full profile (lib.mkDefault = 1000) but not
# over a machine's own configuration.nix (100).
{ config, lib, ... }:

{
  options.anka.profile = lib.mkOption {
    type    = lib.types.enum [ "full" "light" ];
    default = "full";
    description = ''
      full  — everything ANKA ships (AI assistant, game launchers, office suite).
      light — for older or smaller computers: no local AI, no Lutris/Heroic/
              Discord/Bottles, no office or graphics suite (all available in
              Discover), zstd-compressed zram.
    '';
  };

  config = lib.mkIf (config.anka.profile == "light") {
    anka = lib.mapAttrsRecursive (_: lib.mkOverride 900) {
      ai.enable = false;              # Ollama + a ~5 GB model

      gaming = {
        lutris  = false;
        heroic  = false;
        discord = false;
      };
      compat.windows.bottles = false;
      apps = {
        bottles     = false;
        desktopApps = false;          # LibreOffice, GIMP, Signal, Bitwarden, Obsidian
      };
      compat.media.extraPlayers = false;

      # Better compression for machines with little RAM.
      performance.zram.algorithm = "zstd";
    };
  };
}
