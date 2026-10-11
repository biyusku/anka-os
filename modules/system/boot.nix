# ANKA boot configuration — systemd-boot, secure boot stub, initrd
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.boot;
in
{
  options.anka.boot = {
    loader = lib.mkOption {
      type    = lib.types.enum [ "systemd-boot" "grub" ];
      default = "systemd-boot";
      description = "Boot loader to use. systemd-boot for UEFI, grub for legacy BIOS.";
    };

    grubDevice = lib.mkOption {
      type    = lib.types.str;
      default = "/dev/sda";
      description = "Device for GRUB installation (only used when loader = grub).";
    };

    timeout = lib.mkOption {
      type    = lib.types.int;
      default = 0;
      description = ''
        Seconds the boot menu waits. 0 hides it: the computer starts ANKA
        straight away, and holding Space (or Shift/Esc with GRUB) while it
        powers on shows the menu (older versions, other systems). The
        installer sets 5 when it finds Windows on the computer.
      '';
    };

    plymouth = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Enable Plymouth graphical boot splash.";
    };
  };

  config = {
    # ── systemd-boot (UEFI default) ───────────────────────────────────────
    boot.loader.systemd-boot = lib.mkIf (cfg.loader == "systemd-boot") {
      enable       = true;
      configurationLimit = 10;          # keep last 10 generations
      editor       = false;             # disable boot entry editing (security)
      consoleMode  = "max";
    };

    boot.loader.efi.canTouchEfiVariables = lib.mkIf (cfg.loader == "systemd-boot") true;
    boot.loader.timeout = cfg.timeout;

    # ── GRUB (legacy BIOS fallback) ───────────────────────────────────────
    boot.loader.grub = lib.mkIf (cfg.loader == "grub") {
      enable  = true;
      device  = cfg.grubDevice;
      useOSProber = true;
      timeoutStyle = if cfg.timeout == 0 then "hidden" else "menu";
    };

    # ── Plymouth splash screen ────────────────────────────────────────────
    boot.plymouth = lib.mkIf cfg.plymouth {
      enable = true;
      theme  = lib.mkDefault "breeze";   # modules/branding sets "anka"
    };

    # ── initrd settings ───────────────────────────────────────────────────
    boot.initrd = {
      # Use systemd in initrd for faster boot and better service ordering
      systemd.enable = true;

      # Compress initrd with zstd for fast decompression
      compressor     = "zstd";
      compressorArgs = [ "-19" "-T0" ];

      # Always include these modules for broad hardware support
      availableKernelModules = [
        "nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod"
        "sdhci_pci"        # SD card reader
        "virtio_balloon" "virtio_blk" "virtio_pci" "virtio_scsi"  # VM support
      ];
    };

    # ── Silent boot: logo and progress bar only, no text ──────────────────
    boot.consoleLogLevel = 3;
    boot.initrd.verbose = false;
    boot.kernelParams = [
      "quiet"
      "splash"
      "loglevel=3"
      "rd.systemd.show_status=false"
      "vt.global_cursor_default=0"
      "systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];

    # ── Latest kernel (via CachyOS / chaotic-nyx in flake.nix) ───────────
    # kernel.nix selects the actual package; boot.nix just sets loader opts.
  };
}