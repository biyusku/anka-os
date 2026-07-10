"""
RequestRouter — PII detection, complexity classification, and routing decisions.

Routing hierarchy:
  PII detected  → always local
  simple query  → local
  medium query  → local-first (cloud fallback if local fails)
  complex query → cloud

PII is tokenized before any cloud call and restored in the response.
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
from dataclasses import dataclass, field
from typing import Optional

from intent import IntentResult

log = logging.getLogger("anka.router")

# ---------------------------------------------------------------------------
# PII patterns
# ---------------------------------------------------------------------------

_PII_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("SSN", re.compile(r"\b\d{3}-\d{2}-\d{4}\b")),
    ("EMAIL", re.compile(r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b")),
    (
        "PHONE",
        re.compile(
            r"\b(?:\+?1[\s\-.]?)?\(?\d{3}\)?[\s\-.]?\d{3}[\s\-.]?\d{4}\b"
        ),
    ),
    (
        "CREDIT_CARD",
        re.compile(r"\b(?:4\d{12}(?:\d{3})?|5[1-5]\d{14}|3[47]\d{13}|6(?:011|5\d{2})\d{12})\b"),
    ),
    # Passwords in key=value style
    (
        "PASSWORD",
        re.compile(
            r"\b(?:password|passwd|secret|token|api_key)\s*[:=]\s*\S+",
            re.IGNORECASE,
        ),
    ),
    # Home directory paths that could reveal username
    (
        "HOME_PATH",
        re.compile(r"/(?:home|Users)/[A-Za-z0-9_\-]+(?:/[^\s]*)?"),
    ),
    # IPv4 addresses
    (
        "IP_ADDR",
        re.compile(
            r"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"
        ),
    ),
]

# ---------------------------------------------------------------------------
# Complexity keyword lists
# ---------------------------------------------------------------------------

_SIMPLE_KEYWORDS: frozenset[str] = frozenset(
    [
        "volume", "brightness", "mute", "unmute", "open", "close", "launch",
        "time", "date", "weather", "what is", "who is", "tell me", "show me",
        "play", "pause", "stop", "next", "previous", "screenshot", "copy",
        "paste", "list", "check", "status", "ping",
    ]
)

_COMPLEX_KEYWORDS: frozenset[str] = frozenset(
    [
        "refactor", "analyse", "analyze", "explain in detail", "write a",
        "create a", "generate", "debug", "diagnose", "compare", "summarise",
        "summarize", "migrate", "configure", "setup", "install multiple",
        "script", "pipeline", "architecture", "integration", "workflow",
        "automate", "schedule",
    ]
)


# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------


@dataclass
class RoutingDecision:
    target: str  # "local" | "cloud"
    has_pii: bool = False
    complexity: str = "simple"  # "simple" | "medium" | "complex"
    estimated_tokens: int = 0
    reason: str = ""


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------


class RequestRouter:
    """Determines whether a request should be handled locally or in the cloud."""

    # ------------------------------------------------------------------
    # PII detection
    # ------------------------------------------------------------------

    def detect_pii(self, text: str) -> list[tuple[str, str]]:
        """Return list of (pii_type, matched_value) tuples found in *text*."""
        findings: list[tuple[str, str]] = []
        for pii_type, pattern in _PII_PATTERNS:
            for match in pattern.finditer(text):
                findings.append((pii_type, match.group()))
        return findings

    def has_pii(self, text: str) -> bool:
        return bool(self.detect_pii(text))

    # ------------------------------------------------------------------
    # PII tokenisation / restoration
    # ------------------------------------------------------------------

    def tokenize_pii(self, text: str) -> tuple[str, dict[str, str]]:
        """
        Replace PII values with opaque tokens.

        Returns (sanitised_text, restore_map) where restore_map maps each token
        back to the original value.
        """
        restore_map: dict[str, str] = {}
        result = text
        for pii_type, pattern in _PII_PATTERNS:
            def _replace(m: re.Match[str], pt: str = pii_type) -> str:
                original = m.group()
                token = f"[{pt}_{hashlib.sha256(original.encode()).hexdigest()[:8].upper()}]"
                restore_map[token] = original
                return token

            result = pattern.sub(_replace, result)
        return result, restore_map

    def restore_pii(self, text: str, restore_map: dict[str, str]) -> str:
        """Substitute tokens back to original PII values in the LLM response."""
        for token, original in restore_map.items():
            text = text.replace(token, original)
        return text

    # ------------------------------------------------------------------
    # Complexity classification
    # ------------------------------------------------------------------

    def classify_complexity(self, text: str) -> str:
        """Return 'simple', 'medium', or 'complex'."""
        lower = text.lower()
        # Word count heuristic
        word_count = len(lower.split())

        complex_hit = any(kw in lower for kw in _COMPLEX_KEYWORDS)
        simple_hit = any(kw in lower for kw in _SIMPLE_KEYWORDS)

        if complex_hit or word_count > 80:
            return "complex"
        if simple_hit and word_count < 20:
            return "simple"
        return "medium"

    # ------------------------------------------------------------------
    # Main routing
    # ------------------------------------------------------------------

    def route(self, text: str, intent: Optional[IntentResult] = None) -> RoutingDecision:
        """Decide where to route this request."""
        pii_found = self.has_pii(text)
        if pii_found:
            log.info("PII detected — forcing local routing")
            return RoutingDecision(
                target="local",
                has_pii=True,
                complexity="unknown",
                estimated_tokens=len(text) // 4,
                reason="PII detected",
            )

        complexity = self.classify_complexity(text)

        # Intent can override complexity
        if intent is not None:
            if intent.llm_tier == "local":
                complexity = "simple"
            elif intent.llm_tier == "cloud":
                complexity = "complex"

        target = {
            "simple": "local",
            "medium": "local",
            "complex": "cloud",
        }.get(complexity, "local")

        return RoutingDecision(
            target=target,
            has_pii=False,
            complexity=complexity,
            estimated_tokens=len(text) // 4,
            reason=f"complexity={complexity}",
        )

    # ------------------------------------------------------------------
    # Cost estimation
    # ------------------------------------------------------------------

    def estimate_cost(self, tokens: int, model: str) -> float:
        """
        Rough USD cost estimate.

        Prices as of mid-2025 (input tokens, per million):
          claude-sonnet-4-6 → $3.00
          ollama/qwen2.5:7b → $0.00 (local)
        """
        costs_per_million: dict[str, float] = {
            "claude-sonnet-4-6": 3.00,
            "claude-haiku-4-5-20251001": 0.25,
            "ollama/qwen2.5:7b": 0.00,
        }
        rate = costs_per_million.get(model, 1.00)
        return (tokens / 1_000_000) * rate