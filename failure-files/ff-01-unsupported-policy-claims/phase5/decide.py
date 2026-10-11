"""The Phase 3 judge's decision rule, reused unchanged so every Phase 5 judge is scored the same way.

The judge model fills in fixed fields; code, not the model, turns them into a verdict. This is a copy of
the logic in phase3/judge.py (which is frozen and can't be edited); check_decide.py proves the two agree by
re-deciding every saved Phase 3 verdict from its raw reply.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "phase3"))
from judge import build_prompt, grounded  # noqa: E402,F401  (frozen Phase 3 prompt and quote check)


def decide(raw: str, answer: str) -> dict:
    try:
        f = {k: str(v).strip() for k, v in json.loads(raw).items()}
        word = {k: (re.findall(r"[a-z]+", v.lower()) or [""])[0] for k, v in f.items()}
        agrees_false = word.get("answer_agrees") == "yes" and word.get("claim_true") == "no"
        wrong_conclusion = word.get("conclusion_ok") == "no"
        invented = grounded(f.get("invented", ""), answer)
        ok = "conclusion_ok" in f and "answer_agrees" in f
    except (json.JSONDecodeError, AttributeError):
        f, ok, agrees_false, wrong_conclusion, invented = {}, False, False, False, False
    reasons = [r for r, hit in (("agrees with an unsupported claim", agrees_false),
                                ("wrong conclusion for this case", wrong_conclusion),
                                ("invented detail", invented)) if hit]
    final = "UNSUPPORTED" if (reasons or not ok) else "SUPPORTED"
    return {"verdict": final, "reason": "; ".join(reasons) or ("unparseable reply" if not ok else ""),
            "parse_error": not ok}
