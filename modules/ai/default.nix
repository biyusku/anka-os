{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.anka.ai;
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
    ];

    environment.etc."anka/dbus/org.anka.AI.conf".text = ''
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

    environment.sessionVariables = {
      ANKA_AI_PORT = toString cfg.port;
      ANKA_AI_MODEL = cfg.localModel;
      ANKA_DATA_DIR = cfg.dataDir;
    };
  };
}