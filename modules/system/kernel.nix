# ANKA kernel configuration — CachyOS BORE kernel via chaotic-nyx
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.kernel;
in
{
  options.anka.kernel = {
    variant = lib.mkOption {
      type    = lib.types.enum [ "cachyos" "cachyos-bore" "cachyos-lto" "linux_zen" "linux_xanmod" "default" ];
      default = "cachyos-bore";
      description = ''
        Kernel variant to use.
        cachyos-bore — CachyOS kernel with BORE scheduler (best for desktop/gaming).
        cachyos-lto  — CachyOS with link-time optimisation (marginally faster, longer build).
        linux_zen    — Zen kernel (popular gaming kernel, in nixpkgs).
        linux_xanmod — Xanmod kernel (latency focused).
        default      — Stock NixOS kernel.
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