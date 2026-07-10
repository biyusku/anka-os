{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.ankaAI;
in
{
  # MCP (Model Context Protocol) servers for ANKA AI
  # These extend AI capabilities with system access

  config = mkIf (cfg.enable && cfg.mcpEnabled) {

    # MCP server configurations
    environment.etc."anka/mcp/servers.json".text = builtins.toJSON {
      servers = {
        anka-mcp-filesystem = {
          command = "${pkgs.nodejs}/bin/npx";
          args = [ "-y" "@modelcontextprotocol/server-filesystem" "/home/anka" ];
          description = "ANKA filesystem access MCP server";
        };

        anka-mcp-desktop = {
          command = "${pkgs.python3}/bin/python3";
          args = [ "/etc/anka/mcp/desktop_server.py" ];
          description = "ANKA desktop interaction MCP server";
          env = {
            DISPLAY = ":0";
            ANKA_MCP_MODE = "desktop";
          };
        };

        anka-mcp-system = {
          command = "${pkgs.python3}/bin/python3";
          args = [ "/etc/anka/mcp/system_server.py" ];
          description = "ANKA system information MCP server";
          env = {
            ANKA_MCP_MODE = "system";
          };
        };
      };

      # MCP global settings
      settings = {
        timeout = 30;
        max_concurrent = 3;
        log_level = "info";
        log_file = "/var/log/anka/mcp.log";
      };
    };

    # Log directory for MCP
    systemd.tmpfiles.rules = [
      "d /var/log/anka 0755 anka anka-users -"
      "d /etc/anka/mcp 0755 root root -"
    ];

    # MCP desktop server script
    environment.etc."anka/mcp/desktop_server.py".text = ''
      #!/usr/bin/env python3
      """ANKA MCP Desktop Server - Provides desktop interaction capabilities"""

      import json
      import sys
      import subprocess
      import os

      ANKA_VERSION = os.environ.get('ANKA_VERSION', '1.0.0')

      def handle_request(request):
          method = request.get('method', '')

          if method == 'tools/list':
              return {
                  'tools': [
                      {
                          'name': 'take_screenshot',
                          'description': 'Take a screenshot of the desktop',
                          'inputSchema': {'type': 'object', 'properties': {}}
                      },
                      {
                          'name': 'open_application',
                          'description': 'Open an application by name',
                          'inputSchema': {
                              'type': 'object',
                              'properties': {
                                  'name': {'type': 'string', 'description': 'Application name'}
                              },
                              'required': ['name']
                          }
                      }
                  ]
              }

          elif method == 'tools/call':
              tool_name = request.get('params', {}).get('name', '')
              args = request.get('params', {}).get('arguments', {})

              if tool_name == 'take_screenshot':
                  result = subprocess.run(
                      ['scrot', '/tmp/anka-screenshot.png'],
                      capture_output=True, text=True
                  )
                  return {'content': [{'type': 'text', 'text': 'Screenshot saved to /tmp/anka-screenshot.png'}]}

              elif tool_name == 'open_application':
                  app = args.get('name', '')
                  subprocess.Popen([app], start_new_session=True)
                  return {'content': [{'type': 'text', 'text': f'Opened {app}'}]}

          return {'error': {'code': -32601, 'message': 'Method not found'}}

      # MCP stdio loop
      for line in sys.stdin:
          try:
              request = json.loads(line.strip())
              response = handle_request(request)
              response['id'] = request.get('id')
              print(json.dumps(response), flush=True)
          except Exception as e:
              print(json.dumps({'error': str(e), 'id': None}), flush=True)
    '';
  };
}