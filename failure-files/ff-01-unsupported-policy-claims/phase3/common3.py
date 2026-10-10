"""Shared paths, freezes, and helpers for Phase 3.

Two splits:
  dev   the Phase 2 answers (already labeled). Used to build and tune the judge and the citation repair.
  test  fresh answers from the same three models to 100 new questions, frozen before any model saw them.
        Labeled before the judge runs on them. This is the number that counts.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.parent
P2 = ROOT / "phase2"
sys.path[:0] = [str(ROOT), str(P2)]

from kb import POLICIES  # noqa: E402
from common import CITE, read_jsonl, strip_cites, system_prompt  # noqa: E402,F401
import common as p2  # noqa: E402

MODELS = ["ollama:llama3.2:3b", "ollama:qwen2.5:3b", "ollama:gemma2:2b"]
JUDGE_MODEL = "ollama:qwen2.5:7b"

FREEZES = {
    # frozen before any model answered the test questions
    "test": [HERE / "questions_test.json", P2 / "prompt.txt", ROOT / "kb.py", ROOT / "guards.py"],
    # frozen after tuning on dev, before the judge saw any test answer
    "judge": [HERE / "judge.py", HERE / "judge_prompt.txt", HERE / "repair.py"],
}


def slug(model: str) -> str:
    return re.sub(r"[^a-zA-Z0-9.]+", "_", model) + ".jsonl"


def digest(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def freeze(name: str, date: str, note: str) -> None:
    rec = {"frozen_on": date, "note": note, "sha256": {p.name: digest(p) for p in FREEZES[name]}}
    (HERE / f"FREEZE_{name}.json").write_text(json.dumps(rec, indent=1) + "\n")


def check_freeze(name: str) -> None:
    path = HERE / f"FREEZE_{name}.json"
    if not path.exists():
        sys.exit(f"{path.name} is missing: the '{name}' freeze hasn't happened yet.")
    frozen = json.loads(path.read_text())["sha256"]
    changed = [p.name for p in FREEZES[name] if frozen.get(p.name) != digest(p)]
    if changed:
        sys.exit(f"Files changed since the '{name}' freeze: {changed}. Results would not be held-out.")


def questions(split: str) -> list[dict]:
    return p2.questions() if split == "dev" else json.loads((HERE / "questions_test.json").read_text())


def outputs_path(split: str, model: str) -> Path:
    return p2.outputs_path(model) if split == "dev" else HERE / "test" / "outputs" / slug(model)


def labels_path(split: str, model: str) -> Path:
    return p2.labels_path(model) if split == "dev" else HERE / "test" / "labels" / slug(model)


def judge_path(split: str, answer_model: str) -> Path:
    return HERE / split / "judge" / slug(answer_model)
