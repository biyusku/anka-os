{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.anka.ai;
  mcpCfg = config.anka.ai.mcp;
in
{
  options.anka.ai.mcp = {
    enable = mkEnableOption "ANKA MCP servers";
  };

  config = mkIf (cfg.enable && mcpCfg.enable) {
    environment.etc."anka/mcp/servers.json".text = builtins.toJSON {
      servers = {
        anka-mcp-filesystem = {
          command = "/run/current-system/sw/bin/python3";
          args = [ "/etc/anka/mcp-servers/mcp_filesystem.py" ];
          description = "ANKA filesystem access MCP server";
        };
        anka-mcp-desktop = {
          command = "/run/current-system/sw/bin/python3";
          args = [ "/etc/anka/mcp-servers/mcp_desktop.py" ];
          description = "ANKA desktop control MCP server";
        };
        anka-mcp-network = {
          command = "/run/current-system/sw/bin/python3";
          args = [ "/etc/anka/mcp-servers/mcp_network.py" ];
          description = "ANKA network management MCP server";
        };
        anka-mcp-process = {
          command = "/run/current-system/sw/bin/python3";
          args = [ "/etc/anka/mcp-servers/mcp_process.py" ];
          description = "ANKA process management MCP server";
        };
        anka-mcp-audio = {
          command = "/run/current-system/sw/bin/python3";
          args = [ "/etc/anka/mcp-servers/mcp_audio.py" ];
          description = "ANKA audio control MCP server";
        };
        anka-mcp-system = {
          command = "/run/current-system/sw/bin/python3";
          args = [ "/etc/anka/mcp-servers/mcp_system.py" ];
          description = "ANKA system management MCP server";
        };
        anka-mcp-diagnostics = {
          command = "/run/current-system/sw/bin/python3";
          args = [ "/etc/anka/mcp-servers/mcp_diagnostics.py" ];
          description = "ANKA diagnostics MCP server (read-only)";
        };
        anka-mcp-package = {
          command = "/run/current-system/sw/bin/python3";
          args = [ "/etc/anka/mcp-servers/mcp_package.py" ];
          description = "ANKA package management MCP server";
        };
      };
    };

    users.groups.anka-mcp = {};
  };
}