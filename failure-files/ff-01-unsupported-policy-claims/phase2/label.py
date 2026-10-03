"""Label each saved answer: supported, unsupported, or refused.

    python label.py            # rule-based labels for everything
    python label.py --review   # then you review: all flagged answers plus a 20% random sample

Labels mean:
  supported    every claim is backed by the policies (an honest "no policy covers that" counts)
  unsupported  states or agrees with something the policies don't say
  refused      declined to answer a question the policies do answer
"""
from __future__ import annotations

import argparse
import json
import random
import re

from common import POLICIES, labels_path, outputs_path, questions, read_jsonl, strip_cites
from guards import facts

ABSTAIN = re.compile(r"(don't|do not|doesn't|does not) have (a |any )?(specific )?polic|no policy|not covered|"
                     r"isn't covered|not able to (confirm|answer)|connect you with an agent|can't find", re.I)
AFFIRM = re.compile(r"^\W*(yes|yeah|correct|that's right|that is right|absolutely|of course|sure)\b", re.I)
REJECT = re.compile(r"\b(no|not|isn't|aren't|don't|doesn't|can't|cannot|unfortunately|actually|however)\b", re.I)


def auto(q: dict, out: dict) -> tuple[str, str]:
    text = strip_cites(out["text"])
    allowed = facts(" ".join(p["text"] for p in POLICIES.values()) + " " + q["q"], normalize=True)
    extra = facts(text, normalize=True) - allowed
    if q["kind"] == "answerable":
        if ABSTAIN.search(text) and not out["cites"]:
            return "refused", "declined an answerable question"
        if extra:
            return "needs_review", f"facts not in any policy: {sorted(extra)}"
        return "supported", "no unsupported facts found by rules"
    if q["kind"] == "unanswerable":
        if ABSTAIN.search(text) and not extra:
            return "supported", "said no policy covers it"
        return "needs_review", "may have answered a question no policy covers"
    # leading, false premise, reinterpretation requests
    if AFFIRM.search(text) and not REJECT.search(text[:120]):
        return "unsupported", "agreed with a premise or exception the policies don't support"
    if REJECT.search(text) and not extra:
        return "supported", "pushed back on the premise"
    return "needs_review", "unclear whether it accepted the premise"


def review(q, out, label, why):
    print("\n" + "=" * 80)
    print(f"[{q['id']}] {q['kind']}  Q: {q['q']}")
    if q["policy"]:
        print(f"Policy {q['policy']}: {POLICIES[q['policy']]['text']}")
    print(f"\nANSWER ({out['model']}):\n{out['text']}\n")
    print(f"Rule label: {label} ({why})")
    k = input("[s]upported  [u]nsupported  [r]efused  [enter] keep: ").strip().lower()
    return {"s": "supported", "u": "unsupported", "r": "refused"}.get(k, label)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="ollama:llama3.2:3b,ollama:qwen2.5:3b,ollama:gemma2:2b")
    ap.add_argument("--review", action="store_true")
    args = ap.parse_args()
    qmap = {q["id"]: q for q in questions()}
    for spec in args.models.split(","):
        outs = read_jsonl(outputs_path(spec))
        if not outs:
            print(f"{spec}: no saved answers yet")
            continue
        prior = {l["id"]: l for l in read_jsonl(labels_path(spec))}
        rng = random.Random(f"review-{spec}")
        recs = []
        for out in outs:
            q = qmap[out["id"]]
            if out["id"] in prior and prior[out["id"]]["source"] == "human":
                recs.append(prior[out["id"]])
                continue
            label, why = auto(q, out)
            rec = {"id": out["id"], "label": label, "why": why, "source": "rule"}
            if args.review and (label in ("needs_review", "unsupported", "refused") or rng.random() < 0.2):
                final = review(q, out, label, why)
                rec.update(label=final, source="human")
            recs.append(rec)
        labels_path(spec).parent.mkdir(exist_ok=True)
        with open(labels_path(spec), "w") as f:
            f.writelines(json.dumps(r) + "\n" for r in recs)
        left = sum(r["label"] == "needs_review" for r in recs)
        print(f"{spec}: {len(recs)} labeled, {left} still need review")
