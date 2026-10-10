"""Rule-based first-pass labels for the test answers, using the same rules as Phase 2.
Flagged answers are then reviewed and marked "source": "claude_review" (see README).

    python label3.py
"""
from __future__ import annotations

import json

from common3 import MODELS, labels_path, outputs_path, questions, read_jsonl
from label import auto

qmap = {q["id"]: q for q in questions("test")}
for spec in MODELS:
    outs = read_jsonl(outputs_path("test", spec))
    prior = {r["id"]: r for r in read_jsonl(labels_path("test", spec))}
    recs = []
    for o in outs:
        if o["id"] in prior and prior[o["id"]]["source"] != "rule":
            recs.append(prior[o["id"]])
            continue
        label, why = auto(qmap[o["id"]], o)
        recs.append({"id": o["id"], "label": label, "why": why, "source": "rule"})
    if recs:
        path = labels_path("test", spec)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(r) + "\n" for r in recs))
    print(f"{spec}: {len(recs)} labeled, {sum(r['label'] == 'needs_review' for r in recs)} need review")
