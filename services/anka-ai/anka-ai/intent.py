"""
IntentClassifier — two-tier intent detection.

Tier 1: keyword-based fast path (no LLM, sub-millisecond).
Tier 2: Claude Haiku structured output fallback for ambiguous queries.

Each intent carries metadata about whether an LLM is needed, which tier
should handle it, and whether the intended action is destructive.
"""

from __future__ import annotations

import json
import logging
import traceback
from dataclasses import dataclass, field
from typing import Any, Optional

log = logging.getLogger("anka.intent")

# ---------------------------------------------------------------------------
# Intent catalogue
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class IntentMeta:
    category: str
    handler: str          # module.function path for dispatcher
    requires_llm: bool
    llm_tier: str         # "local" | "cloud" | "none"
    is_destructive: bool
    description: str


INTENT_CATEGORIES: dict[str, IntentMeta] = {
    "VOLUME_CONTROL": IntentMeta(
        category="VOLUME_CONTROL",
        handler="handlers.desktop.set_volume",
        requires_llm=False,
        llm_tier="none",
        is_destructive=False,
        description="Adjust system audio volume or mute state",
    ),
    "BRIGHTNESS": IntentMeta(
        category="BRIGHTNESS",
        handler="handlers.desktop.set_brightness",
        requires_llm=False,
        llm_tier="none",
        is_destructive=False,
        description="Adjust screen brightness",
    ),
    "APP_LAUNCH": IntentMeta(
        category="APP_LAUNCH",
        handler="handlers.desktop.launch_app",
        requires_llm=False,
        llm_tier="none",
        is_destructive=False,
        description="Open or close an application",
    ),
    "FILE_OP": IntentMeta(
        category="FILE_OP",
        handler="handlers.filesystem.file_operation",
        requires_llm=True,
        llm_tier="local",
        is_destructive=True,  # could be destructive (delete/overwrite)
        description="File system read, write, move, copy, or delete",
    ),
    "SETTINGS": IntentMeta(
        category="SETTINGS",
        handler="handlers.system.change_setting",
        requires_llm=True,
        llm_tier="local",
        is_destructive=False,
        description="Modify system or application settings",
    ),
    "INFO_QUERY": IntentMeta(
        category="INFO_QUERY",
        handler="handlers.ai.answer_query",
        requires_llm=True,
        llm_tier="local",
        is_destructive=False,
        description="Answer an informational question",
    ),
    "COMPLEX_TASK": IntentMeta(
        category="COMPLEX_TASK",
        handler="handlers.ai.complex_task",
        requires_llm=True,
        llm_tier="cloud",
        is_destructive=False,
        description="Multi-step task requiring planning and reasoning",
    ),
    "MULTI_APP": IntentMeta(
        category="MULTI_APP",
        handler="handlers.desktop.multi_app_workflow",
        requires_llm=True,
        llm_tier="cloud",
        is_destructive=False,
        description="Orchestrate workflow across multiple applications",
    ),
    "PACKAGE_MGMT": IntentMeta(
        category="PACKAGE_MGMT",
        handler="handlers.system.package_management",
        requires_llm=True,
        llm_tier="local",
        is_destructive=True,
        description="Install, remove, or update Nix packages",
    ),
    "NETWORK_OP": IntentMeta(
        category="NETWORK_OP",
        handler="handlers.system.network_operation",
        requires_llm=False,
        llm_tier="none",
        is_destructive=False,
        description="Wi-Fi, VPN, or network configuration",
    ),
    "UNKNOWN": IntentMeta(
        category="UNKNOWN",
        handler="handlers.ai.answer_query",
        requires_llm=True,
        llm_tier="local",
        is_destructive=False,
        description="Could not classify intent",
    ),
}

# ---------------------------------------------------------------------------
# Keyword fast-path rules
# Rule format: (list_of_keywords, intent_category)
# First match wins.
# ---------------------------------------------------------------------------

