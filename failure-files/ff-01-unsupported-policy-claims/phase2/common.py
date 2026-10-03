"""Shared paths, freeze check, and helpers for Phase 2."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))

from kb import POLICIES  # noqa: E402

FROZEN = [ROOT / "guards.py", ROOT / "kb.py", HERE / "questions.json", HERE / "prompt.txt"]
CITE = re.compile(r"\b([A-Z]{2,4}-\d)\b")


def strip_cites(text: str) -> str:
    """Remove inline citation tags like [BAG-1] so their digits aren't read as facts.
    Citations are passed to the guards separately, as in Phase 1."""
    return re.sub(r"\[?\b[A-Z]{2,4}-\d\b\]?", "", text)


def digest(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def check_freeze() -> None:
    frozen = json.load(open(HERE / "FREEZE.json"))["sha256"]
    changed = [p.name for p in FROZEN if frozen.get(p.name) != digest(p)]
    if changed:
        sys.exit(f"Frozen files changed since the freeze: {changed}. Phase 2 results would not be held-out.")


def questions() -> list[dict]:
    return json.load(open(HERE / "questions.json"))


def system_prompt() -> str:
    policies = "\n".join(f"[{pid}] {p['text']}" for pid, p in POLICIES.items())
    return (HERE / "prompt.txt").read_text().format(policies=policies)


def outputs_path(model: str) -> Path:
    return HERE / "outputs" / (re.sub(r"[^a-zA-Z0-9.]+", "_", model) + ".jsonl")


def labels_path(model: str) -> Path:
    return HERE / "labels" / (re.sub(r"[^a-zA-Z0-9.]+", "_", model) + ".jsonl")


def read_jsonl(p: Path) -> list[dict]:
    return [json.loads(line) for line in open(p)] if p.exists() else []
