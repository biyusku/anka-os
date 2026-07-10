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

    governor = lib.mkOption {
      type    = lib.types.enum [ "schedutil" "ondemand" "powersave" "performance" "conservative" ];
      default = "schedutil";
      description = ''
        CPU frequency scaling governor.
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
      "vm.swappiness"             = 10;
      "vm.dirty_ratio"            = 15;
      "vm.dirty_background_ratio" = 5;
      "vm.vfs_cache_pressure"     = 50;

      # Transparent Huge Pages
      "kernel.mm.transparent_hugepage.enabled" = cfg.thp;
      "kernel.mm.transparent_hugepage.defrag"  = "defer+madvise";

      # Network performance
      "net.core.netdev_max_backlog"   = 16384;
      "net.core.somaxconn"            = 8192;
      "net.ipv4.tcp_fastopen"         = 3;
      "net.ipv4.tcp_mtu_probing"      = 1;

      # File descriptor limits
      "fs.file-max"    = 2097152;
      "fs.inotify.max_user_watches" = 524288;

      # CachyOS / BORE scheduler hint
      "kernel.sched_latency_ns"       = 4000000;
      "kernel.sched_migration_cost_ns" = 500000;
      "kernel.sched_min_granularity_ns" = 500000;
    };

    # ── zram compressed swap ─────────────────────────────────────────────────
    zramSwap = lib.mkIf cfg.zram.enable {
      enable          = true;
      algorithm       = cfg.zram.algorithm;
      memoryPercent   = cfg.zram.memoryPercent;
      priority        = 100; # prefer zram over disk swap
    };

    # ── CPU governor ─────────────────────────────────────────────────────────
    powerManagement.cpuFreqGovernor = cfg.governor;

    # ── I/O schedulers via udev rules ────────────────────────────────────────
    services.udev.extraRules = ''
      # NVMe — no scheduler (drive-internal NCQ is smarter)
      ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="${cfg.ioScheduler.nvme}"

      # SATA / HDD
      ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{rotational}=="0", ATTR{queue/scheduler}="${cfg.ioScheduler.nvme}"
      ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{rotational}=="1", ATTR{queue/scheduler}="${cfg.ioScheduler.sata}"

      # USB mass storage
      ACTION=="add|change", KERNEL=="sd[a-z]*", SUBSYSTEMS=="usb", ATTR{queue/scheduler}="${cfg.ioScheduler.usb}"

      # eMMC (common on budget laptops)
      ACTION=="add|change", KERNEL=="mmcblk[0-9]*", ATTR{queue/scheduler}="${cfg.ioScheduler.nvme}"
    '';

    # ── earlyoom ─────────────────────────────────────────────────────────────
    services.earlyoom = lib.mkIf cfg.enableEarlyoom {
      enable            = true;
      freeMemThreshold  = cfg.earlyoom.freeMemThresholdPercent;
      freeSwapThreshold = cfg.earlyoom.freeSwapThresholdPercent;
      extraArgs         = [
        "--prefer '^(Web Content|chromium|firefox)$'"
        "--avoid '^(kwin_wayland|plasmashell|systemd|anka)$'"
        "-n"   # send SIGTERM first, then SIGKILL after 1 s
      ];
    };

    # ── Preload frequently-used executables into page cache ──────────────────
    services.preload.enable = lib.mkDefault false; # opt-in; SSD users don't need it

    # ── Packages ─────────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      powertop      # CPU power analysis
      s-tui         # stress + TUI monitor
      btop          # resource monitor
      iotop         # I/O per-process
      numactl       # NUMA topology control
    ];

    # ── CachyOS / BORE kernel extra params ───────────────────────────────────
    # These are added in modules/system/kernel.nix via chaotic-nyx.
    # Here we add extra cmdline hints for the BORE scheduler.
    boot.kernelParams = [
      "mitigations=auto"         # keep Spectre/Meltdown mitigations but skip unnecessary ones
      "nowatchdog"               # disable NMI watchdog → lower latency
      "nmi_watchdog=0"
      "transparent_hugepage=${cfg.thp}"
    ];

  };
}