# ANKA OS — system updates
#
# An installed machine's /etc/nixos is a flake with ANKA as its `anka` input.
# `anka-update` (anka-update.sh) points that input at the newest ANKA for the
# channel and rebuilds. A timer checks and notifies; System Settings ›
# ANKA Updates (kcm/) applies updates and rolls them back.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.anka.update;

  anka-update = pkgs.writeShellApplication {
    name = "anka-update";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gawk
      gitMinimal
      gnugrep
      gnused
      jq
      libnotify
      util-linux                 # runuser
      config.nix.package
      config.system.build.nixos-rebuild
    ];
    text = builtins.readFile ./anka-update.sh;
  };

  kcm-anka-update = pkgs.callPackage ./kcm { };

  # Shared by the update units: nix needs a HOME and the proxy settings.
  unitEnvironment =
    config.nix.envVars
    // { HOME = "/root"; }
    // config.networking.proxy.envVars;

  # Units that run `nixos-rebuild switch` must not be restarted or stopped by
  # that same switch, or the update would kill itself half-way.
  rebuildUnit = description: command: {
    inherit description;
    after    = [ "network-online.target" ];
    wants    = [ "network-online.target" ];
    restartIfChanged = false;
    unitConfig.X-StopOnRemoval = false;
    environment = unitEnvironment;
    serviceConfig = {
      Type          = "oneshot";
      ExecStart     = "${anka-update}/bin/anka-update ${command}";
      StateDirectory = "anka-update";
    };
  };
in
{
  options.anka.update = {
    enable = mkEnableOption "ANKA System Update Manager";

    channel = mkOption {
      type = types.enum [ "stable" "unstable" ];
      default = "stable";
      description = ''
        stable: the newest vX.Y.Z release of ANKA (main until the first release).
        unstable: the main branch.
      '';
    };

    repo = mkOption {
      type = types.str;
      default = "biyusku/anka-os";
      description = "GitHub owner/repo ANKA is updated from.";
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
      description = "Send a desktop notification when an update is available";
    };

    flakePath = mkOption {
      type = types.str;
      default = "/etc/nixos";
      description = "This machine's system flake (the one with the `anka` input).";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ anka-update kcm-anka-update ];

    # Built by `nix flake check` (see checks in flake.nix)
    system.build.ankaUpdate = anka-update;
    system.build.kcmAnkaUpdate = kcm-anka-update;

    # Read by anka-update; one place for the CLI, the timer and the KCM.
    environment.etc."anka/update.conf".text = ''
      FLAKE_DIR=${escapeShellArg cfg.flakePath}
      REPO=${escapeShellArg cfg.repo}
      CHANNEL=${escapeShellArg cfg.channel}
      NOTIFY=${boolToString cfg.notifyUser}
      AUTO_APPLY=${boolToString cfg.autoApply}
    '';

    # Version of the ANKA this system was built from (ANKA_VERSION=x.y.z)
    environment.etc."anka/VERSION".source = ../../VERSION;

    # anka-update drives flakes.
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    # ── Check: on boot and every checkInterval ─────────────────────────────
    systemd.services.anka-update-check = rebuildUnit "ANKA Update Check" "check";

    systemd.timers.anka-update-check = {
      description = "ANKA Update Check Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec          = "5min";
        OnUnitActiveSec    = cfg.checkInterval;
        RandomizedDelaySec = "10min";
        Unit = "anka-update-check.service";
      };
    };

    # ── Started by the KCM (pkexec systemctl start …) or by hand ───────────
    systemd.services.anka-apply-update = rebuildUnit "ANKA Apply System Update" "apply";
    systemd.services.anka-rollback     = rebuildUnit "ANKA Roll Back the Last Update" "rollback";

    # Version display in MOTD
    environment.etc."anka/motd".text = ''
      ╔══════════════════════════════════╗
      ║         ANKA OS                  ║
      ║   Rise with ANKA                 ║
      ╚══════════════════════════════════╝
    '';
  };
}
