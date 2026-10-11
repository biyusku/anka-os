# ANKA Performance Layer — kernel tuning, zram, CPU governor, I/O scheduler
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.performance;
in
{
  imports = [
    ./gaming.nix
  ];

  options.anka.performance = {
    enable = lib.mkEnableOption "ANKA performance tuning (kernel, memory, I/O)";

    zram = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Enable zram compressed swap (lz4, 50 % of RAM).";
      };

      algorithm = lib.mkOption {
        type    = lib.types.enum [ "lz4" "lz4hc" "zstd" "lzo" "lzo-rle" ];
        default = "lz4";
        description = "zram compression algorithm. lz4 is fastest; zstd has best ratio.";
      };

      memoryPercent = lib.mkOption {
        type    = lib.types.ints.between 10 100;
        default = 50;
        description = "Percentage of total RAM to use as zram capacity.";
      };
    };

    scheduler = lib.mkOption {
      type    = lib.types.enum [ "none" "scx_lavd" "scx_bpfland" "scx_rusty" ];
      default = "none";
      description = ''
        sched_ext CPU scheduler loaded on top of the kernel's own.
        scx_lavd — latency-aware scheduler Valve developed for the Steam Deck;
                   keeps games and the desktop responsive under load.
        If a sched_ext scheduler stops, the kernel falls back to its default
        scheduler on its own.
      '';
    };

    governor = lib.mkOption {
      type    = lib.types.enum [ "auto" "schedutil" "ondemand" "powersave" "performance" "conservative" ];
      default = "auto";
      description = ''
        CPU frequency scaling governor.
        'auto' leaves it to the CPU driver and Plasma's power profiles
        (power-profiles-daemon). Modern Intel (intel_pstate) and AMD
        (amd-pstate) drivers only offer 'performance' and 'powersave', so
        forcing another governor fails there.
        'schedutil' is the recommended default; gaming.nix overrides to 'performance'
        when anka.performance.gaming.enable is true and the game is active.
      '';
    };

    ioScheduler = {
      nvme = lib.mkOption {
        type    = lib.types.enum [ "none" "mq-deadline" "bfq" "kyber" ];
        default = "none";
        description = "I/O scheduler for NVMe devices. 'none' lets the drive queue itself.";
      };

      sata = lib.mkOption {
        type    = lib.types.enum [ "mq-deadline" "bfq" "kyber" "none" ];
        default = "mq-deadline";
        description = "I/O scheduler for SATA/HDD devices.";
      };

      usb = lib.mkOption {
        type    = lib.types.enum [ "bfq" "mq-deadline" "none" ];
        default = "bfq";
        description = "I/O scheduler for USB mass storage devices.";
      };
    };

    thp = lib.mkOption {
      type    = lib.types.enum [ "always" "madvise" "never" ];
      default = "madvise";
      description = ''
        Transparent Huge Pages policy.
        'madvise' lets applications opt-in (recommended — avoids latency spikes).
      '';
    };

    enableEarlyoom = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Enable earlyoom — kills the largest memory hog before the kernel OOM killer
        freezes the whole desktop.
      '';
    };

    earlyoom = {
      freeMemThresholdPercent = lib.mkOption {
        type    = lib.types.ints.between 1 50;
        default = 5;
        description = "Trigger earlyoom when free RAM drops below this percentage.";
      };

      freeSwapThresholdPercent = lib.mkOption {
        type    = lib.types.ints.between 1 50;
        default = 10;
        description = "Trigger earlyoom when free swap drops below this percentage.";
      };
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Kernel sysctl tuning ─────────────────────────────────────────────────
    boot.kernel.sysctl = {
      # Memory
      "vm.dirty_ratio"            = 15;
      "vm.dirty_background_ratio" = 5;
      "vm.vfs_cache_pressure"     = 50;

      # Network performance
      "net.core.netdev_max_backlog"   = 16384;
      "net.core.somaxconn"            = 8192;
      "net.ipv4.tcp_fastopen"         = 3;
      "net.ipv4.tcp_mtu_probing"      = 1;

      # File descriptor limits
      "fs.file-max"    = 2097152;
      "fs.inotify.max_user_watches" = 524288;
    }
    # Swap: zram is RAM-speed, so swap to it eagerly (Arch wiki "zram",
    # as on Pop!_OS and ChromeOS); without zram keep disk swap a last resort.
    // (if cfg.zram.enable then {
      "vm.swappiness"                = 180;
      "vm.page-cluster"              = 0;
      "vm.watermark_boost_factor"    = 0;
      "vm.watermark_scale_factor"    = 125;
    } else {
      "vm.swappiness"                = 10;
    });

    # Transparent Huge Pages: mode via the kernel command line (below);
    # defrag lives in sysfs, not sysctl.
    systemd.tmpfiles.rules = [
      "w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise"
    ];

    # ── zram compressed swap ─────────────────────────────────────────────────
    zramSwap = lib.mkIf cfg.zram.enable {
      enable          = true;
      algorithm       = cfg.zram.algorithm;
      memoryPercent   = cfg.zram.memoryPercent;
      priority        = 100; # prefer zram over disk swap
    };

    # ── CPU governor ─────────────────────────────────────────────────────────
    powerManagement.cpuFreqGovernor = lib.mkIf (cfg.governor != "auto") cfg.governor;

    # ── I/O schedulers via udev rules ────────────────────────────────────────
    services.udev.extraRules = ''
      # Whole disks only (partitions have no queue/scheduler).
      # NVMe — no scheduler (drive-internal NCQ is smarter)
      ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ENV{DEVTYPE}=="disk", ATTR{queue/scheduler}="${cfg.ioScheduler.nvme}"

      # SATA / HDD
      ACTION=="add|change", KERNEL=="sd[a-z]*", ENV{DEVTYPE}=="disk", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="${cfg.ioScheduler.nvme}"
      ACTION=="add|change", KERNEL=="sd[a-z]*", ENV{DEVTYPE}=="disk", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="${cfg.ioScheduler.sata}"

      # USB mass storage
      ACTION=="add|change", KERNEL=="sd[a-z]*", ENV{DEVTYPE}=="disk", SUBSYSTEMS=="usb", ATTR{queue/scheduler}="${cfg.ioScheduler.usb}"

      # eMMC (common on budget laptops)
      ACTION=="add|change", KERNEL=="mmcblk[0-9]*", ENV{DEVTYPE}=="disk", ATTR{queue/scheduler}="${cfg.ioScheduler.nvme}"
    '';

    # ── earlyoom ─────────────────────────────────────────────────────────────
    services.earlyoom = lib.mkIf cfg.enableEarlyoom {
      enable            = true;
      freeMemThreshold  = cfg.earlyoom.freeMemThresholdPercent;
      freeSwapThreshold = cfg.earlyoom.freeSwapThresholdPercent;
      # One argv element per word: the module shell-escapes each element.
      extraArgs = [
        "--prefer" "^(Web Content|chromium|firefox)$"
        "--avoid"  "^(kwin_wayland|plasmashell|systemd|anka-ai-daemon)$"
      ];
      # Tell the user which app was closed to free memory.
      enableNotifications = true;
    };

    # ── sched_ext scheduler (kernel ≥ 6.12) ──────────────────────────────────
    services.scx = lib.mkIf (cfg.scheduler != "none") {
      enable    = true;
      scheduler = cfg.scheduler;
    };

    # ── Packages ─────────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      powertop      # CPU power analysis
      s-tui         # stress + TUI monitor
      btop          # resource monitor
      iotop         # I/O per-process
      numactl       # NUMA topology control
    ];

    # ── Low-latency kernel command line ──────────────────────────────────────
    boot.kernelParams = [
      "mitigations=auto"         # keep Spectre/Meltdown mitigations but skip unnecessary ones
      "nowatchdog"               # disable NMI watchdog → lower latency
      "nmi_watchdog=0"
      "transparent_hugepage=${cfg.thp}"
    ];

  };
}