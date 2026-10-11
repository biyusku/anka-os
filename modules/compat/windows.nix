# ANKA Windows Compatibility — Proton, Wine, Bottles, NTFS, umu-launcher
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.compat.windows;
in
{
  options.anka.compat.windows = {
    enable = lib.mkEnableOption "Windows compatibility layer (Proton, Wine, Bottles, NTFS)";

    geProton = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = ''
          Offer GE-Proton (community Proton build with extra patches) in
          Steam's compatibility tools. Uses nixpkgs' proton-ge-bin, which is
          updated with the rest of the system.
        '';
      };
    };

    umuLauncher = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Install umu-launcher — the universal game launcher that works with
        GE-Proton, SteamTinkerLaunch, and Heroic without requiring Steam.
      '';
    };

    protontricks = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install protontricks — Winetricks wrapper for Steam Proton prefixes.";
    };

    bottles = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install Bottles — GUI Wine prefix manager for non-Steam Windows apps.";
    };

    ntfs = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Enable automatic NTFS partition mounting.";
      };

      driver = lib.mkOption {
        type    = lib.types.enum [ "ntfs-3g" "ntfs3" ];
        default = "ntfs-3g";
        description = ''
          NTFS driver to use.
          ntfs-3g — FUSE-based, battle-tested, slightly slower.
          ntfs3   — In-kernel driver (Linux 5.15+), faster writes; still experimental on some distros.
        '';
      };

      autoMountOptions = lib.mkOption {
        type    = lib.types.listOf lib.types.str;
        default = [ "uid=1000" "gid=100" "dmask=022" "fmask=133" "nofail" "x-gvfs-show" ];
        description = "Default mount options applied to NTFS partitions found by udisks2.";
      };
    };

    wineOffice = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = ''
        Set up a dedicated Wine Staging prefix for Microsoft Office / legacy
        Windows applications (separate from game prefixes).
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Core Wine packages ────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; lib.concatLists [
      # Base Wine
      [ wine-staging winetricks cabextract p7zip ]

      # Optional packages
      (lib.optional cfg.umuLauncher umu-launcher)
      (lib.optional cfg.protontricks protontricks)
      (lib.optional cfg.bottles bottles)
      (lib.optional cfg.ntfs.enable ntfs3g)
      # Lutris / Heroic: anka.gaming.lutris / anka.gaming.heroic
    ];

    # ── GE-Proton in Steam's compatibility tools ──────────────────────────────
    programs.steam.extraCompatPackages = lib.mkIf cfg.geProton.enable [ pkgs.proton-ge-bin ];

    # ── NTFS driver selection ─────────────────────────────────────────────────
    boot.extraModprobeConfig = lib.mkIf (cfg.ntfs.enable && cfg.ntfs.driver == "ntfs3") ''
      # Prefer the in-kernel ntfs3 driver when mounted as "ntfs3"
      options ntfs3 nohidden prealloc
    '';

    # udev rule: auto-mount NTFS partitions with the correct options
    services.udev.extraRules = lib.mkIf cfg.ntfs.enable ''
      # Mount NTFS partitions via udisks2 with anka defaults
      ENV{ID_FS_TYPE}=="ntfs", ENV{UDISKS_FILESYSTEM_SHARED}="1"
    '';

    # udisks2 needed for auto-mounting in KDE/GNOME/etc
    services.udisks2.enable = lib.mkDefault true;

    # ntfs-3g must be setuid for non-root mounts
    security.wrappers.mount-ntfs-3g = lib.mkIf (cfg.ntfs.enable && cfg.ntfs.driver == "ntfs-3g") {
      source  = "${pkgs.ntfs3g}/bin/ntfs-3g";
      owner   = "root";
      group   = "root";
      setuid  = true;
    };

    # ── Kernel modules ────────────────────────────────────────────────────────
    boot.kernelModules = lib.mkIf (cfg.ntfs.enable && cfg.ntfs.driver == "ntfs3") [ "ntfs3" ];

    # ── Wine Office prefix setup (optional) ──────────────────────────────────
    systemd.user.services.anka-wine-office-init = lib.mkIf cfg.wineOffice {
      description   = "Initialize ANKA Office Wine prefix";
      wantedBy      = [ "default.target" ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        ExecStart       = pkgs.writeShellScript "anka-wine-office-init" ''
          WINEPREFIX="$HOME/.local/share/anka/wine-office"
          if [ ! -d "$WINEPREFIX" ]; then
            echo "Creating Office Wine prefix..."
            WINEPREFIX="$WINEPREFIX" WINEARCH=win64 \
              ${pkgs.wine-staging}/bin/wineboot --init
            WINEPREFIX="$WINEPREFIX" \
              ${pkgs.winetricks}/bin/winetricks -q corefonts vcrun2019 dotnet48
          fi
        '';
      };
    };

    # ── Allow users in 'wheel' to manage Wine/Proton ─────────────────────────
    users.groups.anka-compat = {};

  };
}