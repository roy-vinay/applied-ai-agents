"""Phase 5: run one candidate judge over the 300 Phase 3 test answers, with the frozen Phase 3 prompt.

    python judge5.py --judge gemma4-12b --answer-models ollama:gemma2:2b --shard 0/3   # local, via Ollama
    python judge5.py --judge gpt-oss-120b                                            # hosted, OpenRouter :free

Local judges try each candidate tag until one downloads. Hosted judges must be free: the script stops if
OpenRouter reports any cost. Answers are saved as they come, so a run that hits a daily limit resumes later.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
import urllib.error
import urllib.request

from common5 import HOSTED, LOCAL, MODELS, judge_dir, outputs_path, questions, read_jsonl, records, slug
from decide import build_prompt, decide


def post(url: str, body: dict, headers: dict, timeout: int) -> dict:
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", **headers})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def pull_first(tags: list[str]) -> str:
    for tag in tags:
        if subprocess.run(["ollama", "pull", tag], capture_output=True).returncode == 0:
            return tag
        print(f"  could not pull {tag}", flush=True)
    raise SystemExit(f"::error::none of these tags could be pulled: {tags}")


def ask_ollama(tag: str, prompt: str) -> tuple[str, dict]:
    base = {"model": tag, "stream": False, "format": "json", "options": {"temperature": 0, "num_predict": 400},
            "messages": [{"role": "user", "content": prompt}]}
    for body in ({**base, "think": False}, base):      # turn off "thinking" where a model supports it
        try:
            out = post("http://localhost:11434/api/chat", body, {}, 600)
            return out["message"]["content"], {"input_tokens": out.get("prompt_eval_count"), "output_tokens": out.get("eval_count")}
        except urllib.error.HTTPError as e:
            if body is base:
                raise
            print(f"  retrying without think=false ({e.code})", flush=True)


def openrouter_model(candidates: list[str], key: str) -> str:
    req = urllib.request.Request("https://openrouter.ai/api/v1/models", headers={"Authorization": f"Bearer {key}"})
    ids = {m["id"] for m in json.load(urllib.request.urlopen(req, timeout=60))["data"]}
    for c in candidates:
        if c in ids:
            return c
    raise SystemExit(f"::error::none of {candidates} is listed on OpenRouter right now")


def ask_openrouter(model: str, prompt: str, key: str) -> tuple[str, dict]:
    body = {"model": model, "temperature": 0, "max_tokens": 1500, "response_format": {"type": "json_object"},
            "usage": {"include": True}, "messages": [{"role": "user", "content": prompt}]}
    for attempt in range(6):
        try:
            out = post("https://openrouter.ai/api/v1/chat/completions", body, {"Authorization": f"Bearer {key}"}, 180)
            break
        except urllib.error.HTTPError as e:
            msg = e.read()[:300].decode(errors="replace")
            if e.code == 429 and ("per-day" in msg or "per day" in msg or "daily" in msg.lower()):
                raise SystemExit(f"::warning::daily free limit reached; rerun tomorrow to continue. {msg}")
            if e.code in (429, 502, 503):
                time.sleep(15 * (attempt + 1))
                continue
            raise SystemExit(f"::error::HTTP {e.code}: {msg}")
    else:
        raise SystemExit("::error::OpenRouter kept rate-limiting; rerun later")
    usage = out.get("usage") or {}
    if (usage.get("cost") or 0) > 0:
        raise SystemExit(f"::error::{model} charged ${usage['cost']}; stopping, Phase 5 only uses free models")
    content = ((out.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
    return content, {"input_tokens": usage.get("prompt_tokens"), "output_tokens": usage.get("completion_tokens"),
                     "served_by": out.get("model"), "provider": out.get("provider"), "cost_usd": usage.get("cost", 0)}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--judge", required=True, choices=sorted(LOCAL) + sorted(HOSTED))
    ap.add_argument("--answer-models", default=",".join(MODELS))
    ap.add_argument("--shard", default="0/1")
    a = ap.parse_args()
    i_, n_ = map(int, a.shard.split("/"))
    hosted = a.judge in HOSTED
    key = os.environ.get("OPENROUTER_API_KEY", "")
    if hosted:
        if not key:
            raise SystemExit("::error::OPENROUTER_API_KEY is not set")
        model = openrouter_model(HOSTED[a.judge], key)
    else:
        model = pull_first(LOCAL[a.judge])
    print(f"judge {a.judge} -> {model}", flush=True)
    qmap = {q["id"]: q for q in questions("test")}
    for spec in a.answer_models.split(","):
        done = {r["id"] for r in records(a.judge, spec)}
        todo = [o for k, o in enumerate(read_jsonl(outputs_path("test", spec))) if k % n_ == i_ and o["id"] not in done]
        path = judge_dir(a.judge) / (slug(spec)[:-6] + (f".shard{i_}" if n_ > 1 else "") + ".jsonl")
        path.parent.mkdir(parents=True, exist_ok=True)
        print(f"{spec}: {len(todo)} to judge", flush=True)
        for o in todo:
            prompt = build_prompt(qmap[o["id"]]["q"], o["text"])
            t = time.monotonic()
            raw, meta = ask_openrouter(model, prompt, key) if hosted else ask_ollama(model, prompt)
            rec = {"id": o["id"], "answer_model": spec, "judge": a.judge, "judge_model": model,
                   **decide(raw, o["text"]), "latency_s": round(time.monotonic() - t, 2), "raw": raw[:1500], **meta}
            with open(path, "a") as f:
                f.write(json.dumps(rec) + "\n")
            print(f"  {o['id']} {rec['verdict']} {rec['latency_s']}s", flush=True)
            if hosted:
                time.sleep(3.2)     # stay under 20 requests a minute
