"""Phase 2: put the frozen questions to real models and save every answer.

    python run_models.py --dry-run
    python run_models.py --models ollama:llama3.2:3b,ollama:qwen2.5:3b,ollama:gemma2:2b

Answers are saved and reused: rerunning only asks questions a model hasn't answered yet,
so nothing is ever paid for twice. Refuses to run if any frozen file has changed.
"""
from __future__ import annotations

import argparse
import json

from common import CITE, check_freeze, outputs_path, questions, read_jsonl, system_prompt
from providers import get_provider

DEFAULT = "ollama:llama3.2:3b,ollama:qwen2.5:3b,ollama:gemma2:2b"

ap = argparse.ArgumentParser()
ap.add_argument("--models", default=DEFAULT)
ap.add_argument("--dry-run", action="store_true")
ap.add_argument("--max-calls", type=int, default=400)
args = ap.parse_args()

check_freeze()
qs, system = questions(), system_prompt()
plan = []
for spec in args.models.split(","):
    done = {o["id"] for o in read_jsonl(outputs_path(spec))}
    todo = [q for q in qs if q["id"] not in done]
    plan.append((spec, todo))
    print(f"{spec}: {len(todo)} to ask, {len(done)} already saved")
total = sum(len(t) for _, t in plan)
print(f"total calls: {total} (cap {args.max_calls}); local models cost $0")
if args.dry_run or total == 0:
    raise SystemExit
if total > args.max_calls:
    raise SystemExit("over the call cap; raise --max-calls if intended")

for spec, todo in plan:
    provider = get_provider(spec)
    path = outputs_path(spec)
    path.parent.mkdir(exist_ok=True)
    for i, q in enumerate(todo, 1):
        try:
            r = provider.answer(system, q["q"])
        except RuntimeError as e:  # skip and report; a rerun asks only what's missing
            print(f"  {spec} {q['id']} skipped: {e}", flush=True)
            continue
        rec = {"id": q["id"], "model": spec, "text": r.text, "cites": sorted(set(CITE.findall(r.text))),
               "latency_s": r.latency_s, "input_tokens": r.input_tokens, "output_tokens": r.output_tokens,
               "truncated": r.truncated}
        with open(path, "a") as f:
            f.write(json.dumps(rec) + "\n")
        print(f"  {spec} {i}/{len(todo)} {q['id']} {r.latency_s}s", flush=True)
