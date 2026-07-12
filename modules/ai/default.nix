{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.anka.ai;

  # ── Python package ────────────────────────────────────────────────────────
  anka-ai-pkg = pkgs.python3Packages.buildPythonApplication {
    pname   = "anka-ai";
    version = "0.3.0";
    format  = "pyproject";

    src = ../../services/anka-ai/anka-ai;

    nativeBuildInputs = with pkgs.python3Packages; [ hatchling ];

    propagatedBuildInputs = with pkgs.python3Packages; [
      anthropic
      litellm
      fastmcp
      dasbus
      dbus-python
      pygobject3
      psutil
      faster-whisper
      pyaudio
    ];

    pythonImportsCheck = [ "daemon" ];

    meta = {
      description = "ANKA OS AI orchestration daemon";
      license     = lib.licenses.mit;
      platforms   = lib.platforms.linux;
    };
  };
in
{
  imports = [ ./mcp.nix ];

  options.anka.ai = {
    enable = mkEnableOption "ANKA AI Assistant";

    localModel = mkOption {
      type = types.str;
      default = "qwen2.5:7b";
      description = "Default Ollama model for ANKA AI";
    };

    port = mkOption {
      type = types.int;
      default = 11434;
      description = "Ollama service port";
    };

    enableVoice = mkOption {
      type = types.bool;
      default = false;
      description = "Enable voice input/output (Whisper STT + Kokoro TTS)";
    };

    whisperModel = mkOption {
      type = types.str;
      default = "base";
      description = "Whisper model size (tiny, base, small, medium, large)";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/anka-ai";
      description = "ANKA AI data directory";
    };
  };

  config = mkIf cfg.enable {
    services.ollama = {
      enable = true;
      port = cfg.port;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 anka anka-users -"
      "d ${cfg.dataDir}/models 0750 anka anka-users -"
      "d ${cfg.dataDir}/conversations 0750 anka anka-users -"
      "d /etc/anka 0755 root root -"
      "d /etc/anka/services 0755 root root -"
      "d /var/log/anka 0755 root root -"
    ];

    # ── D-Bus session policy ──────────────────────────────────────────────────
    environment.etc."dbus-1/session.d/org.anka.AI.conf".text = ''
      <!DOCTYPE busconfig PUBLIC
        "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
        "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
      <busconfig>
        <policy user="anka">
          <allow own="org.anka.AI"/>
          <allow send_destination="org.anka.AI"/>
        </policy>
        <policy context="default">
          <allow send_destination="org.anka.AI"/>
        </policy>
      </busconfig>
    '';

    # ── D-Bus session activation ──────────────────────────────────────────────
    environment.etc."dbus-1/services/org.anka.AI.service".text = ''
      [D-BUS Service]
      Name=org.anka.AI
      Exec=${anka-ai-pkg}/bin/anka-ai-daemon
      SystemdService=anka-ai.service
    '';

    # ── Systemd user service ──────────────────────────────────────────────────
    systemd.user.services.anka-ai = {
      description = "ANKA AI Daemon (D-Bus session service)";
      after    = [ "graphical-session.target" "dbus.socket" ];
      requires = [ "dbus.socket" ];
      wantedBy = [ "graphical-session.target" ];

      environment = {
        ANKA_AI_MODEL  = cfg.localModel;
        ANKA_DATA_DIR  = cfg.dataDir;
        OLLAMA_HOST    = "http://localhost:${toString cfg.port}";
        WHISPER_MODEL  = cfg.whisperModel;
      };

      serviceConfig = {
        Type             = "dbus";
        BusName          = "org.anka.AI";
        ExecStart        = "${anka-ai-pkg}/bin/anka-ai-daemon";
        Restart          = "on-failure";
        RestartSec       = "5s";
        StandardOutput   = "journal";
        StandardError    = "journal";
        SyslogIdentifier = "anka-ai";
      };
    };

    # ── Daemon available in PATH ──────────────────────────────────────────────
    environment.systemPackages = [ anka-ai-pkg ];

    environment.sessionVariables = {
      ANKA_AI_PORT  = toString cfg.port;
      ANKA_AI_MODEL = cfg.localModel;
      ANKA_DATA_DIR = cfg.dataDir;
    };
  };
}