"""Phase 3, step 1: put the 100 new test questions to the same three models, with the same frozen
system prompt as Phase 2. Answers are saved and never re-asked.

    python run_test_answers.py --dry-run
    python run_test_answers.py --models ollama:llama3.2:3b
"""
from __future__ import annotations

import argparse
import json

from common3 import CITE, MODELS, check_freeze, outputs_path, questions, read_jsonl, system_prompt
from providers import get_provider

ap = argparse.ArgumentParser()
ap.add_argument("--models", default=",".join(MODELS))
ap.add_argument("--dry-run", action="store_true")
args = ap.parse_args()

check_freeze("test")
qs, system = questions("test"), system_prompt()
for spec in args.models.split(","):
    path = outputs_path("test", spec)
    done = {o["id"] for o in read_jsonl(path)}
    todo = [q for q in qs if q["id"] not in done]
    print(f"{spec}: {len(todo)} to ask, {len(done)} already saved")
    if args.dry_run or not todo:
        continue
    provider = get_provider(spec)
    path.parent.mkdir(parents=True, exist_ok=True)
    for i, q in enumerate(todo, 1):
        try:
            r = provider.answer(system, q["q"])
        except RuntimeError as e:
            print(f"  {q['id']} skipped: {e}", flush=True)
            continue
        rec = {"id": q["id"], "model": spec, "text": r.text, "cites": sorted(set(CITE.findall(r.text))),
               "latency_s": r.latency_s, "input_tokens": r.input_tokens, "output_tokens": r.output_tokens,
               "truncated": r.truncated}
        with open(path, "a") as f:
            f.write(json.dumps(rec) + "\n")
        print(f"  {spec} {i}/{len(todo)} {q['id']} {r.latency_s}s", flush=True)
