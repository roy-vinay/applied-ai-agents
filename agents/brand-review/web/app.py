"""Glue between the web page and the agent core. Runs in the browser under Pyodide.

Nothing here decides anything: it collects the page's inputs, calls the same agent code
the tests and benchmark use, and returns what it produced as JSON.
"""
from __future__ import annotations

import contextlib
import io
import json
from datetime import date

from agent import BrandRules, Brief, Correction, LessonStore, MissingFact, TemplateDrafter, prereview
from agent.drafter import PRODUCTS
from agent.render import check_rendered, render_all

TODAY = date(2026, 10, 31)
RULES = BrandRules()
CHART_KEYS = ("certificate_6m_apy", "certificate_12m_apy", "certificate_24m_apy")


def legal_lessons() -> LessonStore:
    """What Dana (Legal) taught the agent on an earlier auto-loan review, scoped to all lending."""
    s = LessonStore()
    s.learn(Correction("Dana Ruiz", "legal", "sub", r"guaranteed ", "", "claim",
                       note="No 'guaranteed' in lending claims"), {"product_line": "lending"}, date(2026, 10, 22))
    s.learn(Correction("Dana Ruiz", "legal", "sub", r"and lower your monthly payment",
                       "and you could lower your monthly payment", "claim",
                       note="'could lower', not 'lower', in payment claims"), {"product_line": "lending"}, date(2026, 10, 22))
    return s


def run(params_json: str) -> str:
    p = json.loads(params_json)
    facts = {k: float(v) for k, v in p["offer"].items()}
    source_name = p.get("offer_name", "Q4 offer sheet, Oct 28")
    compare = CHART_KEYS if p.get("infographic") and p["product"] == "certificate" else ()
    brief = Brief(p.get("campaign", "Campaign"), p["product"], p.get("region", "pnw"), p.get("direction", "benefit"), compare)
    drafter = TemplateDrafter()
    try:
        directions = [] if compare else [s.headline for s in drafter.directions(brief, facts)]
        spec = drafter.draft(brief, facts)
    except MissingFact as e:
        return json.dumps({"asks": str(e)})

    draft = {"headline": spec.headline, "sub": spec.sub, "cta": spec.cta}
    edits = {k: p[k] for k in ("headline", "sub") if p.get(k)}
    if p.get("image") is not None and not compare:
        edits["image"] = p["image"] or None
    spec = spec.with_(**edits)

    store = legal_lessons() if p.get("lessons") else None
    review = prereview(spec, RULES, store, TODAY, facts)
    outputs = render_all(review.spec, RULES, source_name)
    drawn = check_rendered(review.spec, outputs, facts, source_name)
    findings = review.findings + drawn
    blocked = [f for f in findings if f.required and not f.ok]

    return json.dumps({
        "directions": directions,
        "draft": draft,
        "you_typed": edits,
        "final": {"headline": review.spec.headline, "short_headline": review.spec.short_headline,
                  "sub": review.spec.sub, "disclaimer": review.spec.disclaimer},
        "routed_to": sorted(review.routed_to),
        "changes": [vars(c) for c in review.changes],
        "conflicts": [[a.text, b.text] for a, b in review.conflicts],
        "checks": [{"rule": f.rule, "ok": f.ok, "required": f.required, "evidence": f.evidence,
                    "fix": f.suggested_fix} for f in findings],
        "can_send": not blocked and not review.conflicts,
        "formats": [{"key": k, "name": r.layout.name, "w": r.layout.w, "h": r.layout.h, "svg": r.svg}
                    for k, r in outputs.items()],
        "products": list(PRODUCTS),
    })


def run_evals() -> str:
    import evals.run_evals as ev
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ev.main()
    return buf.getvalue()
