"""Stencil english-name → localized-name maps for STENCIL_FULL languages."""
from __future__ import annotations
import json
from pathlib import Path

_DIR = Path(__file__).with_name("stencil_maps")

def _load() -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    if not _DIR.exists():
        return out
    for p in sorted(_DIR.glob("*.json")):
        out[p.stem] = json.loads(p.read_text())
    return out

STENCIL_MAPS = _load()
