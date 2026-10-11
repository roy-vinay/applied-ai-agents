"""Judge each answer with TypeSafe's Jev 1.13 through OpenRouter, with a hard spending stop.

Jev is a structured decision model: it picks from a fixed set of answers instead of writing text. It is
called through OpenRouter's decisions endpoint (/api/alpha/decisions; the chat endpoint rejects it) with
one "choice" question, SUPPORTED or UNSUPPORTED, defined in jev_prompt.json. The policies, the customer's
question and the answer go in as the state. The prompt is fixed before the pilot and not tuned afterwards;
the pilot only checks that the call works and what it costs.

    python jev_judge.py --pilot             # 10 dev answers, to check format and cost
    python jev_judge.py --split dev         # all Phase 2 answers
    python jev_judge.py --split test        # all Phase 3 answers

Needs OPENROUTER_API_KEY. Every response's cost is added to jev/spend.json, and the script refuses to
make another call once the total reaches BUDGET_USD, below the key's own $1 limit.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import time
import urllib.request
from pathlib import Path

from common4 import MODELS, POLICIES, outputs_path, questions, read_jsonl, slug

MODEL = "typesafe/jev-1.13"          # Jev itself; not typesafe/jev-router, which forwards to other models
PRICE_IN_PER_TOKEN = 0.042 / 1e6     # OpenRouter list price, used only if a response reports no cost
BUDGET_USD = 0.90
HERE = Path(__file__).parent
OUT = HERE / "jev"
SPEND = OUT / "spend.json"
QUESTION = json.loads((HERE / "jev_prompt.json").read_text())


def spent() -> float:
    return json.loads(SPEND.read_text())["usd"] if SPEND.exists() else 0.0


def add_spend(usd: float) -> None:
    OUT.mkdir(exist_ok=True)
    s = json.loads(SPEND.read_text()) if SPEND.exists() else {"usd": 0.0, "calls": 0}
    s["usd"] = round(s["usd"] + usd, 6)
    s["calls"] += 1
    SPEND.write_text(json.dumps(s, indent=1) + "\n")


def call(question: str, answer: str, key: str) -> dict:
    body = {"model": MODEL,
            "state": {"policies": {pid: p["text"] for pid, p in POLICIES.items()},
                      "customer_question": question, "assistant_answer": answer},
            "questions": {"verdict": {"type": "choice", **QUESTION}}}
    req = urllib.request.Request("https://openrouter.ai/api/alpha/decisions", data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                                          "X-Title": "FF-01 Phase 4"})
    last = None
    for attempt in range(3):
        t = time.monotonic()
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                out = json.load(r)
            break
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code}: {e.read()[:300]!r}"
            if e.code in (400, 401, 402, 403, 404):
                raise RuntimeError(last)       # bad request, key, or credit: retrying won't help
        except Exception as e:
            last = str(e)
        time.sleep(3 * (attempt + 1))
    else:
        raise RuntimeError(f"failed after 3 attempts: {last}")
    usage = out.get("usage") or {}
    cost = usage.get("cost")
    if cost is None:
        cost = (usage.get("input_tokens") or 0) * PRICE_IN_PER_TOKEN
    ans = (out.get("answers") or {}).get("verdict") or {}
    verdict = str(ans.get("choice", "")).upper()
    ok = verdict in ("SUPPORTED", "UNSUPPORTED")
    return {"verdict": verdict if ok else "UNSUPPORTED", "parse_error": not ok,
            "probabilities": ans.get("probabilities"), "confidence": ans.get("confidence"),
            "raw": None if ok else json.dumps(out)[:400],
            "cost_usd": cost, "input_tokens": usage.get("input_tokens"), "latency_s": round(time.monotonic() - t, 2),
            "served_by": out.get("model"), "provider": out.get("provider")}


def run(split: str, limit: int | None, tag: str) -> None:
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        fail("OPENROUTER_API_KEY is not set or is empty in this run")
    qmap = {q["id"]: q for q in questions(split)}
    for spec in MODELS:
        path = OUT / tag / slug(spec)
        path.parent.mkdir(parents=True, exist_ok=True)
        done = {r["id"] for r in read_jsonl(path)}
        todo = [o for o in read_jsonl(outputs_path(split, spec)) if o["id"] not in done]
        if limit is not None:
            todo = todo[: max(0, limit - len(done))]
        print(f"{spec}: {len(todo)} to judge, spent so far ${spent():.4f}", flush=True)
        for o in todo:
            if spent() >= BUDGET_USD:
                fail(f"stopping: spend ${spent():.4f} reached the ${BUDGET_USD} budget")
            try:
                rec = {"id": o["id"], "answer_model": spec, "judge_model": MODEL,
                       **call(qmap[o["id"]]["q"], o["text"], key)}
            except RuntimeError as e:
                fail(f"{o['id']}: {e}")
            add_spend(rec["cost_usd"])
            with open(path, "a") as f:
                f.write(json.dumps(rec) + "\n")
            print(f"  {o['id']} {rec['verdict']} ${rec['cost_usd']:.6f} {rec['latency_s']}s via {rec['served_by']}", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", choices=["dev", "test"])
    ap.add_argument("--pilot", action="store_true")
    a = ap.parse_args()
    if a.pilot:
        run("dev", 4, "pilot")       # 4 per answering model, 12 calls
    elif a.split:
        run(a.split, None, a.split)
    else:
        ap.error("use --pilot or --split")
