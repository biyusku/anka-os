# ANKA System Security — nftables firewall, AppArmor, fail2ban, hardening
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.security;
in
{
  options.anka.security = {
    enable = lib.mkEnableOption "ANKA system security hardening";

    firewall = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Enable nftables-based stateful firewall.";
      };

      allowedTCPPorts = lib.mkOption {
        type    = lib.types.listOf lib.types.port;
        default = [];
        example = [ 22 80 443 ];
        description = "TCP ports to allow inbound (in addition to established/related).";
      };

      allowedUDPPorts = lib.mkOption {
        type    = lib.types.listOf lib.types.port;
        default = [];
        description = "UDP ports to allow inbound.";
      };

      allowSsh = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Allow inbound SSH (port 22). Disable if you do not use SSH.";
      };

      sshPort = lib.mkOption {
        type    = lib.types.port;
        default = 22;
        description = "SSH port (also used by fail2ban).";
      };
    };

    apparmor = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Enable AppArmor mandatory access control.";
      };

      enforceMode = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = ''
          When true, AppArmor profiles run in enforcing mode.
          Set to false during initial development to use complain mode only.
        '';
      };
    };

    fail2ban = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Enable fail2ban to block SSH brute-force attacks.";
      };

      maxRetries = lib.mkOption {
        type    = lib.types.int;
        default = 5;
        description = "Number of failed SSH attempts before banning.";
      };

      bantime = lib.mkOption {
        type    = lib.types.str;
        default = "1h";
        description = "How long to ban an IP. Supports s/m/h/d suffixes.";
      };

      findtime = lib.mkOption {
        type    = lib.types.str;
        default = "10m";
        description = "Window in which maxRetries failures trigger a ban.";
      };
    };

    usbGuard = {
      enable = lib.mkOption {
        type    = lib.types.bool;
        default = false;
        description = ''
          Enable USBGuard — blocks unrecognised USB devices.
          Recommended for enterprise/kiosk deployments.
          Disabled by default (breaks desktop USB plug-and-play).
        '';
      };

      policy = lib.mkOption {
        type    = lib.types.enum [ "allow-all" "block-all" "interactive" ];
        default = "interactive";
        description = ''
          USBGuard default policy for newly attached devices.
          allow-all   — same as disabled (testing only).
          block-all   — block everything not explicitly allowed.
          interactive — prompt the user via the USBGuard daemon notify.
        '';
      };
    };

    sudo = {
      requirePassword = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Require password for sudo. Disable only for development VMs.";
      };

      wheelNeedsPassword = lib.mkOption {
        type    = lib.types.bool;
        default = true;
        description = "Require password for users in the 'wheel' group.";
      };

      timeout = lib.mkOption {
        type    = lib.types.int;
        default = 5;
        description = "sudo credential cache timeout in minutes (0 = never cache).";
      };
    };

    kernelHardening = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = "Apply kernel hardening sysctl parameters.";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── nftables firewall ─────────────────────────────────────────────────────
    networking.nftables.enable  = lib.mkIf cfg.firewall.enable true;
    networking.firewall.enable  = lib.mkIf cfg.firewall.enable true;
    networking.firewall.backend = lib.mkIf cfg.firewall.enable "nftables";

    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.firewall.enable (
        cfg.firewall.allowedTCPPorts
        ++ lib.optional cfg.firewall.allowSsh cfg.firewall.sshPort
      );

    networking.firewall.allowedUDPPorts =
      lib.mkIf cfg.firewall.enable cfg.firewall.allowedUDPPorts;

    # Log dropped packets (rate-limited to avoid log spam)
    networking.firewall.logRefusedConnections = lib.mkDefault true;
    networking.firewall.logReversePathDrops   = lib.mkDefault true;

    # ── AppArmor ──────────────────────────────────────────────────────────────
    security.apparmor = lib.mkIf cfg.apparmor.enable {
      enable   = true;
      killUnconfinedConfinables = cfg.apparmor.enforceMode;
      packages = with pkgs; [ apparmor-profiles apparmor-utils ];
    };

    # ── fail2ban ──────────────────────────────────────────────────────────────
    services.fail2ban = lib.mkIf cfg.fail2ban.enable {
      enable   = true;
      maxretry = cfg.fail2ban.maxRetries;
      bantime  = cfg.fail2ban.bantime;
      findtime = cfg.fail2ban.findtime;

      jails = {
        sshd = {
          settings = {
            enabled  = true;
            port     = toString cfg.firewall.sshPort;
            filter   = "sshd";
            logpath  = "/var/log/auth.log %(journalmatch)s";
            maxretry = cfg.fail2ban.maxRetries;
            bantime  = cfg.fail2ban.bantime;
          };
        };
      };
    };

    # ── USBGuard ──────────────────────────────────────────────────────────────
    services.usbguard = lib.mkIf cfg.usbGuard.enable {
      enable              = true;
      implicitPolicyTarget = cfg.usbGuard.policy;
      # Rule file generated by: usbguard generate-policy > /etc/usbguard/rules.conf
      # after plugging in all trusted devices.
      rules               = lib.mkDefault "allow with-interface equals { 03:00:00 03:01:00 }"; # keyboard/mouse
    };

    # ── sudo configuration ────────────────────────────────────────────────────
    security.sudo = {
      enable      = true;
      extraConfig = ''
        Defaults timestamp_timeout=${toString cfg.sudo.timeout}
        Defaults !visiblepw
        Defaults always_set_home
        Defaults match_group_by_gid
        ${lib.optionalString (!cfg.sudo.requirePassword) "Defaults !authenticate"}
      '';
      # Allow wheel with or without password
      extraRules = [{
        groups   = [ "wheel" ];
        commands = [{ command = "ALL"; options = lib.optional (!cfg.sudo.wheelNeedsPassword) "NOPASSWD"; }];
      }];
    };

    # ── Kernel hardening sysctl parameters ───────────────────────────────────
    boot.kernel.sysctl = lib.mkIf cfg.kernelHardening {
      # TCP SYN cookie protection
      "net.ipv4.tcp_syncookies"              = 1;

      # IP spoofing / source routing
      "net.ipv4.conf.all.rp_filter"          = 1;
      "net.ipv4.conf.default.rp_filter"      = 1;
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;

      # ICMP redirect protection
      "net.ipv4.conf.all.accept_redirects"    = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.send_redirects"       = 0;
      "net.ipv6.conf.all.accept_redirects"     = 0;

      # Log martian packets (invalid source addresses)
      "net.ipv4.conf.all.log_martians"         = 1;

      # Ignore broadcast pings (Smurf amplification)
      "net.ipv4.icmp_echo_ignore_broadcasts"   = 1;

      # Ignore bogus ICMP error responses
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

      # Disable IPv6 router advertisements if IPv6 not used
      # "net.ipv6.conf.all.accept_ra" = 0;  # Uncomment if no IPv6 RA needed

      # Kernel pointers hidden from unprivileged users
      "kernel.kptr_restrict"                   = 2;

      # Restrict dmesg to root
      "kernel.dmesg_restrict"                  = 1;

      # Restrict perf to root
      "kernel.perf_event_paranoid"             = 3;

      # Disable core dumps for setuid binaries
      "fs.suid_dumpable"                       = 0;

      # Protect against PTRACE from unprivileged processes
      "kernel.yama.ptrace_scope"               = 1;

      # Randomize virtual address space (ASLR)
      "kernel.randomize_va_space"              = 2;
    };

    # ── Boot hardening ────────────────────────────────────────────────────────
    boot.kernelParams = lib.mkIf cfg.kernelHardening [
      "page_alloc.shuffle=1"       # randomise page allocator freelist
      "pti=on"                     # Kernel Page Table Isolation (Meltdown)
      "vsyscall=none"              # disable legacy vsyscall (attack surface)
      "debugfs=off"                # hide kernel debug interfaces
    ];

    # ── Audit daemon (optional — needed for enterprise compliance) ────────────
    # security.auditd.enable = true;
    # security.audit.enable  = true;

    # ── SSH hardening (when allowSsh = true) ──────────────────────────────────
    services.openssh = lib.mkIf cfg.firewall.allowSsh {
      enable    = lib.mkDefault true;
      settings  = {
        PermitRootLogin                = "no";
        PasswordAuthentication         = lib.mkDefault false;
        KbdInteractiveAuthentication   = false;
        X11Forwarding                  = false;
        AllowAgentForwarding           = false;
        AllowTcpForwarding             = "no";
        MaxAuthTries                   = 3;
        LoginGraceTime                 = 30;
        ClientAliveInterval            = 300;
        ClientAliveCountMax            = 2;
        Ciphers                        = "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com";
        MACs                           = "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com";
        KexAlgorithms                  = "curve25519-sha256,curve25519-sha256@libssh.org";
      };
      ports = [ cfg.firewall.sshPort ];
    };

    # ── Polkit — least privilege GUI auth ─────────────────────────────────────
    security.polkit.enable = true;

    # ── Security packages ─────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      apparmor-utils
      lynis         # security auditing tool
      chkrootkit    # rootkit detector
      rkhunter      # rootkit hunter
    ];

  };
}