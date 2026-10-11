#!/usr/bin/env python3
"""
ANKA AI Daemon
D-Bus session service (org.anka.AI) that answers questions with a local
Ollama model.

- Logs to stderr, which the systemd user unit sends to the journal.
- Never blocks on start-up: a missing model is pulled in the background the
  first time someone asks, and Ask() reports progress until it is ready.
- Respects the first-run wizard: AI_MODE=none in ~/.config/anka/setup.conf
  turns the assistant off.
"""

import json
import logging
import os
import signal
import threading
from pathlib import Path

import dbus
import dbus.mainloop.glib
import dbus.service
import requests
from gi.repository import GLib

DBUS_SERVICE_NAME = "org.anka.AI"
DBUS_OBJECT_PATH = "/org/anka/AI"
DBUS_INTERFACE = "org.anka.AI"

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
DEFAULT_MODEL = os.environ.get("ANKA_AI_MODEL", "qwen2.5:7b")
SETUP_CONF = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "anka" / "setup.conf"
MAX_HISTORY = 20

SYSTEM_PROMPT = """You are ANKA AI, the assistant built into ANKA OS.
ANKA OS is a NixOS-based desktop operating system that aims to be as simple
as macOS, as compatible as Windows and as light as Linux.
You help users with:
- using the KDE Plasma desktop and their apps
- games and Windows programs (Steam, Proton, Bottles)
- troubleshooting hardware and software problems
- system settings and NixOS concepts

Be concise and helpful, and answer in the user's language (Turkish or English).
If you don't know something, say so clearly."""

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("anka-ai-daemon")


def read_ai_mode(path=SETUP_CONF):
    """AI_MODE chosen in the first-run wizard: "local", "cloud", "none" or None."""
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            key, _, value = line.partition("=")
            if key.strip() == "AI_MODE":
                return value.strip()
    except OSError:
        pass
    return None


def model_available(model, names):
    """Is *model* among the installed Ollama model *names*? ("qwen2.5" matches "qwen2.5:latest")."""
    wanted = model if ":" in model else model + ":latest"
    return wanted in names


class ModelManager:
    """Tracks whether the model is installed and pulls it in the background."""

    def __init__(self, model):
        self.model = model
        self.pulling = False
        self.pull_error = None
        self._lock = threading.Lock()

    def installed(self):
        response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=5)
        response.raise_for_status()
        names = [m["name"] for m in response.json().get("models", [])]
        return model_available(self.model, names)

    def ensure_pulling(self):
        with self._lock:
            if self.pulling:
                return
            self.pulling = True
            self.pull_error = None
        threading.Thread(target=self._pull, args=(self.model,), daemon=True).start()

    def _pull(self, model):
        logger.info("Pulling model %s", model)
        try:
            response = requests.post(
                f"{OLLAMA_HOST}/api/pull", json={"model": model, "stream": False}, timeout=None
            )
            response.raise_for_status()
            logger.info("Model %s is ready", model)
        except requests.RequestException as e:
            logger.error("Pulling %s failed: %s", model, e)
            self.pull_error = str(e)
        finally:
            with self._lock:
                self.pulling = False


class AnkaAIService(dbus.service.Object):
    """org.anka.AI — AI capabilities for desktop applications."""

    def __init__(self, bus, object_path):
        super().__init__(bus, object_path)
        self.models = ModelManager(DEFAULT_MODEL)
        self.conversation_history = []
        logger.info("ANKA AI ready on %s (model %s)", DBUS_SERVICE_NAME, DEFAULT_MODEL)

    def _not_ready_reason(self, start_download):
        """None when a question can be answered, otherwise a message for the user.

        Only a question (start_download=True) starts downloading a missing model,
        never a status query.
        """
        if read_ai_mode() == "none":
            return "ANKA AI is turned off. Turn it on again in ~/.config/anka/setup.conf (AI_MODE=local)."
        try:
            if self.models.installed():
                return None
        except requests.RequestException as e:
            logger.error("Ollama not reachable: %s", e)
            return "ANKA AI can't reach Ollama. Is ollama.service running?"
        if self.models.pull_error:
            return f"Downloading {self.models.model} failed: {self.models.pull_error}"
        if start_download:
            self.models.ensure_pulling()
        if self.models.pulling:
            return f"ANKA AI is downloading its model ({self.models.model}). Try again in a few minutes."
        return f"The model ({self.models.model}) is downloaded the first time you ask a question."

    @dbus.service.method(DBUS_INTERFACE, in_signature="s", out_signature="s")
    def Ask(self, question):
        """org.anka.AI.Ask(question) -> JSON {success, response | error}"""
        reason = self._not_ready_reason(start_download=True)
        if reason:
            return json.dumps({"success": False, "error": reason, "downloading": self.models.pulling})

        self.conversation_history.append({"role": "user", "content": question})
        try:
            response = requests.post(
                f"{OLLAMA_HOST}/api/chat",
                json={
                    "model": self.models.model,
                    "messages": [{"role": "system", "content": SYSTEM_PROMPT}, *self.conversation_history],
                    "stream": False,
                },
                timeout=300,
            )
            response.raise_for_status()
            answer = response.json()["message"]["content"]
        except (requests.RequestException, KeyError, ValueError) as e:
            self.conversation_history.pop()
            logger.error("Ask failed: %s", e)
            return json.dumps({"success": False, "error": f"Ollama error: {e}"})

        self.conversation_history.append({"role": "assistant", "content": answer})
        self.conversation_history = self.conversation_history[-MAX_HISTORY:]
        return json.dumps({"success": True, "response": answer, "model": self.models.model})

    @dbus.service.method(DBUS_INTERFACE, in_signature="", out_signature="s")
    def GetStatus(self):
        """Service status as JSON."""
        reason = self._not_ready_reason(start_download=False)
        return json.dumps({
            "ready": reason is None,
            "reason": reason,
            "downloading": self.models.pulling,
            "model": self.models.model,
            "ollama_host": OLLAMA_HOST,
            "conversation_length": len(self.conversation_history),
            "service": DBUS_SERVICE_NAME,
        })

    @dbus.service.method(DBUS_INTERFACE, in_signature="", out_signature="b")
    def ClearHistory(self):
        self.conversation_history = []
        logger.info("Conversation history cleared")
        return True

    @dbus.service.method(DBUS_INTERFACE, in_signature="s", out_signature="b")
    def SetModel(self, model_name):
        """Switch to another Ollama model; it is pulled on the next question if missing."""
        self.models = ModelManager(model_name)
        self.conversation_history = []
        self.StatusChanged(json.dumps({"model": model_name}))
        return True

    @dbus.service.signal(DBUS_INTERFACE, signature="s")
    def StatusChanged(self, status):
        """Emitted when the service status changes."""


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    session_bus = dbus.SessionBus()
    # Keep references: the bus name and object live as long as the loop.
    bus_name = dbus.service.BusName(DBUS_SERVICE_NAME, session_bus)
    service = AnkaAIService(session_bus, DBUS_OBJECT_PATH)

    loop = GLib.MainLoop()

    def handle_signal(signum, _frame):
        logger.info("Received signal %s, shutting down", signum)
        loop.quit()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    try:
        loop.run()
    finally:
        del service, bus_name
        logger.info("ANKA AI daemon stopped")


if __name__ == "__main__":
    main()
