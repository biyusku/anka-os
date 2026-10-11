# ANKA OS — MCP servers
#
# Eight stdio MCP servers (FastMCP) that let an AI assistant work with the
# desktop: files (sandboxed to $HOME and /tmp), audio, network, processes,
# systemd, diagnostics, packages and windows. Each is a command,
# `anka-mcp-<name>`, and /etc/anka/mcp/servers.json lists them in the
# standard `mcpServers` format, ready for MCP clients such as Claude Desktop
# or Claude Code.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.anka.ai;
  mcpCfg = config.anka.ai.mcp;

  servers = {
    filesystem  = "File read/write, sandboxed to the home directory and /tmp";
    desktop     = "KWin/KDE windows, keyboard, screenshots, brightness";
    network     = "NetworkManager Wi-Fi and VPN";
    process     = "Process listing and termination";
    audio       = "PipeWire/PulseAudio volume, mute and devices";
    system      = "systemd services, hostname, timezone, shutdown";
    diagnostics = "Read-only system diagnostics";
    package     = "Nix package management";
  };

  python = pkgs.python3.withPackages (ps: with ps; [ fastmcp psutil dbus-python ]);

  anka-mcp-servers = pkgs.runCommand "anka-mcp-servers" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
    src = ../../services/anka-ai/anka-ai/mcp-servers;
  } ''
    mkdir -p $out/share/anka/mcp-servers $out/bin
    cp $src/mcp_*.py $out/share/anka/mcp-servers/
    ${concatStrings (mapAttrsToList (name: _: ''
      makeWrapper ${python}/bin/python3 $out/bin/anka-mcp-${name} \
        --add-flags $out/share/anka/mcp-servers/mcp_${name}.py
    '') servers)}

    # Every server must at least load (catches FastMCP API changes).
    for server in $out/share/anka/mcp-servers/mcp_*.py; do
      HOME=$TMPDIR ${python}/bin/python3 -c \
        "import runpy, sys; runpy.run_path(sys.argv[1], run_name='check')" "$server"
    done
  '';
in
{
  options.anka.ai.mcp = {
    enable = mkEnableOption "ANKA MCP servers";
  };

  config = mkIf (cfg.enable && mcpCfg.enable) {
    environment.systemPackages = [ anka-mcp-servers ];

    environment.etc."anka/mcp/servers.json".text = builtins.toJSON {
      mcpServers = mapAttrs' (name: description: nameValuePair "anka-${name}" {
        command = "${anka-mcp-servers}/bin/anka-mcp-${name}";
        args = [ ];
        inherit description;
      }) servers;
    };

    users.groups.anka-mcp = {};

    # Built by `nix flake check` (see checks in flake.nix)
    system.build.ankaMcpServers = anka-mcp-servers;
  };
}
