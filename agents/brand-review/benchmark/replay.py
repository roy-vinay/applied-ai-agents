"""Replay a quarter of campaigns through review, with and without reviewer-taught lessons.

    python -m benchmark.replay            # print the table
    python -m benchmark.replay --check    # also assert the claims the README makes (used in CI)

Modes
  off       written-rule checks only; reviewers repeat their unwritten rules every time
  unscoped  reviewers' corrections become lessons, applied everywhere they match
  scoped    the same lessons, applied only inside the scope the reviewer chose

Per campaign: pre-review runs, required-rule failures are fixed by the marketer before review
(they never reach a reviewer), then reviewers review in rounds. A reviewer spots each remaining
objection with probability SPOT per round; spotted ones are corrected, and in lesson modes each
correction is learned. Review ends when a round finds nothing. Anything still wrong then escaped.
"""
from __future__ import annotations

import json
import random
import re
import sys
from pathlib import Path

from agent import BrandRules, Correction, LessonStore, prereview
from agent.lessons import apply_edit
from agent.retrieval import in_scope
from benchmark.scenarios import HABITS, SOURCE, make_quarter

SPOT = 0.75
SEEDS = range(1, 21)
MODES = ("off", "unscoped", "scoped")
HERE = Path(__file__).parent


def objections(spec, routed, novel):
    out = [h for h in HABITS if h.function in routed and h.objects_to(spec)]
    if novel and novel in spec.sub:
        out.append(("novel", novel))
    return out


def correct(spec, obj):
    if isinstance(obj, tuple):  # a one-off judgment call
        _, novel = obj
        c = Correction("Dana Ruiz", "legal", "sub", re.escape(f" A real {novel}."), "", "tone",
                       spec.campaign, note=f"One-off: drop '{novel}'")
        return spec.with_(sub=spec.sub.replace(f" A real {novel}.", "")), c, {"product": spec.product}, None
    h = obj
    # The reviewer strikes the exact words in front of them. The lesson learns those words,
    # not the reviewer's whole (unwritten) rule, so a paraphrase on a later draft can slip past it.
    struck = re.search(h.find, getattr(spec, h.field), flags=re.I).group(0)
    wrote = re.sub(h.find, h.replace, struck, flags=re.I)
    new = apply_edit(getattr(spec, h.field), h.find, h.replace)
    c = Correction(h.reviewer, h.function, h.field, re.escape(struck.strip()) if struck.strip() else h.find,
                   wrote.strip(), h.reason, spec.campaign, note=h.note)
    return spec.with_(**{h.field: new}), c, h.scope, h.id


