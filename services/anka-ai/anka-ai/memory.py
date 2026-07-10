"""
AnkaMemory — SQLite-backed long-term memory with FTS5 semantic search.

Memory types:
  episodic   — specific conversation events; auto-decay after 90 days
  semantic   — extracted facts and preferences; no expiry

Preference categories tracked:
  apps, language, gaming, work_style, ai_behavior
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sqlite3
import traceback
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

log = logging.getLogger("anka.memory")

DB_PATH = Path(os.environ.get("anka_MEMORY_DB", "/var/lib/anka-ai/memory.db"))
EPISODIC_TTL_DAYS = 90
PREFERENCE_CATEGORIES = ("apps", "language", "gaming", "work_style", "ai_behavior")

EXTRACT_PROMPT_TEMPLATE = """\
Extract key facts, preferences, and memorable information from this conversation.
Return a JSON object with keys:
  "facts": [list of short fact strings]
  "preferences": {{"category": "value"}} (categories: apps, language, gaming, work_style, ai_behavior)

Conversation:
{conversation}

Return only valid JSON, nothing else."""


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

_DDL = """
CREATE TABLE IF NOT EXISTS memories (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     TEXT    NOT NULL,
    memory_type TEXT    NOT NULL CHECK(memory_type IN ('episodic', 'semantic')),
    content     TEXT    NOT NULL,
    metadata    TEXT    NOT NULL DEFAULT '{}',
    created_at  TEXT    NOT NULL,
    expires_at  TEXT
);

CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    content,
    content='memories',
    content_rowid='id'
);

CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts(rowid, content) VALUES (new.id, new.content);
END;

CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, content)
    VALUES ('delete', old.id, old.content);
END;

CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, content)
    VALUES ('delete', old.id, old.content);
    INSERT INTO memories_fts(rowid, content) VALUES (new.id, new.content);
END;

