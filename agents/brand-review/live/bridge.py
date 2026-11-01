"""Bridge between the copied web demo and the agent core. Runs in the browser under Pyodide.

The demo describes an ad in its own shape (head, sub, disc, bg, photo, data rows). This module
turns that into a ContentSpec and hands it to the real code: agent/render.py draws the ad,
agent/rules.py and the render checks decide what passes, and agent/lessons.py holds what
Legal has taught. Nothing here makes a decision of its own.
"""
from __future__ import annotations

import json
from datetime import date

from agent import BrandRules, ContentSpec, Correction, Figure, LessonStore, check, prereview
from agent.drafter import Brief, TemplateDrafter
from agent.render import check_rendered, render

TODAY = date(2026, 10, 30)
# The demo's fictional Q4 offer sheet: every rate any demo campaign prints.
OFFER = {"auto_refi_apr": 4.2, "personal_loan_apr": 9.9, "certificate_12m_apy": 4.0, "savings_cert_apy": 4.1,
         "balance_transfer_intro_apr": 0.0, "mortgage_30y_apr": 6.1, "card_cash_back": 1.5,
         "summer_cd_apy": 4.0}
OFFER_NAME = "Q4 offer sheet (Oct 28)"
LINES = {"refi": "lending", "ploan": "lending", "mortgage": "lending", "balance": "cards", "card": "cards",
         "apy": "deposits", "springcd": "deposits", "savings": "deposits", "summer": "deposits", "info": "deposits",
         "youth": "deposits", "student": "deposits", "holiday": "branch", "hours": "branch", "branch": "branch",
         "homeeq": "lending"}

STORE = LessonStore()
PLOAN = "Consolidate at 9.9% APR and lower your monthly payment."


def reset() -> str:
    """Restart: Legal's earlier lesson from Oct 22 is the only thing the agent knows."""
    global STORE
    STORE = LessonStore()
    l = STORE.learn(Correction("Dana Ruiz", "legal", "sub", r"guaranteed ", "", "claim",
                               note="Avoid 'guaranteed' in lending claims"), {"product_line": "lending"}, date(2026, 10, 22))
    return l.id


def _spec(d: dict) -> ContentSpec:
    figs = ()
    if d.get("data"):  # infographic rows: [label, value shown, value on the offer sheet]
        figs = tuple(Figure(str(r[0]), float(r[1]), f"chart_{r[0]}") for r in d["data"])
    image = None
    if d.get("photoMissing"):
        image = "missing-not-approved"
    elif d.get("photo"):
        image = "branch-ballard-2026"
    return ContentSpec(d.get("campaign", "Campaign"), LINES.get(d.get("id", ""), "deposits"), d.get("id", ""),
                       "pnw", d.get("head") or "", d.get("sub") or "", d.get("cta") or "Learn more",
                       d.get("short") or "", d.get("disc") or "", "#FFFFFF", d.get("bg") or "#0E4D64", image, figs)


def _facts(d: dict) -> dict:
    facts = dict(OFFER)
    for r in d.get("data") or []:
        facts[f"chart_{r[0]}"] = float(r[2])
    return facts


def _rules(d: dict) -> BrandRules:
    return BrandRules(min_contrast=float(d.get("min_contrast", 4.5)), banner_max_chars=int(d.get("banner_max", 30)))


def render_ad(payload: str) -> str:
    d = json.loads(payload)
    spec = _spec(d)
    fmt = "infographic" if spec.figures and d["fmt"] != "leaderboard_728x90" else d["fmt"]
    return render(spec, fmt, _rules(d), OFFER_NAME).svg


def check_ad(payload: str) -> str:
    """Every rule and every render check, for the post plus the banner, as the demo's checks panel needs them."""
    d = json.loads(payload)
    spec, rules, facts = _spec(d), _rules(d), _facts(d)
    fmts = ["infographic", "leaderboard_728x90"] if spec.figures else ["post_1x1", "leaderboard_728x90"]
    outs = {f: render(spec, f, rules, OFFER_NAME) for f in fmts}
    found = check(spec, rules, facts) + check_rendered(spec, outs, facts, OFFER_NAME)
    return json.dumps([{"rule": f.rule, "ok": f.ok, "required": f.required, "evidence": f.evidence} for f in found])


def learn_payment_claim() -> str:
    """Dana's correction on the refinance review, scoped to all lending."""
    l = STORE.learn(Correction("Dana Ruiz", "legal", "sub", r"and lower your monthly payment",
                               "and you could lower your monthly payment", "claim",
                               note="'could lower', not 'lower', in payment claims"),
                    {"product_line": "lending"}, TODAY)
    return l.id


def retire(lesson_id: str) -> None:
    STORE.retire(lesson_id, "legal")


def ploan_prereview() -> str:
    """Pre-review the personal-loan draft with whatever lessons are active right now."""
    spec = ContentSpec("Personal loan promo", "lending", "personal_loan", "pnw", "One payment, less stress", PLOAN,
                       disclaimer="APR = Annual Percentage Rate. Illustrative offer.")
    res = prereview(spec, BrandRules(), STORE, TODAY)
    lessons = [{"id": c.source.split()[1], "source": c.source} for c in res.changes if c.kind == "lesson"]
    return json.dumps({"sub": res.spec.sub, "lessons": lessons})


def directions() -> str:
    return json.dumps([s.headline for s in TemplateDrafter().directions(Brief("Auto loan refinance", "auto_refi"), OFFER)])
