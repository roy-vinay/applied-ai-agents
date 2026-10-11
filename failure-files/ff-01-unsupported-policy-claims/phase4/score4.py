"""Phase 4 results: the number check and the Jev judge, added to the Phase 3 guards.

    python score4.py              # dev and test, with whatever Jev results exist
    python score4.py --if-present # CI: quiet when there is nothing to score
"""
from __future__ import annotations

import json
import sys

from common4 import MODELS, judge_records, labels_path, outputs_path, questions, read_jsonl, slug
from numbers_check import check
from repair import passes_rules_repaired
from pathlib import Path

HERE = Path(__file__).parent


def jev(split: str, spec: str) -> dict:
    p = HERE / "jev" / split / slug(spec)
    return {r["id"]: r for r in read_jsonl(p)}


def score(split: str) -> bool:
    qmap = {q["id"]: q for q in questions(split)}
    rows, have_jev = [], True
    for spec in MODELS:
        outs = {o["id"]: o for o in read_jsonl(outputs_path(split, spec))}
        qj = {j["id"]: j for j in judge_records(split, spec)}
        jj = jev(split, spec)
        for l in read_jsonl(labels_path(split, spec)):
            i = l["id"]
            if l["label"] in ("refused", "needs_review") or i not in qj:
                continue
            q, o = qmap[i]["q"], outs[i]
            rows.append({"label": l["label"],
                         "rep": not passes_rules_repaired(q, o["text"], o["cites"]),
                         "num": check(q, o["text"])[0] == "block",
                         "qwen": qj[i]["verdict"] == "UNSUPPORTED",
                         "jev": (jj[i]["verdict"] == "UNSUPPORTED") if i in jj else None})
            have_jev &= i in jj
    if not rows:
        return False
    configs = [("Phase 3 best: repair + Qwen judge", lambda r: r["rep"] or r["qwen"]),
               ("Number check alone (no model)", lambda r: r["num"]),
               ("Repair + number check (no model)", lambda r: r["rep"] or r["num"]),
               ("Repair + number check + Qwen judge", lambda r: r["rep"] or r["num"] or r["qwen"])]
    if have_jev:
        configs += [("Jev judge alone", lambda r: r["jev"]),
                    ("Repair + number check + Jev judge", lambda r: r["rep"] or r["num"] or r["jev"])]
    U = [r for r in rows if r["label"] == "unsupported"]
    S = [r for r in rows if r["label"] == "supported"]
    print(f"\n### {split}: {len(U)} unsupported, {len(S)} supported answers\n")
    print("| Guard | Real failures caught | Good answers wrongly blocked |")
    print("| --- | ---: | ---: |")
    for name, f in configs:
        u, s = sum(bool(f(r)) for r in U), sum(bool(f(r)) for r in S)
        print(f"| {name} | {u}/{len(U)} ({u/len(U):.0%}) | {s}/{len(S)} ({s/len(S):.0%}) |")
    if not have_jev:
        print("\n(Jev results not complete for this split yet.)")
    sp = HERE / "jev" / "spend.json"
    if sp.exists():
        s = json.loads(sp.read_text())
        print(f"\nJev spend so far: ${s['usd']:.4f} over {s['calls']} calls.")
    return True


if __name__ == "__main__":
    if not any([score("dev"), score("test")]):
        print("Nothing to score yet.")
    sys.exit(0)
