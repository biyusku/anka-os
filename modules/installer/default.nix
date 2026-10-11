# ANKA OS — first-login welcome
# Runs once per user when their first Plasma session starts.
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.installer;

  firstRunWizard = pkgs.writeShellApplication {
    name = "anka-first-run";
    runtimeInputs = with pkgs; [ coreutils gnused kdePackages.kdialog ];
    text = builtins.readFile ./first-run-wizard.sh;
  };
in
{
  options.anka.installer = {
    enable = lib.mkOption {
      type        = lib.types.bool;
      default     = true;
      description = ''
        Show the ANKA welcome once per user after their first login
        (AI assistant on/off and where to find things).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ firstRunWizard ];

    # Plasma starts XDG autostart entries with the session; the script
    # itself exits at once when the user was already welcomed.
    environment.etc."xdg/autostart/anka-first-run.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=ANKA Welcome
      Comment=Welcome to ANKA OS
      Exec=${firstRunWizard}/bin/anka-first-run
      Icon=system-software-install
      Terminal=false
      NoDisplay=true
      X-KDE-autostart-phase=2
    '';

    # Built by `nix flake check` (see checks in flake.nix)
    system.build.ankaFirstRun = firstRunWizard;
  };
}
