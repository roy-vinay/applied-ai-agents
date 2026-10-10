"""Semantic check: a second, larger local model reads the question, all policies, and the answer, and
decides whether the policies support what the answer says and concludes.

    python judge.py --split dev --answer-models ollama:qwen2.5:3b
    python judge.py --split test           # refuses to run until the judge is frozen

Two rules decide what counts as a block:
  - A block must be grounded: the judge has to quote the problem sentence from the answer. If the quote
    isn't actually in the answer, the block is dropped (recorded as "ungrounded_block").
  - Fails closed: if the judge's reply can't be parsed at all, the answer is blocked.
"""
from __future__ import annotations

import argparse
import json
import re
import time
import urllib.request
from pathlib import Path

from common3 import (JUDGE_MODEL, MODELS, POLICIES, check_freeze, judge_path, judge_records, outputs_path,
                     questions, read_jsonl)

PROMPT = (Path(__file__).parent / "judge_prompt.txt").read_text()


def build_prompt(question: str, answer: str) -> str:
    policies = "\n".join(f"[{pid}] {p['text']}" for pid, p in POLICIES.items())
    return PROMPT.format(policies=policies, question=question, answer=answer)


def _norm(t: str) -> list[str]:
    return re.findall(r"[a-z0-9$%.]+", re.sub(r"\[?\b[A-Z]{2,4}-\d\b\]?", " ", t).lower())


def grounded(quote: str, answer: str) -> bool:
    """True if most of the quoted words appear, in order, in the answer."""
    q, a = _norm(quote), " ".join(_norm(answer))
    if len(q) < 3:
        return False
    hits = sum(1 for i in range(len(q) - 2) if " ".join(q[i:i + 3]) in a)
    return hits >= 0.6 * (len(q) - 2)


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
        verdict = str(parsed.get("verdict", "")).upper().split()[0] if parsed.get("verdict") else ""
        reason = str(parsed.get("reason", ""))
        quote = str(parsed.get("problem_sentence", ""))
    except (json.JSONDecodeError, AttributeError):
        verdict, reason, quote = "", "", ""
    ok = verdict in ("SUPPORTED", "UNSUPPORTED")
    ungrounded = ok and verdict == "UNSUPPORTED" and not grounded(quote, answer)
    final = "SUPPORTED" if ungrounded else (verdict if ok else "UNSUPPORTED")
    return {"verdict": final, "judge_said": verdict, "problem_sentence": quote, "ungrounded_block": ungrounded,
            "reason": reason, "parse_error": not ok,
            "latency_s": round(time.monotonic() - t, 2), "input_tokens": out.get("prompt_eval_count", 0),
            "output_tokens": out.get("eval_count", 0), "raw": raw}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", choices=["dev", "test"], required=True)
    ap.add_argument("--answer-models", default=",".join(MODELS))
    ap.add_argument("--shard", default="0/1", help="i/n: judge every n-th answer starting at i")
    args = ap.parse_args()
    if args.split == "test":
        check_freeze("judge")
    qmap = {q["id"]: q for q in questions(args.split)}
    for spec in args.answer_models.split(","):
        i_, n_ = map(int, args.shard.split("/"))
        path = judge_path(args.split, spec, i_ if n_ > 1 else None)
        done = {r["id"] for r in judge_records(args.split, spec)}
        todo = [o for k, o in enumerate(read_jsonl(outputs_path(args.split, spec))) if k % n_ == i_ and o["id"] not in done]
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
