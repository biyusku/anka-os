# ANKA gaming — Steam, GE-Proton helper, Gamescope, GameMode, MangoHud
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.gaming;
in
{
  options.anka.gaming = {
    enable = lib.mkEnableOption "ANKA gaming stack (Steam, Gamescope, GameMode)";

    steam = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Install and configure Steam.";
      };

      protonGe = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Enable GE-Proton management (handled via compat/windows.nix).";
      };

      remotePlay = lib.mkOption {
        type    = lib.types.bool;
        default = false;
        description = "Open Steam Remote Play firewall ports.";
      };

      localNetworkGameTransfers = lib.mkOption {
        type    = lib.types.bool;
        default = false;
        description = "Open Steam local network game transfer ports.";
      };
    };

    gamescope = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Enable Gamescope compositing session (FSR upscaling, frame limiter).";
      };

      capSysNice = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Give Gamescope CAP_SYS_NICE (needed for real-time priority).";
      };
    };

    lutris = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install Lutris (GOG, Epic, Itch.io launcher).";
    };

    heroic = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install Heroic Games Launcher (GOG + Epic native client).";
    };

    discord = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install Discord.";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Steam ─────────────────────────────────────────────────────────────
    programs.steam = lib.mkIf cfg.steam.enable {
      enable                        = true;
      remotePlay.openFirewall       = cfg.steam.remotePlay;
      localNetworkGameTransfers.openFirewall = cfg.steam.localNetworkGameTransfers;
      # Required for Proton / 32-bit games
      package                       = pkgs.steam.override {
        extraPkgs = steam-pkgs: with steam-pkgs; [
          libgdiplus
          keyutils
          libkrb5
          libpng
          libpulseaudio
          libvorbis
          stdenv.cc.cc.lib
          xorg.libXcursor
          xorg.libXi
          xorg.libXinerama
          xorg.libXScrnSaver
        ];
      };
      extraCompatPackages = with pkgs; [
        proton-ge-bin     # GE-Proton from nixpkgs (auto-updated)
      ];
    };

    # ── Gamescope ─────────────────────────────────────────────────────────
    programs.gamescope = lib.mkIf cfg.gamescope.enable {
      enable     = true;
      capSysNice = cfg.gamescope.capSysNice;
    };

    # ── GameMode ──────────────────────────────────────────────────────────
    # Detailed settings live in modules/performance/gaming.nix
    programs.gamemode.enable = true;

    # ── Extra gaming packages ─────────────────────────────────────────────
    environment.systemPackages = with pkgs; lib.concatLists [
      (lib.optional cfg.lutris  lutris)
      (lib.optional cfg.heroic  heroic)
      (lib.optional cfg.discord discord)
      [
        gamemode          # gamemoderun wrapper
        mangohud
        vkbasalt          # Vulkan post-processing (sharpening, SMAA)
        vulkan-tools      # vulkaninfo
        glxinfo           # OpenGL info
      ]
    ];

    # ── 32-bit graphics libraries (needed by Steam, Proton, DXVK) ────────
    hardware.graphics = {
      enable       = true;
      enable32Bit  = true;
    };

    # ── Udev rules for gaming peripherals ────────────────────────────────
    services.udev.packages = with pkgs; [
      game-devices-udev-rules    # PS3/PS4/PS5, Xbox, Steam Deck controller udev
    ];

    # ── User must be in 'gamemode' group ─────────────────────────────────
    users.groups.gamemode = {};
  };
}