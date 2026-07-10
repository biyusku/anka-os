# ANKA filesystem — disko layout, tmpfs /tmp, extra mount options
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.filesystem;
in
{
  options.anka.filesystem = {
    rootDevice = lib.mkOption {
      type    = lib.types.str;
      default = "/dev/disk/by-label/nixos";
      description = "Root filesystem device (override per-host in hardware-configuration.nix).";
    };

    rootFormat = lib.mkOption {
      type    = lib.types.enum [ "ext4" "btrfs" "xfs" ];
      default = "btrfs";
      description = "Root filesystem format.";
    };

    btrfsSubvolumes = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Use Btrfs subvolumes (@, @home, @nix, @snapshots).";
    };

    tmpOnTmpfs = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Mount /tmp as tmpfs (RAM disk). Cleared on reboot.";
    };

    tmpSize = lib.mkOption {
      type    = lib.types.str;
      default = "4G";
      description = "Max size of /tmp tmpfs (e.g. '4G', '50%').";
    };

    swapOnZram = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Enable zram swap (configured in performance module if both active).";
    };
  };

  config = {
    # ── /tmp as tmpfs ─────────────────────────────────────────────────────
    boot.tmp = {
      useTmpfs   = cfg.tmpOnTmpfs;
      tmpfsSize  = cfg.tmpSize;
      cleanOnBoot = true;
    };

    # ── Btrfs mount options (performance + CoW tuning) ────────────────────
    fileSystems = lib.mkIf (cfg.rootFormat == "btrfs" && cfg.btrfsSubvolumes) {
      "/" = {
        device  = cfg.rootDevice;
        fsType  = "btrfs";
        options = [ "subvol=@" "compress=zstd:1" "noatime" "space_cache=v2" "autodefrag" ];
      };
      "/home" = {
        device  = cfg.rootDevice;
        fsType  = "btrfs";
        options = [ "subvol=@home" "compress=zstd:1" "noatime" "space_cache=v2" ];
      };
      "/nix" = {
        device  = cfg.rootDevice;
        fsType  = "btrfs";
        options = [ "subvol=@nix" "compress=zstd:3" "noatime" "space_cache=v2" ];
      };
      "/.snapshots" = {
        device  = cfg.rootDevice;
        fsType  = "btrfs";
        options = [ "subvol=@snapshots" "noatime" "space_cache=v2" ];
      };
    };

    # ── Snapper automatic snapshots (Btrfs only) ──────────────────────────
    services.snapper = lib.mkIf (cfg.rootFormat == "btrfs" && cfg.btrfsSubvolumes) {
      snapshotRootOnBoot = lib.mkDefault false;
      configs.root = {
        SUBVOLUME    = "/";
        ALLOW_GROUPS = [ "wheel" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY   = "5";
        TIMELINE_LIMIT_DAILY    = "7";
        TIMELINE_LIMIT_WEEKLY   = "4";
        TIMELINE_LIMIT_MONTHLY  = "6";
        TIMELINE_LIMIT_YEARLY   = "2";
      };
    };

    # ── NFS / CIFS client utils ───────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      btrfs-progs     # Btrfs utilities
      compsize        # show Btrfs compression ratio
      e2fsprogs       # ext4 tools
      xfsprogs        # XFS tools
      dosfstools      # FAT/vfat tools (EFI partition)
      parted
      gptfdisk
      smartmontools   # disk health (SMART)
    ];

    # ── Systemd service: periodic Btrfs balance ───────────────────────────
    systemd.services.btrfs-balance = lib.mkIf (cfg.rootFormat == "btrfs") {
      description   = "Periodic Btrfs balance (maintain free space metadata)";
      serviceConfig = {
        Type      = "oneshot";
        ExecStart = "${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=70 -musage=70 /";
        Nice      = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.btrfs-balance = lib.mkIf (cfg.rootFormat == "btrfs") {
      description = "Periodic Btrfs balance timer";
      wantedBy    = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };
  };
}