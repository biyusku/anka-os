# anka-ai — ANKA OS AI assistant

## What runs today

```
KRunner "ai soru" ─┐
anka-ai "soru"  ───┴─D-Bus─▶  anka-ai-daemon (org.anka.AI, session bus)  ──HTTP──▶  Ollama (local model)
```

**KRunner** (Alt+Space): type `ai <question>` or `? <question>`, press Enter;
the answer opens in a small window. The daemon implements `org.kde.krunner1`
on `/krunner`; the plugin file is `share/krunner/dbusplugins/anka-ai.desktop`.

| Piece | File | Notes |
|---|---|---|
| Daemon | `daemon.py` | systemd user unit `anka-ai`, logs to the user journal |
| CLI / client | `dbus_bridge.py` | `anka-ai` (status) and `anka-ai "question"` |
| MCP servers | `mcp-servers/` | packaged as `anka-mcp-<name>` (see below) |

The daemon never blocks: if the model (`anka.ai.localModel`, default
`qwen2.5:7b`) is missing, the first question starts downloading it in the
background and the answer says so. Status queries never start a download.
`AI_MODE=none` in `~/.config/anka/setup.conf` (first-run wizard) turns the
assistant off.

### D-Bus interface

Service `org.anka.AI`, object `/org/anka/AI`, interface `org.anka.AI`:

```
Ask(question: s) → s           JSON {success, response | error, downloading}
GetStatus() → s                JSON {ready, reason, downloading, model, ...}
ClearHistory() → b
SetModel(model: s) → b         pulled on the next question if missing
signal StatusChanged(s)
```

```bash
busctl --user call org.anka.AI /org/anka/AI org.anka.AI Ask s "Merhaba"
journalctl --user -u anka-ai
```

## MCP servers

Eight stdio servers built on FastMCP 3, installed as commands and listed in
`/etc/anka/mcp/servers.json` (standard `mcpServers` format, usable from MCP
clients such as Claude Desktop or Claude Code):

| Command | Tools |
|---|---|
| `anka-mcp-filesystem` | read/write/list/search files, sandboxed to `$HOME` and `/tmp` (`~/.config/anka/mcp-roots.json`) |
| `anka-mcp-desktop` | windows, keys, screenshots, brightness (KWin) |
| `anka-mcp-network` | Wi-Fi, VPN, ping (NetworkManager) |
| `anka-mcp-process` | list / inspect / signal processes |
| `anka-mcp-audio` | volume, mute, devices (PipeWire) |
| `anka-mcp-system` | systemd services, hostname, timezone, shutdown |
| `anka-mcp-diagnostics` | logs, disks, memory, temperatures (read-only) |
| `anka-mcp-package` | search / install / remove Nix packages |

## Planned, not wired yet

`intent.py` (intent classification), `router.py` (PII-aware local/cloud
routing), `memory.py` (SQLite long-term memory), `confirmation_gate.py`
(confirm destructive actions) and `voice_pipeline.py` (Whisper / TTS) are the
next layer. Their dependencies are the `assistant` extra in `pyproject.toml`;
the daemon does not import them yet.

## Development

```bash
nix build .#checks.x86_64-linux.anka-ai    # daemon + CLI (import-checked)
nix build .#checks.x86_64-linux.anka-mcp   # MCP servers (load-checked)
ruff check --config pyproject.toml daemon.py dbus_bridge.py mcp-servers/
```
