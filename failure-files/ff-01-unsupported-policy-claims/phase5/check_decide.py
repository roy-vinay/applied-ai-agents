"""Proves decide.py matches the frozen Phase 3 judge: re-decide every saved Phase 3 test verdict."""
from common5 import MODELS, outputs_path, read_jsonl
from decide import decide
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "phase3"))
from common3 import judge_records  # noqa: E402

bad = n = 0
for spec in MODELS:
    outs = {o["id"]: o for o in read_jsonl(outputs_path("test", spec))}
    for r in judge_records("test", spec):
        n += 1
        bad += decide(r["raw"], outs[r["id"]]["text"])["verdict"] != r["verdict"]
print(f"{n - bad}/{n} Phase 3 verdicts reproduced")
sys.exit(1 if bad else 0)
