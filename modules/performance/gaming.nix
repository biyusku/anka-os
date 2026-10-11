# ANKA Gaming Performance — GameMode, CPU isolation, RT audio, GPU tweaks
{ config, lib, pkgs, ... }:

let
  cfg  = config.anka.performance;
  gcfg = config.anka.gaming;
  gpu  = config.anka.gpu;
in
{
  options.anka.performance.gaming = {
    enable = lib.mkEnableOption "Gaming-specific performance optimisations";

    isolateCpus = lib.mkOption {
      type    = lib.types.str;
      default = "";
      example = "4-7";
      description = ''
        CPU cores to isolate from the Linux scheduler (isolcpus= kernel parameter).
        These cores are then pinned to the game process by GameMode.
        Leave empty to disable isolation (recommended for < 8-core CPUs).
        Example: "4-7" isolates cores 4–7 on an 8-core CPU.
      '';
    };

    realtimeAudio = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Grant the 'audio' and 'anka-gamemode' groups real-time scheduling
        priority via /etc/security/limits.d/. Required for sub-5 ms audio
        latency with PipeWire in low-latency mode.
      '';
    };

    nvidiaTweaks = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Enable NVIDIA-specific gaming tweaks:
        - PowerMizer prefers maximum performance while GameMode is active
        - nvidia-persistenced kept running
        Only applied when anka.gpu.type = "nvidia".
      '';
    };

    amdTweaks = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Enable AMD-specific gaming tweaks:
        - GPU performance level "high" while GameMode is active
        Only applied when anka.gpu.type = "amd".
      '';
    };

    gameModeReaper = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Kill background non-essential services (e.g. indexers, update checks)
        while a game is running. They restart when GameMode exits.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.gaming.enable) {

    # ── GameMode ─────────────────────────────────────────────────────────────
    programs.gamemode = {
      enable   = true;
      settings = {
        general = {
          renice        = 10;         # nice -10 for game process
          inhibit_screensaver = 1;
          softrealtime  = "auto";
          reaper_freq   = 5;          # check for dead game PIDs every 5 s
        };
        cpu = {
          park_cores      = "no";
          pin_cores       = if cfg.gaming.isolateCpus != "" then "yes" else "no";
          governor        = "performance";  # override schedutil while game runs
        };
        gpu = lib.mkMerge [
          { apply_gpu_optimisations = "accept-responsibility"; }
          (lib.mkIf (gpu.type == "amd" && cfg.gaming.amdTweaks) {
            gpu_device       = 0;
            amd_performance_level = "high";
          })
          (lib.mkIf (gpu.type == "nvidia" && cfg.gaming.nvidiaTweaks) {
            nv_powermizer_mode  = 1;   # prefer maximum performance
            nv_core_clock_mhz_offset  = 0;
            nv_mem_clock_mhz_offset   = 0;
          })
        ];
        # Pause KDE's file indexer while a game runs (GameMode runs these as the user).
        custom = lib.mkIf cfg.gaming.gameModeReaper {
          start = "${pkgs.kdePackages.baloo}/bin/balooctl6 suspend";
          end   = "${pkgs.kdePackages.baloo}/bin/balooctl6 resume";
        };
      };
    };

    # ── CPU isolation (isolcpus kernel param) ─────────────────────────────────
    boot.kernelParams = lib.mkIf (cfg.gaming.isolateCpus != "") [
      "isolcpus=${cfg.gaming.isolateCpus}"
      "rcu_nocbs=${cfg.gaming.isolateCpus}"
      "nohz_full=${cfg.gaming.isolateCpus}"
    ];

    # ── Real-time audio limits ────────────────────────────────────────────────
    security.pam.loginLimits = lib.mkIf cfg.gaming.realtimeAudio [
      { domain = "@audio";              item = "memlock"; type = "hard"; value = "unlimited"; }
      { domain = "@audio";              item = "memlock"; type = "soft"; value = "unlimited"; }
      { domain = "@audio";              item = "rtprio";  type = "hard"; value = "99"; }
      { domain = "@audio";              item = "rtprio";  type = "soft"; value = "99"; }
      { domain = "@anka-gamemode";    item = "nice";    type = "soft"; value = "-15"; }
      { domain = "@anka-gamemode";    item = "nice";    type = "hard"; value = "-20"; }
      { domain = "@anka-gamemode";    item = "rtprio";  type = "soft"; value = "95"; }
      { domain = "@anka-gamemode";    item = "rtprio";  type = "hard"; value = "95"; }
    ];

    users.groups.anka-gamemode = {};

    # ── NVIDIA persistence daemon (keeps the GPU initialised) ────────────────
    # NixOS' option runs the daemon of the driver actually in use.
    # (hardware.nvidia.powerManagement is owned by modules/gpu.)
    hardware.nvidia.nvidiaPersistenced = lib.mkIf (gpu.type == "nvidia" && cfg.gaming.nvidiaTweaks) true;

    # No amdgpu ppfeaturemask=0xffffffff: it unlocks overclocking, taints
    # the kernel and is known to destabilise some cards. Tools like LACT
    # document how to enable it for users who want to overclock.

    # No always-on low-latency PipeWire profile: a 64-sample quantum for
    # every app costs CPU and causes crackling on older machines; the
    # desktop default (modules/desktop) stays in effect.

    # ── Useful gaming tools ───────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      mangohud        # in-game FPS/GPU overlay
      vkbasalt        # post-processing (CAS sharpening etc.)
      gamemode        # gamemoderun CLI wrapper
    ];

  };
}