_KEYWORD_RULES: list[tuple[list[str], str]] = [
    (["volume", "mute", "unmute", "louder", "quieter", "sound level"], "VOLUME_CONTROL"),
    (["brightness", "dim", "brighter", "screen brightness", "backlight"], "BRIGHTNESS"),
    (
        ["open ", "launch ", "start ", "run ", "close ", "quit ", "exit "],
        "APP_LAUNCH",
    ),
    (
        ["install ", "remove package", "uninstall", "nix-env", "nixos-rebuild",
         "nix profile", "update system", "upgrade"],
        "PACKAGE_MGMT",
    ),
    (
        ["wifi", "wi-fi", "connect to network", "disconnect", "vpn", "network"],
        "NETWORK_OP",
    ),
    (
        ["read file", "write file", "delete file", "move file", "copy file",
         "list files", "find file", "create file", "rename file"],
        "FILE_OP",
    ),
    (
        ["setting", "configure", "preference", "enable ", "disable "],
        "SETTINGS",
    ),
    (
        ["what is", "who is", "how does", "explain", "tell me about",
         "what are", "when did", "where is", "why does"],
        "INFO_QUERY",
    ),
    (
        ["refactor", "write a script", "create a pipeline", "automate",
         "analyse my", "analyze my", "debug this", "generate code",
         "design a", "architecture"],
        "COMPLEX_TASK",
    ),
    (
        ["while opening", "copy from", "paste to", "drag between",
         "export from", "import into", "across apps"],
        "MULTI_APP",
    ),
]


# ---------------------------------------------------------------------------
# Result type
# ---------------------------------------------------------------------------


@dataclass
class IntentResult:
    category: str
    meta: IntentMeta
    confidence: float  # 0.0–1.0
    method: str        # "keyword" | "llm" | "default"
    requires_llm: bool = field(init=False)
    llm_tier: str = field(init=False)
    is_destructive: bool = field(init=False)

    def __post_init__(self) -> None:
        self.requires_llm = self.meta.requires_llm
        self.llm_tier = self.meta.llm_tier
        self.is_destructive = self.meta.is_destructive


# ---------------------------------------------------------------------------
# Classifier
# ---------------------------------------------------------------------------


class IntentClassifier:
    """Two-tier intent classifier: fast keyword path + LLM fallback."""

    # ------------------------------------------------------------------
    # Tier 1: keyword matching
    # ------------------------------------------------------------------

    def _keyword_classify(self, text: str) -> Optional[IntentResult]:
        lower = text.lower()
        for keywords, category in _KEYWORD_RULES:
            if any(kw in lower for kw in keywords):
                meta = INTENT_CATEGORIES[category]
                return IntentResult(
                    category=category,
                    meta=meta,
                    confidence=0.85,
                    method="keyword",
                )
        return None

    # ------------------------------------------------------------------
    # Tier 2: LLM structured output (Haiku tool_use)
    # ------------------------------------------------------------------

    async def _llm_classify(self, text: str) -> IntentResult:
        try:
            import litellm

            categories_str = ", ".join(INTENT_CATEGORIES.keys())
            tool_schema: dict[str, Any] = {
                "type": "function",
                "function": {
                    "name": "classify_intent",
                    "description": "Classify the user's intent into exactly one category.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "category": {
                                "type": "string",
                                "enum": list(INTENT_CATEGORIES.keys()),
                                "description": f"One of: {categories_str}",
                            },
                            "confidence": {
                                "type": "number",
                                "description": "Confidence score 0.0 to 1.0",
                            },
                        },
                        "required": ["category", "confidence"],
                    },
                },
            }

            resp = await litellm.acompletion(
                model="claude-haiku-4-5-20251001",
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You are an intent classifier. Given a user query, "
                            "call classify_intent with the most appropriate category."
                        ),
                    },
                    {"role": "user", "content": text},
                ],
                tools=[tool_schema],
                tool_choice={"type": "function", "function": {"name": "classify_intent"}},
                max_tokens=128,
                temperature=0.0,
            )

            tool_call = resp.choices[0].message.tool_calls[0]
            args = json.loads(tool_call.function.arguments)
            category = args.get("category", "UNKNOWN")
            confidence = float(args.get("confidence", 0.6))

            if category not in INTENT_CATEGORIES:
                category = "UNKNOWN"

            meta = INTENT_CATEGORIES[category]
            return IntentResult(
                category=category,
                meta=meta,
                confidence=confidence,
                method="llm",
            )

        except Exception:
            log.warning(
                "LLM intent classification failed — using UNKNOWN",
                extra={"err": traceback.format_exc()},
            )
            meta = INTENT_CATEGORIES["UNKNOWN"]
            return IntentResult(
                category="UNKNOWN",
                meta=meta,
                confidence=0.1,
                method="default",
            )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def classify(self, text: str) -> IntentResult:
        """Classify *text* using the fast path first, with LLM fallback."""
        # Tier 1: keyword fast path
        result = self._keyword_classify(text)
        if result is not None:
            log.debug(
                "Intent classified via keywords",
                extra={"category": result.category, "confidence": result.confidence},
            )
            return result

        # Tier 2: LLM fallback
        result = await self._llm_classify(text)
        log.debug(
            "Intent classified via LLM",
            extra={
                "category": result.category,
                "confidence": result.confidence,
                "method": result.method,
            },
        )
        return result