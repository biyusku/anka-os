# ANKA OS — First-run setup wizard module
# Runs once after the user's first login to guide initial configuration.
{ config, lib, pkgs, ... }:

let
  cfg = config.anka.installer;

  # Bundle the wizard script as a derivation so it lands in the store
  firstRunWizard = pkgs.writeScriptBin "anka-first-run" (
    builtins.readFile ./first-run-wizard.sh
  );

in
{
  # ── Option declaration ────────────────────────────────────────────────────
  options.anka.installer = {
    enable = lib.mkOption {
      type        = lib.types.bool;
      default     = true;
      description = ''
        Enable the ANKA first-run setup wizard.
        The wizard runs once per user after the first login and guides
        the user through language, use-case, and AI assistant configuration.
      '';
    };
  };

  # ── Configuration ─────────────────────────────────────────────────────────
  config = lib.mkIf cfg.enable {

    # Make the wizard script available system-wide
    environment.systemPackages = [
      firstRunWizard
      pkgs.kdialog   # Qt dialog toolkit used by the wizard
    ];

    # ── Systemd user service ────────────────────────────────────────────────
    # This service is enabled per-user via the home-manager module or by
    # placing the .service file in ~/.config/systemd/user/. We ship it as
    # a system-wide template so any user who logs in gets it.
    systemd.user.services.anka-first-run = {
      description = "ANKA OS First-Run Setup Wizard";

      # Run after the graphical session is ready
      after    = [ "graphical-session.target" ];
      requires = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      serviceConfig = {
        Type            = "oneshot";
        ExecStart       = "${firstRunWizard}/bin/anka-first-run";
        RemainAfterExit = false;

        # Only run if the sentinel file does not yet exist
        ExecCondition = pkgs.writeShellScript "anka-check-setup" ''
          test ! -f "$HOME/.anka-setup-done"
        '';

        # Restart policy: never restart automatically
        Restart    = "no";

        # Give the desktop time to settle before showing dialogs
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      };

      # Run in the graphical environment so kdialog can reach the display
      environment = {
        DISPLAY     = ":0";
        WAYLAND_DISPLAY = "wayland-0";
        XDG_RUNTIME_DIR = "/run/user/%U";
      };
    };

    # ── KDE Autostart shortcut ──────────────────────────────────────────────
    # Plasma reads ~/.config/autostart/ — we ship the .desktop file into the
    # system-wide XDG autostart directory so Plasma picks it up automatically.
    environment.etc."xdg/autostart/anka-first-run.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=ANKA First-Run Setup
      Comment=Configure ANKA OS on first login
      Exec=${firstRunWizard}/bin/anka-first-run
      Terminal=false
      Hidden=false
      X-GNOME-Autostart-enabled=true
      X-KDE-autostart-condition=anka-first-run:General:Completed:false
    '';
  };
}