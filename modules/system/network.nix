# ANKA network configuration — NetworkManager, mDNS, firewall defaults
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.network;
in
{
  options.anka.network = {
    manager = lib.mkOption {
      type    = lib.types.enum [ "networkmanager" "systemd-networkd" ];
      default = "networkmanager";
      description = "Network management backend. NetworkManager for desktop, systemd-networkd for servers.";
    };

    hostname = lib.mkOption {
      type    = lib.types.str;
      default = "anka";
      description = "System hostname.";
    };

    mdns = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Enable mDNS/Avahi for .local hostname resolution and service discovery.";
    };

    bluetooth = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Enable Bluetooth.";
    };

    dnssec = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = "Enable DNSSEC validation via systemd-resolved.";
    };

    dns = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "9.9.9.9" "1.0.0.1" ];
      description = "Fallback DNS servers (used when DHCP does not provide DNS).";
    };
  };

  config = {
    networking.hostName = cfg.hostname;

    # ── NetworkManager ────────────────────────────────────────────────────
    networking.networkmanager = lib.mkIf (cfg.manager == "networkmanager") {
      enable  = true;
      dns     = "systemd-resolved";    # hand DNS to resolved for caching
    };

    # ── systemd-resolved (used by both NM and networkd) ───────────────────
    services.resolved = {
      enable    = true;
      dnssec    = if cfg.dnssec then "true" else "allow-downgrade";
      fallbackDns = cfg.dns;
      # Use systemd-resolved stub for /etc/resolv.conf
      extraConfig = ''
        DNSStubListener=yes
        LLMNR=no
        MulticastDNS=${if cfg.mdns then "yes" else "no"}
      '';
    };

    # /etc/resolv.conf → systemd-resolved stub
    networking.resolvconf.enable = lib.mkDefault false;

    # ── mDNS / Avahi ─────────────────────────────────────────────────────
    services.avahi = lib.mkIf cfg.mdns {
      enable        = true;
      nssmdns4      = true;             # /etc/nsswitch.conf integration
      publish = {
        enable      = true;
        addresses   = true;
        workstation = true;
      };
    };

    # ── Bluetooth ─────────────────────────────────────────────────────────
    hardware.bluetooth = lib.mkIf cfg.bluetooth {
      enable      = true;
      powerOnBoot = true;
      settings.Policy.AutoEnable = "true";
    };
    services.blueman.enable = lib.mkIf cfg.bluetooth true;

    # ── Basic networking packages ─────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      networkmanager
      iproute2
      nmap
      wget
      curl
      dig
      traceroute
      ethtool
      wireguard-tools   # VPN
      openvpn
    ];

    # ── Firewall defaults (detailed rules in security.nix) ────────────────
    networking.firewall.enable = lib.mkDefault true;
  };
}