"""Generate the example graphics shown in the README, from briefs, through the full pipeline.

    python render_examples.py            # writes docs/formats/*.svg
    python render_examples.py --check    # also fail if any example can't be sent (used in CI)
"""
from __future__ import annotations

import sys
from datetime import date
from pathlib import Path

from agent import BrandRules, Correction, LessonStore
from agent.drafter import Brief
from agent.pipeline import produce

OFFER_SHEET = {"_name": "Q4 offer sheet, Oct 28", "auto_refi_apr": 4.2, "personal_loan_apr": 9.9,
               "certificate_6m_apy": 3.6, "certificate_12m_apy": 4.0, "certificate_24m_apy": 3.8,
               "balance_transfer_intro_apr": 0.0}
BRIEFS = [
    Brief("Auto loan refinance", "auto_refi", direction="benefit"),
    Brief("Certificate rates infographic", "certificate",
          compare=("certificate_6m_apy", "certificate_12m_apy", "certificate_24m_apy")),
]
OUT = Path(__file__).parent / "docs" / "formats"


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    store = LessonStore()
    store.learn(Correction("Dana Ruiz", "legal", "sub", r"guaranteed ", "", "claim",
                           note="No 'guaranteed' in lending claims"), {"product_line": "lending"}, date(2026, 10, 22))
    ok = True
    for brief in BRIEFS:
        p = produce(brief, OFFER_SHEET, BrandRules(), store, date(2026, 10, 31))
        slug = brief.product.replace("_", "-")
        for fmt, r in p.outputs.items():
            (OUT / f"{slug}-{fmt.replace('_', '-')}.svg").write_text(r.svg + "\n")
        status = "ready to send" if p.can_send else "BLOCKED: " + "; ".join(f.evidence for f in p.blocked)
        print(f"{brief.campaign}: {len(p.outputs)} formats, {len(p.review.changes)} pre-review changes, {status}")
        ok &= p.can_send
    if "--check" in sys.argv and not ok:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