def run(mode: str, seed: int, quarter) -> dict:
    rules, store = BrandRules(), (LessonStore() if mode != "off" else None)
    seen: set[str] = set()
    m = dict(campaigns=0, rounds=0, first_pass=0, repeat_corrections=0, repeat_present=0,
             repeat_removed=0, wrong_scope=0, escaped=0, blocked_before_review=0, planted_wrong_figures=0,
             month_rounds=[0, 0, 0], month_n=[0, 0, 0])
    for i, (day, spec, novel) in enumerate(quarter):
        rng = random.Random(seed * 10_000 + i)
        m["planted_wrong_figures"] += any(f.value != SOURCE[f.source_field] for f in spec.figures)
        res = prereview(spec, rules, store, day, SOURCE, use_lessons=mode != "off", scoped=mode == "scoped")
        for lesson in res.lessons_applied:
            if not in_scope(lesson, spec):
                m["wrong_scope"] += 1
        draft = res.spec
        if res.blocked:  # never reaches a reviewer; the marketer fixes the number against the source
            m["blocked_before_review"] += 1
            draft = draft.with_(figures=tuple(f.__class__(f.label, SOURCE[f.source_field], f.source_field)
                                              for f in draft.figures))

        before = [h for h in objections(spec, res.routed_to, None) if h.id in seen]
        after_ids = {o.id for o in objections(draft, res.routed_to, None)}
        m["repeat_present"] += len(before)
        m["repeat_removed"] += sum(h.id not in after_ids for h in before)

        rounds = 0
        while True:
            rounds += 1
            remaining = objections(draft, res.routed_to, novel)
            spotted = [o for o in remaining if rng.random() < SPOT]
            if not spotted:
                m["escaped"] += bool(remaining)
                break
            for o in spotted:
                draft, c, scope, hid = correct(draft, o)
                if hid in seen:
                    m["repeat_corrections"] += 1
                if hid:
                    seen.add(hid)
                if store is not None:
                    store.learn(c, scope, day)
        m["campaigns"] += 1
        m["rounds"] += rounds
        mo = min(2, i * 3 // len(quarter))
        m["month_rounds"][mo] += rounds
        m["month_n"][mo] += 1
        m["first_pass"] += rounds == 1
    return m


def summarize(quarter) -> dict:
    out = {}
    for mode in MODES:
        tot: dict = {}
        for s in SEEDS:
            for k, v in run(mode, s, quarter).items():
                if isinstance(v, list):
                    tot[k] = [a + b for a, b in zip(tot.get(k, [0] * len(v)), v)]
                else:
                    tot[k] = tot.get(k, 0) + v
        n, k = len(SEEDS), tot["campaigns"]
        out[mode] = {
            "mean_rounds": round(tot["rounds"] / k, 2),
            "first_pass": round(tot["first_pass"] / k, 3),
            "repeat_corrections_per_quarter": round(tot["repeat_corrections"] / n, 1),
            "lesson_recall": round(tot["repeat_removed"] / tot["repeat_present"], 3) if tot["repeat_present"] else 0.0,
            "wrong_scope_edits_per_quarter": round(tot["wrong_scope"] / n, 1),
            "escaped": round(tot["escaped"] / k, 3),
            "blocked_before_review_per_quarter": round(tot["blocked_before_review"] / n, 1),
            "planted_wrong_figures_per_quarter": round(tot["planted_wrong_figures"] / n, 1),
            "rounds_by_month": [round(r / c, 2) for r, c in zip(tot["month_rounds"], tot["month_n"])],
        }
    return out


def main() -> int:
    quarter = make_quarter()
    res = summarize(quarter)
    print(f"{len(quarter)} campaigns over a quarter, {len(SEEDS)} seeds, reviewer spot rate {SPOT:.0%}\n")
    cols = [("mean_rounds", "Rounds", "{:.2f}"), ("first_pass", "1st pass", "{:.0%}"),
            ("repeat_corrections_per_quarter", "Repeat fixes", "{:.1f}"), ("lesson_recall", "Recall", "{:.0%}"),
            ("wrong_scope_edits_per_quarter", "Wrong-scope", "{:.1f}"), ("escaped", "Escaped", "{:.1%}"),
            ("blocked_before_review_per_quarter", "Blocked pre-review", "{:.1f}")]
    print(f"{'Mode':10}" + "".join(f"{h:>19}" for _, h, _ in cols))
    for mode, r in res.items():
        print(f"{mode:10}" + "".join(f"{f.format(r[k]):>19}" for k, _, f in cols))
    print("\nLearning curve, mean rounds by month:")
    for mode, r in res.items():
        print(f"  {mode:10}" + "  ".join(f"month {i + 1}: {v:.2f}" for i, v in enumerate(r["rounds_by_month"])))
    (HERE / "results.json").write_text(json.dumps(res, indent=2) + "\n")

    if "--check" in sys.argv:
        off, uns, sco = res["off"], res["unscoped"], res["scoped"]
        checks = {
            "scoped lessons never edit outside their scope": sco["wrong_scope_edits_per_quarter"] == 0,
            "unscoped lessons do (the trap is real)": uns["wrong_scope_edits_per_quarter"] > 0,
            "scoped lessons cut repeat corrections by half or more":
                sco["repeat_corrections_per_quarter"] <= 0.5 * off["repeat_corrections_per_quarter"],
            "scoped lessons cut review rounds": sco["mean_rounds"] < off["mean_rounds"],
            "lessons don't raise escapes": sco["escaped"] <= off["escaped"] + 0.01,
            "every planted wrong figure is blocked before review": all(
                r["blocked_before_review_per_quarter"] == r["planted_wrong_figures_per_quarter"] > 0 for r in res.values()),
        }
        for name, ok in checks.items():
            print(f"  {'PASS' if ok else 'FAIL'}  {name}")
        return 0 if all(checks.values()) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
