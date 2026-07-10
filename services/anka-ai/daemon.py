#!/usr/bin/env python3
"""
ANKA AI Daemon
D-Bus service providing AI capabilities to ANKA OS desktop
"""

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib
import requests
import json
import logging
import os
import signal
import sys
from pathlib import Path

# D-Bus service configuration
DBUS_SERVICE_NAME = "org.anka.AI"
DBUS_OBJECT_PATH = "/org/anka/AI"
DBUS_INTERFACE = "org.anka.AI"

# Ollama configuration
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
DEFAULT_MODEL = os.environ.get("ANKA_AI_MODEL", "llama3.2:1b")

# Data directory
DATA_DIR = Path(os.environ.get("ANKA_DATA_DIR", "/var/lib/anka-ai"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("/var/log/anka/ai-daemon.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger("anka-ai-daemon")


class AnkaAIService(dbus.service.Object):
    """
    ANKA AI D-Bus service.
    Exposes AI capabilities to desktop applications via D-Bus.
    """

    def __init__(self, bus: dbus.SessionBus, object_path: str) -> None:
        super().__init__(bus, object_path)
        self.model = DEFAULT_MODEL
        self.conversation_history: list[dict] = []
        self.is_ready = False
        self._check_ollama()
        logger.info(f"ANKA AI Service initialized on {DBUS_SERVICE_NAME}")

    def _check_ollama(self) -> None:
        """Check if Ollama is running and the model is available."""
        try:
            response = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=5)
            if response.status_code == 200:
                models = response.json().get("models", [])
                model_names = [m["name"] for m in models]

                if self.model in model_names or any(
                    m.startswith(self.model.split(":")[0]) for m in model_names
                ):
                    self.is_ready = True
                    logger.info(f"Ollama ready with model: {self.model}")
                else:
                    logger.warning(
                        f"Model {self.model} not found. Available: {model_names}"
                    )
                    self._pull_model()
        except requests.RequestException as e:
            logger.error(f"Ollama not reachable: {e}")
            self.is_ready = False

    def _pull_model(self) -> None:
        """Pull the default model if not available."""
        try:
            logger.info(f"Pulling model: {self.model}")
            response = requests.post(
                f"{OLLAMA_HOST}/api/pull",
                json={"name": self.model, "stream": False},
                timeout=300,
            )
            if response.status_code == 200:
                self.is_ready = True
                logger.info(f"Model {self.model} pulled successfully")
        except requests.RequestException as e:
            logger.error(f"Failed to pull model: {e}")

    @dbus.service.method(
        DBUS_INTERFACE,
        in_signature="s",
        out_signature="s"
    )
    def Ask(self, question: str) -> str:
        """
        Ask the AI a question. Returns the AI's response.
        D-Bus method: org.anka.AI.Ask(question) -> response
        """
        if not self.is_ready:
            return json.dumps({
                "success": False,
                "error": "ANKA AI is not ready. Ollama may not be running."
            })

        try:
            # Add user message to history
            self.conversation_history.append({
                "role": "user",
                "content": question
            })

            # System prompt for ANKA AI
            system_prompt = """You are ANKA AI, the intelligent assistant built into ANKA OS.
ANKA OS is a lightweight NixOS-based operating system designed for old/low-spec hardware.
You help users with:
- System configuration and NixOS concepts
- Troubleshooting hardware and software issues
- Using KDE Plasma desktop
- Understanding Linux concepts

Be concise, helpful, and speak in the user's language (Turkish or English).
If you don't know something, say so clearly."""

            response = requests.post(
                f"{OLLAMA_HOST}/api/chat",
                json={
                    "model": self.model,
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        *self.conversation_history,
                    ],
                    "stream": False,
                },
                timeout=60,
            )

            if response.status_code == 200:
                data = response.json()
                answer = data["message"]["content"]

                # Add AI response to history
                self.conversation_history.append({
                    "role": "assistant",
                    "content": answer
                })

                # Keep history manageable (last 20 messages)
                if len(self.conversation_history) > 20:
                    self.conversation_history = self.conversation_history[-20:]

                return json.dumps({
                    "success": True,
                    "response": answer,
                    "model": self.model
                })
            else:
                return json.dumps({
                    "success": False,
                    "error": f"Ollama error: {response.status_code}"
                })

        except requests.Timeout:
            return json.dumps({
                "success": False,
                "error": "Request timed out. The model may be loading."
            })
        except Exception as e:
            logger.error(f"Ask failed: {e}")
            return json.dumps({"success": False, "error": str(e)})

    @dbus.service.method(
        DBUS_INTERFACE,
        in_signature="",
        out_signature="s"
    )
    def GetStatus(self) -> str:
        """Get ANKA AI service status."""
        return json.dumps({
            "ready": self.is_ready,
            "model": self.model,
            "ollama_host": OLLAMA_HOST,
            "conversation_length": len(self.conversation_history),
            "version": "1.0.0",
            "service": DBUS_SERVICE_NAME
        })

    @dbus.service.method(
        DBUS_INTERFACE,
        in_signature="",
        out_signature="b"
    )
    def ClearHistory(self) -> bool:
        """Clear conversation history."""
        self.conversation_history = []
        logger.info("Conversation history cleared")
        return True

    @dbus.service.method(
        DBUS_INTERFACE,
        in_signature="s",
        out_signature="b"
    )
    def SetModel(self, model_name: str) -> bool:
        """Change the AI model."""
        self.model = model_name
        self.is_ready = False
        self._check_ollama()
        return self.is_ready

    @dbus.service.signal(DBUS_INTERFACE, signature="s")
    def StatusChanged(self, status: str) -> None:
        """Signal emitted when service status changes."""
        pass


def main() -> None:
    """Start the ANKA AI daemon."""
    # Setup GLib main loop
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    # Connect to session bus
    session_bus = dbus.SessionBus()

    # Request service name
    bus_name = dbus.service.BusName(DBUS_SERVICE_NAME, session_bus)

    # Create service object
    service = AnkaAIService(session_bus, DBUS_OBJECT_PATH)

    # Setup signal handling
    def handle_signal(signum: int, frame) -> None:
        logger.info(f"Received signal {signum}, shutting down ANKA AI daemon")
        loop.quit()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    # Start main loop
    loop = GLib.MainLoop()
    logger.info(f"ANKA AI Daemon started - listening on {DBUS_SERVICE_NAME}")

    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    finally:
        logger.info("ANKA AI Daemon stopped")


if __name__ == "__main__":
    main()