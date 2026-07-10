{ config, lib, pkgs, ... }:
let cfg = config.anka.plymouth;
in {
  options.anka.plymouth = {
    enable = lib.mkEnableOption "ANKA Plymouth boot splash" // { default = true; };
    theme = lib.mkOption {
      type = lib.types.str;
      default = "anka";
      description = "Plymouth theme name";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
      theme = cfg.theme;
      themePackages = [
        # ANKA özel Plymouth teması (şimdilik spinner)
        # Phase 5'te özel tasarım gelecek
        pkgs.plymouth
      ];
    };

    # Silent boot — temiz görünüm
    boot.consoleLogLevel = 0;
    boot.initrd.verbose = false;
    boot.kernelParams = [
      "quiet"
      "splash"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
  };
}