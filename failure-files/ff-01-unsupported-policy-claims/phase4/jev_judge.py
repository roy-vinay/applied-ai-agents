"""Judge each answer with TypeSafe's Jev 1.13 through OpenRouter, with a hard spending stop.

Jev is a structured decision model: it picks from a fixed set of answers instead of writing text, so the
request asks for exactly one of SUPPORTED or UNSUPPORTED. The prompt (jev_prompt.txt) is fixed before the
pilot and not tuned afterwards; the pilot only checks that the call works and what it costs.

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
PROMPT = (HERE / "jev_prompt.txt").read_text()
SCHEMA = {"type": "json_schema", "json_schema": {"name": "verdict", "strict": True, "schema": {
    "type": "object", "additionalProperties": False, "required": ["verdict"],
    "properties": {"verdict": {"type": "string", "enum": ["SUPPORTED", "UNSUPPORTED"]}}}}}


def spent() -> float:
    return json.loads(SPEND.read_text())["usd"] if SPEND.exists() else 0.0


def add_spend(usd: float) -> None:
    OUT.mkdir(exist_ok=True)
    s = json.loads(SPEND.read_text()) if SPEND.exists() else {"usd": 0.0, "calls": 0}
    s["usd"] = round(s["usd"] + usd, 6)
    s["calls"] += 1
    SPEND.write_text(json.dumps(s, indent=1) + "\n")


def call(question: str, answer: str, key: str) -> dict:
    policies = "\n".join(f"[{pid}] {p['text']}" for pid, p in POLICIES.items())
    body = {"model": MODEL, "temperature": 0, "max_tokens": 20, "response_format": SCHEMA,
            "usage": {"include": True},
            "messages": [{"role": "user", "content": PROMPT.format(policies=policies, question=question, answer=answer)}]}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
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
        cost = usage.get("prompt_tokens", 0) * PRICE_IN_PER_TOKEN
    content = ((out.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
    verdict = ""
    try:
        verdict = str(json.loads(content).get("verdict", "")).upper()
    except (json.JSONDecodeError, AttributeError):
        m = re.search(r"\b(UNSUPPORTED|SUPPORTED)\b", content.upper())
        verdict = m.group(1) if m else ""
    ok = verdict in ("SUPPORTED", "UNSUPPORTED")
    return {"verdict": verdict if ok else "UNSUPPORTED", "parse_error": not ok, "raw": content[:300],
            "cost_usd": cost, "prompt_tokens": usage.get("prompt_tokens"), "latency_s": round(time.monotonic() - t, 2),
            "served_by": out.get("model"), "provider": out.get("provider")}


def fail(msg: str) -> None:
    """Record the error where it can be read later (GitHub annotation and a committed log), then stop."""
    OUT.mkdir(exist_ok=True)
    with open(OUT / "errors.log", "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")
    print(f"::error::{msg}", flush=True)
    raise SystemExit(1)


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
