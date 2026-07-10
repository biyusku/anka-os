{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.ankaAI;
in
{
  options.services.ankaAI = {
    enable = mkEnableOption "ANKA AI Assistant";

    model = mkOption {
      type = types.str;
      default = "llama3.2:1b";
      description = "Default Ollama model for ANKA AI";
    };

    port = mkOption {
      type = types.int;
      default = 11434;
      description = "Ollama service port";
    };

    mcpEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable MCP (Model Context Protocol) servers";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/anka-ai";
      description = "ANKA AI data directory";
    };
  };

  config = mkIf cfg.enable {
    # Ollama for local AI
    services.ollama = {
      enable = true;
      port = cfg.port;
    };

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 anka anka-users -"
      "d ${cfg.dataDir}/models 0750 anka anka-users -"
      "d ${cfg.dataDir}/conversations 0750 anka anka-users -"
      "d /etc/anka 0755 root root -"
      "d /etc/anka/services 0755 root root -"
    ];

    # Copy service files
    environment.etc = {
      "anka/services/daemon.py".source = ../../services/anka-ai/daemon.py;
      "anka/services/dbus_bridge.py".source = ../../services/anka-ai/dbus_bridge.py;
      "anka/dbus/org.anka.AI.conf".text = ''
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
    };

    # Include MCP config if enabled
    imports = optionals cfg.mcpEnabled [ ./mcp.nix ];

    # Environment for ANKA AI
    environment.sessionVariables = {
      ANKA_AI_PORT = toString cfg.port;
      ANKA_AI_MODEL = cfg.model;
      ANKA_DATA_DIR = cfg.dataDir;
    };
  };
}