CREATE TABLE IF NOT EXISTS preferences (
    user_id   TEXT NOT NULL,
    category  TEXT NOT NULL,
    value     TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (user_id, category)
);
"""


# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------


@dataclass
class Memory:
    memory_id: int
    user_id: str
    memory_type: str
    content: str
    metadata: dict[str, Any]
    created_at: datetime
    expires_at: Optional[datetime]


# ---------------------------------------------------------------------------
# AnkaMemory
# ---------------------------------------------------------------------------


class AnkaMemory:
    """Thread-safe async wrapper around SQLite memory storage."""

    def __init__(self, db_path: Path = DB_PATH) -> None:
        self._db_path = db_path
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = asyncio.Lock()
        self._conn: Optional[sqlite3.Connection] = None

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def _get_conn(self) -> sqlite3.Connection:
        if self._conn is None:
            self._conn = sqlite3.connect(
                str(self._db_path),
                check_same_thread=False,
                timeout=10,
            )
            self._conn.row_factory = sqlite3.Row
            self._conn.execute("PRAGMA journal_mode=WAL")
            self._conn.execute("PRAGMA foreign_keys=ON")
            self._conn.executescript(_DDL)
            self._conn.commit()
        return self._conn

    def _close(self) -> None:
        if self._conn:
            self._conn.close()
            self._conn = None

    # ------------------------------------------------------------------
    # Memory extraction via LLM (best-effort)
    # ------------------------------------------------------------------

    async def _extract_memories(
        self, conversation: str
    ) -> tuple[list[str], dict[str, str]]:
        """Use Haiku to extract facts and preferences from the conversation."""
        try:
            import litellm

            prompt = EXTRACT_PROMPT_TEMPLATE.format(conversation=conversation)
            resp = await litellm.acompletion(
                model="claude-haiku-4-5-20251001",
                messages=[{"role": "user", "content": prompt}],
                max_tokens=512,
                temperature=0.0,
            )
            raw = resp.choices[0].message.content or "{}"
            parsed = json.loads(raw)
            facts: list[str] = parsed.get("facts", [])
            prefs: dict[str, str] = parsed.get("preferences", {})
            return facts, prefs
        except Exception:
            log.debug(
                "Memory extraction failed", extra={"err": traceback.format_exc()}
            )
            return [], {}

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def add(self, conversation: str, user_id: str) -> None:
        """Extract and persist memories from a completed conversation turn."""
        facts, prefs = await self._extract_memories(conversation)
        now = datetime.now(timezone.utc).isoformat()
        episodic_expires = (
            datetime.now(timezone.utc) + timedelta(days=EPISODIC_TTL_DAYS)
        ).isoformat()

        async with self._lock:
            conn = self._get_conn()
            # Save episodic memory (the raw conversation excerpt)
            conn.execute(
                "INSERT INTO memories (user_id, memory_type, content, metadata, created_at, expires_at)"
                " VALUES (?, 'episodic', ?, '{}', ?, ?)",
                (user_id, conversation[:2000], now, episodic_expires),
            )
            # Save extracted facts as semantic memories
            for fact in facts[:10]:  # cap at 10 facts per turn
                conn.execute(
                    "INSERT INTO memories (user_id, memory_type, content, metadata, created_at, expires_at)"
                    " VALUES (?, 'semantic', ?, '{}', ?, NULL)",
                    (user_id, fact, now),
                )
            # Upsert preferences
            for category, value in prefs.items():
                if category in PREFERENCE_CATEGORIES:
                    conn.execute(
                        "INSERT INTO preferences (user_id, category, value, updated_at)"
                        " VALUES (?, ?, ?, ?)"
                        " ON CONFLICT(user_id, category) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
                        (user_id, category, str(value), now),
                    )
            conn.commit()

        # Prune expired episodic memories asynchronously
        await self._prune_expired()

    async def search(
        self, query: str, user_id: str, limit: int = 5
    ) -> list[str]:
        """FTS5 full-text search over memories for this user."""
        if not query.strip():
            return []

        # Sanitise FTS5 query: keep only alphanumeric and spaces
        safe_query = re.sub(r"[^\w\s]", " ", query) if True else query
        try:
            import re as _re
            safe_query = _re.sub(r"[^\w\s]", " ", query).strip()
        except Exception:
            safe_query = query

        async with self._lock:
            conn = self._get_conn()
            try:
                rows = conn.execute(
                    """
                    SELECT m.content
                    FROM memories m
                    JOIN memories_fts fts ON fts.rowid = m.id
                    WHERE fts.content MATCH ?
                      AND m.user_id = ?
                      AND (m.expires_at IS NULL OR m.expires_at > datetime('now'))
                    ORDER BY rank
                    LIMIT ?
                    """,
                    (safe_query, user_id, limit),
                ).fetchall()
                return [row["content"] for row in rows]
            except sqlite3.OperationalError:
                log.debug("FTS search failed — returning empty list")
                return []

    async def get_preferences(self, user_id: str) -> str:
        """Return a short human-readable summary of stored preferences."""
        async with self._lock:
            conn = self._get_conn()
            rows = conn.execute(
                "SELECT category, value FROM preferences WHERE user_id = ?",
                (user_id,),
            ).fetchall()

        if not rows:
            return ""

        parts = [f"{row['category']}: {row['value']}" for row in rows]
        return "; ".join(parts)

    async def _prune_expired(self) -> None:
        """Delete episodic memories past their TTL."""
        try:
            async with self._lock:
                conn = self._get_conn()
                conn.execute(
                    "DELETE FROM memories WHERE memory_type='episodic' AND expires_at < datetime('now')"
                )
                conn.commit()
        except Exception:
            log.debug("Prune failed", extra={"err": traceback.format_exc()})

    async def clear_user(self, user_id: str) -> None:
        """Remove all memories and preferences for a user (GDPR right to erasure)."""
        async with self._lock:
            conn = self._get_conn()
            conn.execute("DELETE FROM memories WHERE user_id = ?", (user_id,))
            conn.execute("DELETE FROM preferences WHERE user_id = ?", (user_id,))
            conn.commit()
        log.info("User data erased", extra={"user_id": user_id})