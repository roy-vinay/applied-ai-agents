"""Phase 5 paths and helpers. Judges the Phase 3 test answers (300 fresh answers, already labeled)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path[:0] = [str(HERE.parent / "phase3"), str(HERE.parent / "phase4")]
from common3 import MODELS, POLICIES, labels_path, outputs_path, questions, read_jsonl, slug  # noqa: E402,F401

# Candidate judges. Local ones run on a free GitHub runner through Ollama (CPU, 16 GB RAM), so they
# must be about 14B parameters or smaller; each lists tags to try in order. Hosted ones use
# OpenRouter's free (":free") versions, which cost $0 but have daily request limits.
LOCAL = {
    "gemma4-12b": ["gemma4:12b"],
    "gemma4-e4b": ["gemma4:e4b"],
    "qwen3.5-9b": ["qwen3.5:9b"],
    "phi4-mini": ["phi4-mini:3.8b", "phi4-mini"],
    "phi4-14b": ["phi4:14b", "phi4"],
    "ministral3-3b": ["ministral-3:3b", "ministral3:3b", "ministral-3"],
}
HOSTED = {
    # OpenRouter's free list on 2026-10-11 had no free gpt-oss-120b or Llama 3.3 70B, so these replace them.
    "gemma4-31b": ["google/gemma-4-31b-it:free"],
    "nemotron3-super-120b": ["nvidia/nemotron-3-super-120b-a12b:free"],
    "nemotron3-ultra-550b": ["nvidia/nemotron-3-ultra-550b-a55b:free"],
}


def judge_dir(name: str) -> Path:
    return HERE / "test" / "judges" / name


def records(name: str, answer_model: str) -> list[dict]:
    stem = slug(answer_model)[: -len(".jsonl")]
    out = []
    for p in sorted(judge_dir(name).glob(stem + "*.jsonl")):
        out += read_jsonl(p)
    return out
