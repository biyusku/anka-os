#!/usr/bin/env python3
"""
ANKA AI D-Bus Bridge
Client library for interacting with the ANKA AI daemon via D-Bus.
Used by desktop applications, KDE plasmoids, and scripts.
"""

import dbus
import json
import logging
from typing import Any

logger = logging.getLogger("anka-dbus-bridge")

# D-Bus constants
DBUS_SERVICE = "org.anka.AI"
DBUS_PATH = "/org/anka/AI"
DBUS_INTERFACE = "org.anka.AI"


class AnkaAIBridge:
    """
    Client bridge for the ANKA AI D-Bus service.

    Usage:
        bridge = AnkaAIBridge()
        if bridge.is_connected():
            result = bridge.ask("What is NixOS?")
            print(result['response'])
    """

    def __init__(self) -> None:
        self._proxy = None
        self._bus = None
        self._connect()

    def _connect(self) -> None:
        """Connect to the ANKA AI D-Bus service."""
        try:
            self._bus = dbus.SessionBus()
            self._proxy = self._bus.get_object(DBUS_SERVICE, DBUS_PATH)
            logger.debug(f"Connected to {DBUS_SERVICE}")
        except dbus.exceptions.DBusException as e:
            logger.error(f"Failed to connect to ANKA AI service: {e}")
            self._proxy = None

    def is_connected(self) -> bool:
        """Check if connected to the ANKA AI service."""
        if self._proxy is None:
            self._connect()
        return self._proxy is not None

    def ask(self, question: str) -> dict[str, Any]:
        """
        Ask ANKA AI a question.

        Args:
            question: The question to ask

        Returns:
            dict with keys: success (bool), response (str), error (str if failed)
        """
        if not self.is_connected():
            return {
                "success": False,
                "error": "Not connected to ANKA AI service. Is anka-ai.service running?"
            }

        try:
            interface = dbus.Interface(self._proxy, DBUS_INTERFACE)
            raw_result = interface.Ask(question)
            return json.loads(str(raw_result))
        except dbus.exceptions.DBusException as e:
            logger.error(f"D-Bus error asking question: {e}")
            return {"success": False, "error": str(e)}
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON response: {e}")
            return {"success": False, "error": "Invalid response from ANKA AI"}

    def get_status(self) -> dict[str, Any]:
        """
        Get ANKA AI service status.

        Returns:
            dict with service status information
        """
        if not self.is_connected():
            return {
                "ready": False,
                "error": "Not connected to org.anka.AI service"
            }

        try:
            interface = dbus.Interface(self._proxy, DBUS_INTERFACE)
            raw_result = interface.GetStatus()
            return json.loads(str(raw_result))
        except Exception as e:
            return {"ready": False, "error": str(e)}

    def clear_history(self) -> bool:
        """Clear the conversation history."""
        if not self.is_connected():
            return False

        try:
            interface = dbus.Interface(self._proxy, DBUS_INTERFACE)
            return bool(interface.ClearHistory())
        except Exception as e:
            logger.error(f"Failed to clear history: {e}")
            return False

    def set_model(self, model_name: str) -> bool:
        """
        Change the AI model.

        Args:
            model_name: Ollama model name (e.g., "llama3.2:1b", "phi3:mini")

        Returns:
            True if model was set successfully
        """
        if not self.is_connected():
            return False

        try:
            interface = dbus.Interface(self._proxy, DBUS_INTERFACE)
            return bool(interface.SetModel(model_name))
        except Exception as e:
            logger.error(f"Failed to set model: {e}")
            return False

    def subscribe_status_changes(self, callback) -> None:
        """
        Subscribe to status change signals from ANKA AI.

        Args:
            callback: Function to call when status changes, receives status string
        """
        if not self.is_connected():
            return

        try:
            self._bus.add_signal_receiver(
                callback,
                signal_name="StatusChanged",
                dbus_interface=DBUS_INTERFACE,
                bus_name=DBUS_SERVICE,
                path=DBUS_PATH
            )
            logger.debug("Subscribed to ANKA AI status changes")
        except Exception as e:
            logger.error(f"Failed to subscribe to signals: {e}")


# Convenience functions for simple usage
def ask_anka(question: str) -> str:
    """
    Simple function to ask ANKA AI a question.

    Args:
        question: The question to ask

    Returns:
        The AI's response as a string, or an error message
    """
    bridge = AnkaAIBridge()
    result = bridge.ask(question)

    if result.get("success"):
        return result["response"]
    else:
        return f"Error: {result.get('error', 'Unknown error')}"


def get_anka_status() -> dict[str, Any]:
    """Get ANKA AI service status."""
    bridge = AnkaAIBridge()
    return bridge.get_status()


if __name__ == "__main__":
    # CLI usage: python3 dbus_bridge.py "Your question here"
    import sys

    logging.basicConfig(level=logging.WARNING)

    if len(sys.argv) < 2:
        # Show status
        status = get_anka_status()
        print("ANKA AI Status:")
        print(f"  Ready: {status.get('ready', False)}")
        print(f"  Model: {status.get('model', 'unknown')}")
        print(f"  Service: {status.get('service', DBUS_SERVICE)}")
        print(f"  Version: {status.get('version', 'unknown')}")
    else:
        question = " ".join(sys.argv[1:])
        print(f"Asking ANKA AI: {question}")
        response = ask_anka(question)
        print(f"\nANKA: {response}")