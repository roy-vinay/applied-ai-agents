"""Phase 5 results: 2026 free models as judges, against the Phase 3 free judge and Jev, on the same 300
fresh answers and labels, with the same frozen prompt as Phase 3 (Jev uses its own question format).

    python score5.py              # all judges with complete results
    python score5.py --if-present # CI: quiet when there's nothing yet
"""
from __future__ import annotations

import statistics
import sys
from pathlib import Path

from common5 import HOSTED, LOCAL, MODELS, labels_path, outputs_path, questions, read_jsonl, records, slug
from numbers_check import check

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "phase3"))
from common3 import judge_records  # noqa: E402

qmap = {q["id"]: q for q in questions("test")}
labels, outs = {}, {}
for spec in MODELS:
    outs.update({(spec, o["id"]): o for o in read_jsonl(outputs_path("test", spec))})
    labels.update({(spec, l["id"]): l["label"] for l in read_jsonl(labels_path("test", spec))})


def verdicts(name):
    if name == "qwen2.5-7b (Phase 3)":
        return {(s, r["id"]): r for s in MODELS for r in judge_records("test", s)}
    if name == "jev-1.13 (Phase 4)":
        return {(s, r["id"]): r for s in MODELS for r in read_jsonl(HERE.parent / "phase4" / "jev" / "test" / slug(s))}
    return {(s, r["id"]): r for s in MODELS for r in records(name, s)}


rows = []
for name in ["qwen2.5-7b (Phase 3)", "jev-1.13 (Phase 4)"] + list(LOCAL) + list(HOSTED):
    v = verdicts(name)
    keys = [k for k, lab in labels.items() if lab in ("supported", "unsupported")]
    if not v or any(k not in v for k in keys):
        if v:
            rows.append((name, None, len(v)))
        continue
    U = [k for k in keys if labels[k] == "unsupported"]
    S = [k for k in keys if labels[k] == "supported"]
    blocked = lambda k: v[k]["verdict"] == "UNSUPPORTED"
    num = lambda k: check(qmap[k[1]]["q"], outs[k]["text"])[0] == "block"
    lat = statistics.median(r["latency_s"] for r in v.values())
    pe = sum(r.get("parse_error", False) for r in v.values())
    model = next(iter(v.values())).get("judge_model", name)
    rows.append((name, (sum(map(blocked, U)), len(U), sum(map(blocked, S)), len(S),
                        sum(blocked(k) or num(k) for k in U), sum(blocked(k) or num(k) for k in S), lat, pe, model), len(v)))

if not rows:
    print("No Phase 5 judge results yet.")
    sys.exit(0)
print("| Judge | Model | Failures caught | Good answers wrongly blocked | With number check: caught / wrongly blocked | Median time per answer | Unreadable replies |")
print("| --- | --- | ---: | ---: | ---: | ---: | ---: |")
for name, r, n in rows:
    if r is None:
        print(f"| {name} | | in progress ({n}/300) | | | | |")
        continue
    u, U, s, S, nu, ns, lat, pe, model = r
    print(f"| {name} | {model} | {u}/{U} ({u/U:.0%}) | {s}/{S} ({s/S:.0%}) | {nu/U:.0%} / {ns/S:.0%} | {lat:.1f} s | {pe} |")
