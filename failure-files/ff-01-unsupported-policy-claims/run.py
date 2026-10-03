"""FF-01 experiment: which guard layers stop unsupported policy claims, and what they cost.

    python run.py          # prints both result tables
    python run.py --check  # CI: fails if the final layer gets worse than the saved baseline
"""
from __future__ import annotations

import json
import random
import statistics
import sys
import time
from collections import defaultdict

import guards
import model

N, SEED = 500, 11


def trials(n=N, seed=SEED):
    rng = random.Random(seed)
    return [model.draw(rng) for _ in range(n)]


def evaluate(ts):
    rows = []
    for name, check in guards.LAYERS:
        leaked = blocked = 0
        times = []
        for kind, behavior, q, reply, correct in ts:
            t = time.perf_counter()
            shown = check(q, reply)
            times.append((time.perf_counter() - t) * 1e6)
            if correct and not shown:
                blocked += 1
            if not correct and shown:
                leaked += 1
        rows.append({"layer": name, "leaked": leaked, "blocked": blocked, "us": statistics.median(times)})
    return rows


def by_behavior(ts):
    final = guards.LAYERS[-1][1]
    out = defaultdict(lambda: [0, 0])
    for kind, behavior, q, reply, correct in ts:
        out[(kind, behavior, correct)][0] += 1
        out[(kind, behavior, correct)][1] += final(q, reply)
    return out


if __name__ == "__main__":
    ts = trials()
    bad = sum(1 for t in ts if not t[4])
    good = len(ts) - bad
    rows = evaluate(ts)
    print(f"{len(ts)} trials: {bad} faulty answers, {good} correct answers\n")
    print("| Guards (each adds to the one above) | Injected failures not caught | Correct answers wrongly blocked |")
    print("| --- | ---: | ---: |")
    for r in rows:
        print(f"| {r['layer']} | {r['leaked']}/{bad} ({r['leaked']/bad:.0%}) | {r['blocked']}/{good} ({r['blocked']/good:.0%}) |")
    last = rows[-1]
    print(f"\nFinal layer: detection recall {1 - last['leaked']/bad:.1%}, false-positive rate {last['blocked']/good:.1%}.")
    print("\n| Answer type | Expected | Shown with all guards |")
    print("| --- | --- | ---: |")
    for (kind, behavior, correct), (n, shown) in sorted(by_behavior(ts).items(), key=lambda x: (x[0][0], not x[0][2], x[0][1])):
        exp = "show" if correct else "block"
        print(f"| {kind}: {behavior.replace('_', ' ')} | {exp} | {shown}/{n} |")
    if "--check" in sys.argv:
        base = json.load(open("baseline.json"))
        last = rows[-1]
        if last["leaked"] > base["leaked"] or last["blocked"] > base["blocked"]:
            print("final layer regressed vs baseline", base)
            sys.exit(1)
