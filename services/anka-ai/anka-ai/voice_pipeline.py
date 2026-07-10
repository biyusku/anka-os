"""
Voice pipeline — STT (faster-whisper) + TTS (Kokoro / espeak fallback).

Speech-to-text: faster_whisper_stt() transcribes raw audio bytes.
Text-to-speech: kokoro_tts() synthesises speech; falls back to espeak-ng.
Recording:      record_until_silence() captures microphone input via PyAudio.
"""

from __future__ import annotations

import io
import logging
import os
import subprocess
import tempfile
import traceback
from typing import Optional

log = logging.getLogger("anka.voice")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

WHISPER_MODEL_SIZE = os.environ.get("anka_WHISPER_MODEL", "base")
WHISPER_DEVICE = os.environ.get("anka_WHISPER_DEVICE", "auto")  # "cpu", "cuda", "auto"
KOKORO_API_URL = os.environ.get("anka_KOKORO_URL", "http://127.0.0.1:5002")
SAMPLE_RATE = 16_000  # Hz — Whisper expects 16 kHz mono
CHANNELS = 1
CHUNK_SIZE = 1024  # PyAudio frames per chunk

# ---------------------------------------------------------------------------
# STT — faster-whisper
# ---------------------------------------------------------------------------

_whisper_model: Optional[object] = None


def _load_whisper() -> object:
    global _whisper_model
    if _whisper_model is None:
        try:
            from faster_whisper import WhisperModel  # type: ignore[import]

            device = WHISPER_DEVICE
            if device == "auto":
                # Use CUDA if available, else CPU
                try:
                    import torch  # type: ignore[import]
                    device = "cuda" if torch.cuda.is_available() else "cpu"
                except ImportError:
                    device = "cpu"

            compute_type = "float16" if device == "cuda" else "int8"
            _whisper_model = WhisperModel(
                WHISPER_MODEL_SIZE,
                device=device,
                compute_type=compute_type,
            )
            log.info(
                "Whisper model loaded",
                extra={"model": WHISPER_MODEL_SIZE, "device": device},
            )
        except ImportError:
            log.warning("faster-whisper not installed — STT unavailable")
            raise
    return _whisper_model


def faster_whisper_stt(audio_bytes: bytes, language: Optional[str] = None) -> str:
    """
    Transcribe audio bytes to text using faster-whisper.

    Args:
        audio_bytes: Raw audio data — must be 16 kHz mono PCM (WAV or raw).
        language:    Optional ISO-639-1 language code (e.g. 'en', 'tr').
                     None triggers auto-detection.

    Returns:
        Transcribed text string (stripped).
    """
    model = _load_whisper()

    # Write to a temp WAV if bytes are raw PCM; faster-whisper accepts WAV path
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = tmp.name
        tmp.write(audio_bytes)

    try:
        segments, _info = model.transcribe(  # type: ignore[union-attr]
            tmp_path,
            language=language,
            beam_size=5,
            vad_filter=True,  # skip silence
        )
        text = " ".join(seg.text.strip() for seg in segments).strip()
        log.info("STT completed", extra={"chars": len(text)})
        return text
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# TTS — Kokoro / espeak fallback
# ---------------------------------------------------------------------------


