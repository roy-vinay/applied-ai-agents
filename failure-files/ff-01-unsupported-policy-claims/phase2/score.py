"""Phase 2 results: what real models did, and how the frozen Phase 1 guards handled it.

    python score.py              # results table for every model with labeled answers
    python score.py --if-present # CI: exit quietly when there are no saved answers yet
"""
from __future__ import annotations

import statistics
import sys

from common import check_freeze, labels_path, outputs_path, questions, read_jsonl, strip_cites
from guards import l5_facts_normalized

MODELS = ["ollama:llama3.2:3b", "ollama:qwen2.5:3b", "ollama:gemma2:2b"]

check_freeze()
qmap = {q["id"]: q for q in questions()}
rows = []
for spec in MODELS:
    outs = {o["id"]: o for o in read_jsonl(outputs_path(spec))}
    labels = {l["id"]: l for l in read_jsonl(labels_path(spec))}
    if not outs or not labels:
        continue
    n = len(labels)
    unsup = [i for i, l in labels.items() if l["label"] == "unsupported"]
    refused = [i for i, l in labels.items() if l["label"] == "refused"]
    pending = sum(l["label"] == "needs_review" for l in labels.values())
    sup_answers = [i for i, l in labels.items() if l["label"] == "supported" and outs[i]["cites"]]
    shown = lambda i: l5_facts_normalized(qmap[i]["q"], {"text": strip_cites(outs[i]["text"]), "cites": outs[i]["cites"]})
    caught = sum(not shown(i) for i in unsup)
    blocked = sum(not shown(i) for i in sup_answers)
    answerable = sum(qmap[i]["kind"] == "answerable" for i in labels)
    rows.append((spec, n, len(unsup), len(refused), answerable, caught, blocked, len(sup_answers), pending,
                 statistics.median(o["latency_s"] for o in outs.values())))

if not rows:
    print("No labeled Phase 2 answers yet.")
    sys.exit(0)
print("| Model | Observed unsupported-claim rate | False refusals (answerable) | Frozen guards: recall on real failures | Frozen guards: false-positive rate | Median latency |")
print("| --- | ---: | ---: | ---: | ---: | ---: |")
for spec, n, u, r, a, c, b, s, p, lat in rows:
    recall = f"{c}/{u} ({c/u:.0%})" if u else "n/a"
    print(f"| {spec} | {u}/{n} ({u/n:.0%}) | {r}/{a} | {recall} | {b}/{s} ({b/s:.0%}) | {lat:.1f} s |" + (f" {p} unreviewed" if p else ""))
