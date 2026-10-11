# ANKA kernel configuration — Zen kernel by default, CachyOS via chaotic-nyx
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.kernel;
in
{
  options.anka.kernel = {
    variant = lib.mkOption {
      type    = lib.types.enum [ "cachyos" "cachyos-bore" "cachyos-lto" "linux_zen" "linux_xanmod" "default" ];
      default = "linux_zen";
      description = ''
        Kernel variant to use.
        linux_zen    — Zen kernel, tuned for desktop/gaming (default). Prebuilt
                       on cache.nixos.org, includes sched_ext and ntsync.
        linux_xanmod — Xanmod kernel (latency focused, prebuilt).
        default      — Stock NixOS kernel (prebuilt).
        cachyos-bore — CachyOS kernel with BORE scheduler (chaotic-nyx).
        cachyos      — same as cachyos-bore.
        cachyos-lto  — same as cachyos-bore.
        The CachyOS variants are built against ANKA's nixpkgs, which no
        binary cache has: they compile the kernel (and an LLVM-22 rustc)
        on the machine, which takes hours on older hardware.
      '';
    };

    extraModules = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra kernel modules to load at boot.";
    };

    extraParams = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra kernel command-line parameters.";
    };
  };

  config = {
    # ── Kernel package selection ──────────────────────────────────────────
    boot.kernelPackages = lib.mkDefault (
      if      cfg.variant == "cachyos-bore"  then pkgs.linuxPackages_cachyos
      else if cfg.variant == "cachyos"       then pkgs.linuxPackages_cachyos
      else if cfg.variant == "cachyos-lto"   then pkgs.linuxPackages_cachyos
      else if cfg.variant == "linux_zen"     then pkgs.linuxPackages_zen
      else if cfg.variant == "linux_xanmod"  then pkgs.linuxPackages_xanmod_latest
      else                                        pkgs.linuxPackages_latest
    );

    # ── Modules always loaded ─────────────────────────────────────────────
    boot.kernelModules = [
      "kvm-intel"   # hardware virtualisation — Intel
      "kvm-amd"     # hardware virtualisation — AMD
      "tcp_bbr"     # BBR congestion control
    ] ++ cfg.extraModules;

    # ── Module parameters ─────────────────────────────────────────────────
    boot.extraModprobeConfig = ''
      # BBR + FQ for better network throughput
      options tcp_bbr enable_auto_tuning=1
    '';

    # ── BBR TCP congestion control ────────────────────────────────────────
    boot.kernel.sysctl = {
      "net.core.default_qdisc"        = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
    };

    # ── Extra kernel params ───────────────────────────────────────────────
    boot.kernelParams = cfg.extraParams;

    # ── Kernel hardening (basic — extended in security.nix) ───────────────
    security.protectKernelImage = true;
    security.allowSimultaneousMultithreading = true;  # SMT enabled for performance
  };
}