def kokoro_tts(text: str, voice: str = "en-us", speed: float = 1.0) -> bytes:
    """
    Synthesise speech from text using Kokoro TTS server.

    Falls back to espeak-ng if Kokoro is unavailable.

    Args:
        text:  Text to speak.
        voice: Voice identifier (Kokoro voice name or espeak voice code).
        speed: Speaking rate multiplier (0.5 – 2.0).

    Returns:
        WAV audio bytes.
    """
    # Try Kokoro HTTP server first
    try:
        import urllib.request
        import json as _json

        payload = _json.dumps(
            {"text": text, "voice": voice, "speed": speed}
        ).encode()
        req = urllib.request.Request(
            f"{KOKORO_API_URL}/tts",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            audio = resp.read()
            if audio:
                log.info("TTS via Kokoro", extra={"chars": len(text)})
                return audio
    except Exception:
        log.debug("Kokoro TTS unavailable", extra={"err": traceback.format_exc()})

    # Fallback: espeak-ng → WAV via pipe
    return _espeak_tts(text, voice=voice, speed=speed)


def _espeak_tts(text: str, voice: str = "en", speed: float = 1.0) -> bytes:
    """
    Synthesise speech using espeak-ng as a fallback.

    Args:
        text:  Text to synthesise.
        voice: espeak voice code (e.g. 'en', 'tr').
        speed: Words per minute multiplier mapped to espeak -s flag.

    Returns:
        WAV audio bytes.
    """
    # espeak-ng speed: default ~175 wpm; scale by multiplier
    wpm = int(175 * speed)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        result = subprocess.run(
            [
                "espeak-ng",
                "-v", voice,
                "-s", str(wpm),
                "-w", tmp_path,
                text,
            ],
            capture_output=True,
            timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(f"espeak-ng failed: {result.stderr.decode()[:200]}")

        with open(tmp_path, "rb") as f:
            audio = f.read()
        log.info("TTS via espeak-ng", extra={"chars": len(text)})
        return audio
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# Microphone recording
# ---------------------------------------------------------------------------


def record_until_silence(
    threshold_db: float = -40.0,
    timeout: float = 10.0,
    silence_duration: float = 1.5,
    pre_roll_chunks: int = 5,
) -> bytes:
    """
    Record audio from the default microphone, stopping after silence.

    Silence is defined as RMS energy below *threshold_db* for at least
    *silence_duration* seconds.

    Args:
        threshold_db:     Silence threshold in dBFS (default -40 dB).
        timeout:          Maximum recording time in seconds (default 10 s).
        silence_duration: Consecutive silence seconds required to stop (default 1.5 s).
        pre_roll_chunks:  Chunks to keep before the first speech (prevents clipping).

    Returns:
        Raw 16 kHz mono PCM bytes (little-endian 16-bit signed int).
    """
    try:
        import pyaudio  # type: ignore[import]
        import math
        import struct

        pa = pyaudio.PyAudio()
        stream = pa.open(
            format=pyaudio.paInt16,
            channels=CHANNELS,
            rate=SAMPLE_RATE,
            input=True,
            frames_per_buffer=CHUNK_SIZE,
        )

        frames: list[bytes] = []
        silent_chunks = 0
        chunks_per_sec = SAMPLE_RATE / CHUNK_SIZE
        max_chunks = int(timeout * chunks_per_sec)
        silence_chunks_needed = int(silence_duration * chunks_per_sec)
        speech_started = False
        pre_roll: list[bytes] = []

        def rms_db(chunk: bytes) -> float:
            """Return RMS level in dBFS for a raw PCM chunk."""
            count = len(chunk) // 2
            if count == 0:
                return -100.0
            fmt = f"<{count}h"
            samples = struct.unpack(fmt, chunk)
            rms = math.sqrt(sum(s * s for s in samples) / count)
            if rms < 1:
                return -100.0
            return 20 * math.log10(rms / 32768.0)

        log.info("Recording started", extra={"threshold_db": threshold_db, "timeout": timeout})

        for _ in range(max_chunks):
            chunk = stream.read(CHUNK_SIZE, exception_on_overflow=False)
            db = rms_db(chunk)
            is_silent = db < threshold_db

            if not speech_started:
                pre_roll.append(chunk)
                if len(pre_roll) > pre_roll_chunks:
                    pre_roll.pop(0)
                if not is_silent:
                    speech_started = True
                    frames.extend(pre_roll)
                    log.debug("Speech detected")
            else:
                frames.append(chunk)
                if is_silent:
                    silent_chunks += 1
                    if silent_chunks >= silence_chunks_needed:
                        log.debug("Silence detected — stopping")
                        break
                else:
                    silent_chunks = 0

        stream.stop_stream()
        stream.close()
        pa.terminate()

        audio_bytes = b"".join(frames)
        log.info("Recording complete", extra={"bytes": len(audio_bytes)})
        return audio_bytes

    except ImportError:
        raise RuntimeError(
            "PyAudio not installed — microphone recording unavailable. "
            "Install: nix-env -iA nixpkgs.python3Packages.pyaudio"
        )


# ---------------------------------------------------------------------------
# Convenience: full voice round-trip
# ---------------------------------------------------------------------------


def voice_query(
    threshold_db: float = -40.0,
    timeout: float = 10.0,
    language: Optional[str] = None,
) -> str:
    """
    Record a voice query and return the transcribed text.

    Args:
        threshold_db: Silence threshold for recording (dBFS).
        timeout:      Max recording time in seconds.
        language:     Optional language hint for Whisper.

    Returns:
        Transcribed text string.
    """
    audio = record_until_silence(threshold_db=threshold_db, timeout=timeout)
    return faster_whisper_stt(audio, language=language)