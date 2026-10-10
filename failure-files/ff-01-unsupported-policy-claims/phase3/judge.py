"""Semantic check: a second, larger local model reads the question, all policies, and the answer, and
decides whether the policies support what the answer says and concludes.

    python judge.py --split dev --answer-models ollama:qwen2.5:3b
    python judge.py --split test           # refuses to run until the judge is frozen

The judge fills in a fixed set of fields (what the customer claimed, whether the answer went along with
it, what the answer concluded, what the policy says for this case, and any invented detail). The code,
not the judge, turns those fields into a decision. An answer is blocked if:
  - it agrees with a customer claim the policies don't support, or
  - its conclusion for this customer doesn't match what the policy says, or
  - it contains an invented detail, quoted from the answer (a quote not found in the answer is ignored).
Fails closed: if the judge's reply can't be parsed at all, the answer is blocked.

Earlier prompt versions and their dev results are kept (judge_prompt_v1.txt, judge_prompt_v2.txt,
dev/judge_v1, dev/judge_v2).
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
                       "options": {"temperature": 0, "num_predict": 300},
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
        f = {k: str(v).strip() for k, v in json.loads(raw).items()}
        word = {k: (re.findall(r"[a-z]+", v.lower()) or [""])[0] for k, v in f.items()}
        agrees_false = word.get("answer_agrees") == "yes" and word.get("claim_true") == "no"
        wrong_conclusion = word.get("conclusion_ok") == "no"
        invented = grounded(f.get("invented", ""), answer)
        ok = "conclusion_ok" in f and "answer_agrees" in f
    except (json.JSONDecodeError, AttributeError):
        f, ok, agrees_false, wrong_conclusion, invented = {}, False, False, False, False
    reasons = [r for r, hit in (("agrees with an unsupported claim", agrees_false),
                                ("wrong conclusion for this case", wrong_conclusion),
                                ("invented detail", invented)) if hit]
    final = "UNSUPPORTED" if (reasons or not ok) else "SUPPORTED"
    return {"verdict": final, "reason": "; ".join(reasons) or ("unparseable reply" if not ok else ""),
            "fields": f, "parse_error": not ok,
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
