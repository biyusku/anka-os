# ANKA Media Compatibility — codecs, ffmpeg, DVD/Blu-ray, VA-API, VDPAU
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.compat.media;
  gpu = config.anka.gpu;
in
{
  options.anka.compat.media = {
    enable = lib.mkEnableOption "Full media codec support (GStreamer, ffmpeg, hardware decode)";

    dvd = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Enable DVD playback (libdvdcss + libdvdread + libdvdnav).";
    };

    bluray = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = ''
        Enable Blu-ray playback (libbluray + libaacs + libbdplus).
        Note: commercial BD+ titles still require the correct AACS keys.
      '';
    };

    hardwareDecode = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Enable VA-API / VDPAU hardware-accelerated video decoding.";
    };

    vaapi = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install VA-API drivers matching the active GPU.";
    };

    vdpau = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install VDPAU (NVIDIA & AMD).";
    };

    extraPlayers = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Install mpv, VLC, and Celluloid as media players.";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── GStreamer full codec stack ────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good    # Ogg, Vorbis, Opus, WebM, FLAC
      gst_all_1.gst-plugins-bad     # RTMP, HLS, AV1, MPEG-TS
      gst_all_1.gst-plugins-ugly    # MP3, x264, MPEG-2
      gst_all_1.gst-libav           # FFmpeg bridge (catches everything else)
      gst_all_1.gst-vaapi           # Hardware decode via VA-API
    ]
    # VA-API drivers
    ++ lib.optionals (cfg.vaapi && cfg.hardwareDecode) (lib.concatLists [
      [ libva libva-utils ]
      (lib.optional (gpu.type == "intel" || gpu.type == "amd")
        intel-media-driver)
      (lib.optional (gpu.type == "amd")
        libva1)
      (lib.optional (gpu.type == "nvidia")
        nvidia-vaapi-driver)
      # Mesa OpenCL / Rusticl for VA-API on AMD
      (lib.optional (gpu.type == "amd")
        mesa)
    ])
    # VDPAU
    ++ lib.optionals (cfg.vdpau && cfg.hardwareDecode) (lib.concatLists [
      [ libvdpau ]
      (lib.optional (gpu.type == "nvidia") vdpauinfo)
      (lib.optional (gpu.type == "amd")    libvdpau-va-gl)
    ])
    # DVD
    ++ lib.optionals cfg.dvd [
      libdvdcss libdvdread libdvdnav dvdbackup
    ]
    # Blu-ray
    ++ lib.optionals cfg.bluray [
      libbluray libaacs
    ]
    # ffmpeg full build
    ++ [
      (ffmpeg-full.override {
        withCuda     = gpu.type == "nvidia";
        withVaapi    = cfg.vaapi && cfg.hardwareDecode;
        withVdpau    = cfg.vdpau && cfg.hardwareDecode;
        withRubberband = true;
        withXml2     = true;
        withZlib     = true;
        withSdl2     = true;
        withOpenal   = true;
        withPulse    = true;
      })
    ]
    # Media players
    ++ lib.optionals cfg.extraPlayers [
      mpv
      vlc
      celluloid   # GTK mpv frontend
    ];

    # ── Nixpkgs unfree packages needed ───────────────────────────────────────
    nixpkgs.config.allowUnfree = lib.mkDefault true;   # libdvdcss, NVIDIA, etc.

    # ── VA-API + VDPAU environment variables ─────────────────────────────────
    environment.variables = lib.mkMerge [
      (lib.mkIf (cfg.vaapi && cfg.hardwareDecode) (lib.mkMerge [
        { LIBVA_MESSAGING_LEVEL = "1"; }
        (lib.mkIf (gpu.type == "intel") {
          LIBVA_DRIVER_NAME = "iHD";
        })
        (lib.mkIf (gpu.type == "amd") {
          LIBVA_DRIVER_NAME = "radeonsi";
        })
        (lib.mkIf (gpu.type == "nvidia") {
          LIBVA_DRIVER_NAME              = "nvidia";
          __EGL_VENDOR_LIBRARY_FILENAMES = "${pkgs.mesa.drivers}/share/glvnd/egl_vendor.d/50_mesa.json";
        })
      ]))
      (lib.mkIf (cfg.vdpau && cfg.hardwareDecode) (lib.mkMerge [
        (lib.mkIf (gpu.type == "nvidia") {
          VDPAU_DRIVER = "nvidia";
        })
        (lib.mkIf (gpu.type == "amd" || gpu.type == "intel") {
          VDPAU_DRIVER = "va_gl";
        })
      ]))
    ];

    # ── DVD/Blu-ray kernel module ─────────────────────────────────────────────
    boot.kernelModules = lib.mkIf (cfg.dvd || cfg.bluray) [ "sg" ];

    # ── mpv config drop-in (hardware decode) ─────────────────────────────────
    environment.etc."mpv/mpv.conf".text = lib.mkIf (cfg.extraPlayers && cfg.hardwareDecode) ''
      # ANKA: hardware video decode
      hwdec=auto-safe
      hwdec-codecs=all
      vo=gpu-next
      gpu-api=vulkan
      profile=fast
    '';

  };
}