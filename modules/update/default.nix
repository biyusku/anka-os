{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.ankaUpdate;
in
{
  options.services.ankaUpdate = {
    enable = mkEnableOption "ANKA System Update Manager";

    checkInterval = mkOption {
      type = types.str;
      default = "6h";
      description = "How often to check for updates";
    };

    autoApply = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically apply updates without user confirmation";
    };

    notifyUser = mkOption {
      type = types.bool;
      default = true;
      description = "Send KDE notification when updates are available";
    };

    flakePath = mkOption {
      type = types.str;
      default = "/etc/anka";
      description = "Path to the ANKA NixOS flake";
    };
  };

  config = mkIf cfg.enable {
    # Install notifier script
    environment.etc."anka/scripts/kde-notifier.py" = {
      source = ../../modules/update/kde-notifier.py;
      mode = "0755";
    };

    # Version tracking
    environment.etc."anka/VERSION".source = ../../VERSION;

    # Update check service
    systemd.services.anka-update-check = {
      description = "ANKA Update Check";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${cfg.flakePath}/scripts/anka-rebuild.sh check";
        User = "root";
        Environment = [
          "ANKA_FLAKE_PATH=${cfg.flakePath}"
          "ANKA_AUTO_APPLY=${if cfg.autoApply then "true" else "false"}"
          "ANKA_NOTIFY=${if cfg.notifyUser then "true" else "false"}"
        ];
      };
    };

    systemd.timers.anka-update-check = {
      description = "ANKA Update Check Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.checkInterval;
        Unit = "anka-update-check.service";
        Persistent = true;
      };
    };

    # Version display in MOTD
    environment.etc."anka/motd".text = ''
      ╔══════════════════════════════════╗
      ║         ANKA OS                  ║
      ║   Rise with ANKA                 ║
      ╚══════════════════════════════════╝
    '';
  };
}