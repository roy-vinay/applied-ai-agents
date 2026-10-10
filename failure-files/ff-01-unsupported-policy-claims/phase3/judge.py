"""Semantic check: a second, larger local model reads the question, all policies, and the answer, and
decides whether the policies support what the answer says and concludes.

    python judge.py --split dev --answer-models ollama:qwen2.5:3b
    python judge.py --split test           # refuses to run until the judge is frozen

Fails closed: if the judge's reply can't be parsed, the answer is treated as UNSUPPORTED (blocked).
"""
from __future__ import annotations

import argparse
import json
import time
import urllib.request
from pathlib import Path

from common3 import (JUDGE_MODEL, MODELS, POLICIES, check_freeze, judge_path, outputs_path, questions,
                     read_jsonl)

PROMPT = (Path(__file__).parent / "judge_prompt.txt").read_text()


def build_prompt(question: str, answer: str) -> str:
    policies = "\n".join(f"[{pid}] {p['text']}" for pid, p in POLICIES.items())
    return PROMPT.format(policies=policies, question=question, answer=answer)


def judge(question: str, answer: str, model: str = JUDGE_MODEL, host: str = "http://localhost:11434") -> dict:
    body = json.dumps({"model": model.split(":", 1)[1], "stream": False, "format": "json",
                       "options": {"temperature": 0, "num_predict": 120},
                       "messages": [{"role": "user", "content": build_prompt(question, answer)}]}).encode()
    req = urllib.request.Request(f"{host}/api/chat", data=body, headers={"Content-Type": "application/json"})
    last = None
    for attempt in range(3):
        t = time.monotonic()
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                out = json.load(r)
            break
        except Exception as e:
            last = e
            time.sleep(5 * (attempt + 1))
    else:
        raise RuntimeError(f"judge failed after 3 attempts: {last}")
    raw = out["message"]["content"]
    try:
        parsed = json.loads(raw)
        verdict = str(parsed.get("verdict", "")).upper()
        reason = str(parsed.get("reason", ""))
    except json.JSONDecodeError:
        verdict, reason = "", ""
    ok = verdict in ("SUPPORTED", "UNSUPPORTED")
    return {"verdict": verdict if ok else "UNSUPPORTED", "reason": reason, "parse_error": not ok,
            "latency_s": round(time.monotonic() - t, 2), "input_tokens": out.get("prompt_eval_count", 0),
            "output_tokens": out.get("eval_count", 0), "raw": raw}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", choices=["dev", "test"], required=True)
    ap.add_argument("--answer-models", default=",".join(MODELS))
    args = ap.parse_args()
    if args.split == "test":
        check_freeze("judge")
    qmap = {q["id"]: q for q in questions(args.split)}
    for spec in args.answer_models.split(","):
        path = judge_path(args.split, spec)
        done = {r["id"] for r in read_jsonl(path)}
        todo = [o for o in read_jsonl(outputs_path(args.split, spec)) if o["id"] not in done]
        print(f"{spec}: {len(todo)} to judge, {len(done)} already judged", flush=True)
        path.parent.mkdir(parents=True, exist_ok=True)
        for i, o in enumerate(todo, 1):
            try:
                rec = judge(qmap[o["id"]]["q"], o["text"])
            except RuntimeError as e:
                print(f"  {o['id']} skipped: {e}", flush=True)
                continue
            rec = {"id": o["id"], "answer_model": spec, "judge_model": JUDGE_MODEL, **rec}
            with open(path, "a") as f:
                f.write(json.dumps(rec) + "\n")
            print(f"  {i}/{len(todo)} {o['id']} {rec['verdict']} {rec['latency_s']}s", flush=True)
