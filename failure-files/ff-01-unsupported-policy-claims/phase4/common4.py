"""Phase 4 paths and helpers. Reuses Phase 3's splits (dev = Phase 2 answers, test = Phase 3 answers)."""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "phase3"))
from common3 import *  # noqa: E402,F401,F403
