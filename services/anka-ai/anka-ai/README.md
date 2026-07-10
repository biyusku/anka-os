# anka-ai — Phase 3B AI Layer

Core AI orchestration daemon and MCP server suite for ANKA OS (NixOS).

## What it does

The daemon receives natural language queries over a Unix socket
(`/run/anka-ai/daemon.sock`), classifies intent, routes to the right model,
and returns structured responses. It also registers on the session D-Bus as
`org.anka.AI` for desktop integration.

```
Query → IntentClassifier → RequestRouter → LiteLLM (local/cloud) → Response
                                         ↘ MCP tools (via FastMCP servers)
```

## Architecture

| Component | File | Role |
|---|---|---|
| Daemon | `daemon.py` | asyncio server, conversation manager, orchestrator |
| Router | `router.py` | PII detection, complexity classification, routing |
| Memory | `memory.py` | SQLite FTS5 long-term memory |
| Intent | `intent.py` | Two-tier intent classifier (keywords + Haiku) |
| D-Bus bridge | `dbus_bridge.py` | org.anka.AI D-Bus service |
| Confirmation gate | `confirmation_gate.py` | Pre-action confirmation + snapshotting |
| Voice pipeline | `voice_pipeline.py` | faster-whisper STT + Kokoro/espeak TTS |

## MCP Servers

Each server runs as a sandboxed FastMCP process under its own systemd DynamicUser.

| Server | Port | Description |
|---|---|---|
| `mcp_filesystem.py` | 11500 | File read/write with path sandboxing |
| `mcp_desktop.py` | 11501 | KWin/KDE desktop control |
| `mcp_network.py` | 11502 | NetworkManager Wi-Fi/VPN |
| `mcp_process.py` | 11503 | Process listing and termination |
| `mcp_audio.py` | 11504 | PipeWire/PulseAudio audio control |
| `mcp_system.py` | 11505 | Systemd service management |
| `mcp_diagnostics.py` | 11506 | Read-only system diagnostics |
| `mcp_package.py` | 11507 | Nix package management |

## Routing Logic

```
Request
  ↓
PII detected? → YES → local (Ollama qwen2.5:7b)
  ↓ NO
complexity = simple/medium → local
complexity = complex       → cloud (claude-sonnet-4-6)
```

PII patterns: SSN, email, phone, credit card, passwords, home directory paths.

## D-Bus Interface

Service: `org.anka.AI` — object path `/org/anka/AI`

```
ProcessQuery(query: str, context: str) → str  (JSON response)
GetStatus()                             → str  (JSON stats)
SetUserPreference(key: str, val: str)   → bool
GetConversationSummary()                → str
Shutdown()                              → void
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | — | Required for cloud routing |
| `anka_WHISPER_MODEL` | `base` | Whisper model size |
| `anka_WHISPER_DEVICE` | `auto` | `cpu`, `cuda`, or `auto` |
| `anka_KOKORO_URL` | `http://127.0.0.1:5002` | Kokoro TTS server URL |
| `anka_MEMORY_DB` | `/var/lib/anka-ai/memory.db` | SQLite memory path |

## Running

The daemon is managed by `systemd.services.anka-ai-daemon` defined in
`modules/ai/default.nix`. To run manually for development:

```bash
cd services/anka-ai
pip install -e ".[dev]"
export ANTHROPIC_API_KEY=sk-ant-...
python daemon.py
```