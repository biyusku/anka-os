# ANKA Adobe compatibility layer — Premiere Pro, After Effects, Photoshop via Wine
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.adobe;
  gpu = config.anka.gpu;

  # Setup script: creates a dedicated Wine prefix for Adobe apps
  adobeSetupScript = pkgs.writeShellScriptBin "anka-adobe-setup" ''
    set -euo pipefail

    ADOBE_PREFIX="''${ADOBE_PREFIX:-$HOME/.wine-adobe}"
    export WINEPREFIX="$ADOBE_PREFIX"
    export WINEARCH=win64
    export WINE="${pkgs.wine-staging}/bin/wine"
    export WINESERVER="${pkgs.wine-staging}/bin/wineserver"

    echo "[ANKA] Adobe Wine prefix: $ADOBE_PREFIX"

    # ── DXVK + VKD3D-Proton setup ────────────────────────────────────────────
    echo "[ANKA] Installing DXVK..."
    ${pkgs.dxvk}/bin/setup_dxvk.sh install --symlink

    echo "[ANKA] Installing VKD3D-Proton..."
    ${pkgs.vkd3d-proton}/bin/setup_vkd3d_proton.sh install --symlink

    # ── Required DLLs for Creative Cloud + Premiere ───────────────────────────
    echo "[ANKA] Installing required Windows DLLs via winetricks..."
    ${pkgs.winetricks}/bin/winetricks -q \
      win10          \
      msxml3         \
      msxml6         \
      vcrun2019      \
      vcrun2022      \
      d3dcompiler_47 \
      corefonts

    # ── DLL overrides for DXVK / VKD3D ───────────────────────────────────────
    "$WINE" reg add \
      'HKCU\Software\Wine\DllOverrides' \
      /v d3d11 /t REG_SZ /d native /f
    "$WINE" reg add \
      'HKCU\Software\Wine\DllOverrides' \
      /v d3d12 /t REG_SZ /d native /f
    "$WINE" reg add \
      'HKCU\Software\Wine\DllOverrides' \
      /v dxgi   /t REG_SZ /d native /f

    echo ""
    echo "[ANKA] Prefix hazır: $ADOBE_PREFIX"
    echo "[ANKA] Creative Cloud yüklemek için:"
    echo "  WINEPREFIX=$ADOBE_PREFIX anka-adobe-run ~/Downloads/CreativeCloudSetup.exe"
    echo ""
    echo "[ANKA] Not: Adobe CC installer'ı https://creativecloud.adobe.com/tr/apps/download/creative-cloud adresinden indirin."
  '';

  # Wrapper: run any Adobe app in the dedicated prefix
  adobeRunScript = pkgs.writeShellScriptBin "anka-adobe-run" ''
    set -euo pipefail

    if [ $# -eq 0 ]; then
      echo "Kullanım: anka-adobe-run <program.exe> [args...]"
      exit 1
    fi

    export WINEPREFIX="''${ADOBE_PREFIX:-$HOME/.wine-adobe}"
    export WINEARCH=win64

    # ── NVIDIA CUDA/NVENC passthrough ─────────────────────────────────────────
    ${lib.optionalString (gpu.type == "nvidia" || gpu.type == "intel+nvidia") ''
      export PROTON_NVIDIA_NVCUDA=1
      export PROTON_NVIDIA_NVENC=1
      export CUDA_FAKE_LUID=1
      export __NV_PRIME_RENDER_OFFLOAD=1
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
    ''}

    # ── AMD: Vulkan compute via Mesa/RADV ─────────────────────────────────────
    ${lib.optionalString (gpu.type == "amd") ''
      export RADV_PERFTEST=gpl
      export mesa_glthread=true
    ''}

    # ── DXVK async shader compilation ────────────────────────────────────────
    export DXVK_ASYNC=1
    export DXVK_STATE_CACHE_PATH="$WINEPREFIX/dxvk_cache"

    # ── VKD3D-Proton D3D12 settings ───────────────────────────────────────────
    export VKD3D_CONFIG=dxr11,dxr
    export VKD3D_FEATURE_LEVEL=12_2

    exec ${pkgs.wine-staging}/bin/wine "$@"
  '';

  # Launcher shortcut for Premiere Pro specifically
  premiereScript = pkgs.writeShellScriptBin "premiere-pro" ''
    PREMIERE_EXE="''${ADOBE_PREFIX:-$HOME/.wine-adobe}/drive_c/Program Files/Adobe/Adobe Premiere Pro 2024/Adobe Premiere Pro.exe"
    if [ ! -f "$PREMIERE_EXE" ]; then
      echo "[ANKA] Premiere Pro kurulu değil."
      echo "       Önce 'anka-adobe-setup' çalıştırın, ardından Creative Cloud'dan Premiere Pro'yu kurun."
      exit 1
    fi
    exec anka-adobe-run "$PREMIERE_EXE" "$@"
  '';

in
{
  options.anka.adobe = {
    enable = lib.mkEnableOption "ANKA Adobe compatibility layer (Premiere Pro, Photoshop, After Effects)";

    extraDlls = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional winetricks components to install in the Adobe prefix.";
      example = [ "dotnet48" "mfc140" ];
    };

    enableNvidiaPassthrough = lib.mkOption {
      type    = lib.types.bool;
      default = (gpu.type == "nvidia" || gpu.type == "intel+nvidia");
      description = ''
        Enable NVIDIA CUDA/NVENC passthrough via nvidia-libs.
        Automatically enabled for NVIDIA GPU configurations.
        Requires nvidia-libs installed in the Wine prefix (see anka-adobe-setup).
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # ── System packages ───────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      # Wine stack
      wine-staging          # Wine with staging patches (best Adobe compatibility)
      winetricks            # DLL installer helper
      dxvk                  # D3D9/10/11 → Vulkan
      vkd3d-proton          # D3D12 → Vulkan (VKD3D-Proton fork)

      # Bottles: GUI Wine prefix manager (user-friendly)
      bottles

      # ANKA scripts
      adobeSetupScript
      adobeRunScript
      premiereScript

      # Font rendering (Adobe apps need these)
      liberation_ttf
      freetype

      # Video decode support
      gst_all_1.gst-plugins-bad   # extra codec support
    ]
    ++ lib.optionals cfg.enableNvidiaPassthrough [
      # nvidia-libs (CUDA/NVENC Wine passthrough) is not in nixpkgs.
      # Install manually from https://github.com/SveSop/nvidia-libs
      # or run: anka-adobe-setup --with-cuda
      # Packages below are prerequisites for building nvidia-libs:
      cudaPackages.cudatoolkit
    ];

    # ── 32-bit support (required by Wine) ─────────────────────────────────────
    hardware.graphics = {
      enable      = true;
      enable32Bit = true;
    };

    # ── Environment variables ─────────────────────────────────────────────────
    environment.variables = lib.mkMerge [
      {
        # Default Adobe prefix location
        ADOBE_PREFIX = "$HOME/.wine-adobe";
        # DXVK HUD (comment out for production, useful for debugging)
        # DXVK_HUD = "fps,frametimes,gpuload";
      }
      (lib.mkIf cfg.enableNvidiaPassthrough {
        # NVIDIA Wine CUDA passthrough
        PROTON_NVIDIA_NVCUDA = "1";
        PROTON_NVIDIA_NVENC  = "1";
        CUDA_FAKE_LUID       = "1";
      })
    ];

    # ── udev: allow GPU access from Wine ─────────────────────────────────────
    services.udev.extraRules = lib.mkIf cfg.enableNvidiaPassthrough ''
      # Allow user-space NVIDIA CUDA access for Wine apps
      KERNEL=="nvidia[0-9]*", MODE="0666"
      KERNEL=="nvidiactl",    MODE="0666"
    '';

    # ── Polkit: allow Premiere to use hardware encoder ─────────────────────────
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.policykit.exec" &&
            subject.isInGroup("video")) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}