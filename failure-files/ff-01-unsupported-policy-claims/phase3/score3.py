"""Phase 3 results: four ways to guard the same answers, compared on the same labels.

    python score3.py              # dev and test, whatever is available
    python score3.py --if-present # CI: exit quietly when nothing is judged yet

Configurations
  Rules, frozen      the Phase 1 guard exactly as in Phase 2
  Rules + repair     same guard after citation repair (repair.py)
  Judge only         the semantic check alone (judge.py)
  Repair + judge     block if either one blocks

Measures, over all answers whose label is known (refusals are reported, not guarded):
  catch rate         unsupported answers blocked
  false blocks       supported answers blocked
"""
from __future__ import annotations

import statistics
import sys

from common3 import MODELS, judge_path, labels_path, outputs_path, questions, read_jsonl
from repair import passes_rules_frozen, passes_rules_repaired

CONFIGS = ["Rules, frozen (Phase 2)", "Rules + citation repair", "Judge only", "Repair + judge"]


def pct(a, b):
    return f"{a}/{b} ({a / b:.0%})" if b else "n/a"


def score(split: str):
    qmap = {q["id"]: q for q in questions(split)}
    rows, refused, total, lat, judged_n = [], 0, 0, [], 0
    for spec in MODELS:
        outs = {o["id"]: o for o in read_jsonl(outputs_path(split, spec))}
        labs = {l["id"]: l["label"] for l in read_jsonl(labels_path(split, spec))}
        jud = {j["id"]: j for j in read_jsonl(judge_path(split, spec))}
        for i, label in labs.items():
            if i not in outs or i not in jud or label == "needs_review":
                continue
            total += 1
            judged_n += 1
            lat.append(jud[i]["latency_s"])
            if label == "refused":
                refused += 1
                continue
            q, o = qmap[i]["q"], outs[i]
            frozen = not passes_rules_frozen(q, o["text"], o["cites"])
            rep = not passes_rules_repaired(q, o["text"], o["cites"])
            j = jud[i]["verdict"] == "UNSUPPORTED"
            rows.append((spec, label, [frozen, rep, j, rep or j]))
    return rows, refused, total, lat


def table(split: str) -> bool:
    rows, refused, total, lat = score(split)
    if not rows:
        return False
    unsup = [r for r in rows if r[1] == "unsupported"]
    sup = [r for r in rows if r[1] == "supported"]
    print(f"\n### {split}: {total} answers, {len(unsup)} unsupported, {len(sup)} supported, {refused} refused\n")
    print("| Guard | Catch rate (unsupported blocked) | False blocks (supported blocked) |")
    print("| --- | ---: | ---: |")
    for k, name in enumerate(CONFIGS):
        print(f"| {name} | {pct(sum(r[2][k] for r in unsup), len(unsup))} | {pct(sum(r[2][k] for r in sup), len(sup))} |")
    print(f"\nJudge latency: median {statistics.median(lat):.1f} s per answer on a CPU-only runner. Cost: $0 (local model).")
    print("\nBy answering model (Repair + judge):\n")
    print("| Model | Catch rate | False blocks |")
    print("| --- | ---: | ---: |")
    for spec in MODELS:
        u = [r for r in unsup if r[0] == spec]
        s = [r for r in sup if r[0] == spec]
        print(f"| {spec} | {pct(sum(r[2][3] for r in u), len(u))} | {pct(sum(r[2][3] for r in s), len(s))} |")
    return True


if __name__ == "__main__":
    any_ = [table(s) for s in ("dev", "test")]
    if not any(any_):
        print("No judged Phase 3 answers yet.")
    sys.exit(0)
