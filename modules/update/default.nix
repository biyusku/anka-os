{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.anka.update;
in
{
  imports = [ ./kcm ];
  options.anka.update = {
    enable = mkEnableOption "ANKA System Update Manager";

    channel = mkOption {
      type = types.enum [ "stable" "unstable" "testing" ];
      default = "stable";
      description = "ANKA update channel to track";
    };

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
    # Install update scripts
    environment.etc."anka/scripts/anka-rebuild.sh" = {
      source = ./anka-rebuild.sh;
      mode   = "0755";
    };

    environment.etc."anka/scripts/kde-notifier.py" = {
      source = ./kde-notifier.py;
      mode   = "0755";
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

    # One-shot service triggered by KCM panel or CLI to apply updates
    systemd.services.anka-apply-update = {
      description = "ANKA Apply System Update";
      after       = [ "network-online.target" ];
      wants       = [ "network-online.target" ];
      serviceConfig = {
        Type       = "oneshot";
        ExecStart  = "${pkgs.bash}/bin/bash ${cfg.flakePath}/scripts/anka-rebuild.sh apply";
        User       = "root";
        Environment = [
          "ANKA_FLAKE_PATH=${cfg.flakePath}"
          "ANKA_NOTIFY=${if cfg.notifyUser then "true" else "false"}"
        ];
      };
    };

    # One-shot service for rollback
    systemd.services.anka-rollback = {
      description = "ANKA Rollback to Previous Generation";
      serviceConfig = {
        Type      = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${cfg.flakePath}/scripts/anka-rebuild.sh rollback";
        User      = "root";
        Environment = [
          "ANKA_FLAKE_PATH=${cfg.flakePath}"
          "ANKA_NOTIFY=${if cfg.notifyUser then "true" else "false"}"
        ];
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