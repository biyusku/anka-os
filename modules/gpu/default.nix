# ANKA GPU configuration — AMD, NVIDIA, Intel driver selection
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.gpu;
in
{
  options.anka.gpu = {
    type = lib.mkOption {
      type    = lib.types.enum [ "amd" "nvidia" "intel" "intel+nvidia" "none" ];
      default = "amd";
      description = ''
        GPU type to configure.
        amd          — open-source amdgpu driver (Mesa/Radeon RX).
        nvidia       — proprietary NVIDIA driver.
        intel        — Intel integrated graphics (i915/xe).
        intel+nvidia — hybrid laptop with Intel iGPU + NVIDIA dGPU (Optimus/PRIME).
        none         — no GPU-specific configuration (VM, etc.).
      '';
    };

    nvidia = {
      package = lib.mkOption {
        type    = lib.types.enum [ "stable" "beta" "legacy_470" "legacy_390" ];
        default = "stable";
        description = "NVIDIA driver branch.";
      };

      open = lib.mkOption {
        type    = lib.types.bool;
        default = false;
        description = "Use NVIDIA open-source kernel modules (Turing+ / RTX 20+).";
      };

      modesetting = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Enable NVIDIA kernel modesetting (required for Wayland).";
      };

      prime = {
        enable = lib.mkOption {
          type    = lib.types.bool;
          default = false;
          description = "Enable NVIDIA PRIME offload (for Intel+NVIDIA hybrid laptops).";
        };
        intelBusId  = lib.mkOption { type = lib.types.str; default = "PCI:0:2:0"; description = "Intel GPU PCI bus ID."; };
        nvidiaBusId = lib.mkOption { type = lib.types.str; default = "PCI:1:0:0"; description = "NVIDIA GPU PCI bus ID."; };
      };
    };
  };

  config = lib.mkMerge [

    # ── AMD ───────────────────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "amd") {
      boot.initrd.kernelModules      = [ "amdgpu" ];
      services.xserver.videoDrivers  = [ "amdgpu" ];

      hardware.graphics = {
        enable      = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          amdvlk           # AMD Vulkan driver
          rocmPackages.clr # ROCm OpenCL (for Ollama GPU acceleration)
          libva-mesa-driver
          mesa.drivers
        ];
        extraPackages32 = with pkgs; [ driversi686Linux.amdvlk ];
      };

      # ROCm HIP for GPU compute (Ollama, etc.)
      environment.systemPackages = with pkgs; [
        radeontop       # AMD GPU monitor
        rocmPackages.rocm-smi
      ];

      environment.variables = {
        ROC_ENABLE_PRE_VEGA = "1";          # enable pre-Vega ROCm support
        HSA_OVERRIDE_GFX_VERSION = lib.mkDefault "";
      };
    })

    # ── NVIDIA ────────────────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "nvidia" || cfg.type == "intel+nvidia") {
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        modesetting.enable = cfg.nvidia.modesetting;
        open               = cfg.nvidia.open;
        nvidiaSettings     = true;   # include nvidia-settings GUI

        package = (
          if      cfg.nvidia.package == "beta"       then config.boot.kernelPackages.nvidiaPackages.beta
          else if cfg.nvidia.package == "legacy_470"  then config.boot.kernelPackages.nvidiaPackages.legacy_470
          else if cfg.nvidia.package == "legacy_390"  then config.boot.kernelPackages.nvidiaPackages.legacy_390
          else                                              config.boot.kernelPackages.nvidiaPackages.stable
        );

        prime = lib.mkIf cfg.nvidia.prime.enable {
          offload = {
            enable           = true;
            enableOffloadCmd = true;   # adds 'nvidia-offload' wrapper command
          };
          intelBusId  = cfg.nvidia.prime.intelBusId;
          nvidiaBusId = cfg.nvidia.prime.nvidiaBusId;
        };

        powerManagement.enable        = lib.mkDefault false;
        powerManagement.finegrained   = lib.mkDefault false;
      };

      hardware.graphics = {
        enable      = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          vaapiVdpau
          libvdpau-va-gl
        ];
      };

      environment.systemPackages = with pkgs; [
        nvtopPackages.nvidia   # NVIDIA GPU monitor
        cudatoolkit            # CUDA tools
      ];

      # NVIDIA Wayland environment variables
      environment.variables = {
        LIBVA_DRIVER_NAME       = "nvidia";
        GBM_BACKEND             = "nvidia-drm";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        WLR_NO_HARDWARE_CURSORS = "1";         # fix cursor on some compositors
      };
    })

    # ── Intel ─────────────────────────────────────────────────────────────
    (lib.mkIf (cfg.type == "intel" || cfg.type == "intel+nvidia") {
      boot.initrd.kernelModules = [ "i915" ];

      hardware.graphics = lib.mkIf (cfg.type == "intel") {
        enable      = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          intel-media-driver    # iHD (Broadwell+)
          intel-vaapi-driver    # i965 (older Intel)
          vaapiIntel
          intel-compute-runtime # OpenCL
        ];
      };

      environment.variables = lib.mkIf (cfg.type == "intel") {
        LIBVA_DRIVER_NAME = "iHD";
      };
    })

  ];
}