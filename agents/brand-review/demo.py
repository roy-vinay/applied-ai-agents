"""The core loop in the terminal, with a full trace. No API key, no dependencies.

    python demo.py

0. A brief becomes three drafts and five rendered formats, numbers taken only from the offer sheet.
1. An auto-loan draft goes through pre-review: rule fixes, routing, a blocked figure.
2. Legal (Dana) corrects two payment claims on the review link. Each becomes a scoped lesson.
3. A personal-loan draft arrives. Dana's lessons are applied before she sees it.
4. A certificate says "guaranteed". It's accurate there, and the lending lesson stays out.
5. Dana retires a lesson; the next draft goes back to needing her correction.
"""
from __future__ import annotations

from datetime import date

from agent import (BrandRules, Brief, Campaign, ContentSpec, Correction, Figure, LessonStore, MissingFact,
                   TemplateDrafter, prereview, produce)

OFFER_SHEET = {"auto_refi_apr": 4.2, "personal_loan_apr": 9.9, "certificate_apy": 4.1}
RULES = BrandRules()
STORE = LessonStore()

B, D, G, R, Y, X = "\033[1m", "\033[2m", "\033[32m", "\033[31m", "\033[33m", "\033[0m"


def show(title: str, spec: ContentSpec, today: date) -> None:
    print(f"\n{B}{title}{X}")
    print(f"  {D}draft:{X} {spec.headline} | {spec.sub}")
    res = prereview(spec, RULES, STORE, today, OFFER_SHEET)
    print(f"  {D}routed to:{X} {', '.join(sorted(res.routed_to))}")
    for c in res.changes:
        tag = f"{Y}lesson{X}" if c.kind == "lesson" else f"{G}rule{X}  "
        print(f"  {tag} {c.field}: '{c.before}' -> '{c.after}'\n         {D}{c.source}{X}")
    for f in res.findings:
        if not f.ok:
            print(f"  {R}BLOCKED{X} {f.evidence}. Suggested: {f.suggested_fix}")
    print(f"  {D}ready for review:{X} {G + 'yes' + X if res.can_send else R + 'no' + X}"
          f"   {D}final:{X} {res.spec.headline} | {res.spec.sub}")
    return res


def main() -> None:
    print(f"{B}0. Brief: 'Auto loan refinance for Pacific NW members.' The agent drafts three directions{X}")
    brief = Brief("Auto loan refinance", "auto_refi")
    for spec in TemplateDrafter().directions(brief, OFFER_SHEET):
        print(f"  {D}draft:{X} {spec.headline} | {spec.sub}")
    p = produce(brief, {"_name": "Q4 offer sheet, Oct 28", **OFFER_SHEET}, RULES, None, date(2026, 10, 20))
    for fmt, r in p.outputs.items():
        print(f"  {G}rendered{X} {r.layout.name:20} {D}{r.layout.w}x{r.layout.h}, headline: {' / '.join(r.lines['headline'])}{X}")
    try:
        TemplateDrafter().draft(Brief("Jumbo mortgage", "mortgage"), OFFER_SHEET)
    except MissingFact as e:
        print(f"  {Y}asks instead of guessing:{X} {e}")

    c = Campaign("Auto loan refinance")
    c.move("plan", "agent", "drafted plan and 3 directions")
    c.move("create", "marketer", "Brielle approved the benefit-led direction")

    refi = ContentSpec("Auto loan refinance", "lending", "auto_refi", "pnw",
                       "Refinance your auto loan and save",
                       "Guaranteed savings at 4.2% APR and lower your monthly payment.",
                       bg_color="#5A8FA8", figures=(Figure("Auto refi APR", 4.3, "auto_refi_apr"),))
    res = show("1. Auto loan refinance: first draft (a typo'd rate, low contrast, no disclaimer)", refi, date(2026, 10, 20))

    print(f"\n{B}   Brielle fixes the rate to match the offer sheet, then sends it to Legal.{X}")
    fixed = res.spec.with_(figures=(Figure("Auto refi APR", 4.2, "auto_refi_apr"),))
    res = prereview(fixed, RULES, STORE, date(2026, 10, 20), OFFER_SHEET)
    c.move("review", "marketer", "sent to Dana Ruiz (Legal)", blocked=not res.can_send)

    print(f"\n{B}2. Dana reviews on the no-login link and makes two corrections, scoped to all lending{X}")
    for corr in (
        Correction("Dana Ruiz", "legal", "sub", r"guaranteed ", "", "claim", note="No 'guaranteed' in lending claims"),
        Correction("Dana Ruiz", "legal", "sub", r"and lower your monthly payment",
                   "and you could lower your monthly payment", "claim",
                   note="'could lower', not 'lower', in payment claims"),
    ):
        l = STORE.learn(corr, {"product_line": "lending"}, date(2026, 10, 22))
        print(f"  learned {l.id}: {l.text}  {D}(owner {l.owner}, scope {l.scope}, reason {l.reason}){X}")
    c.move("create", "reviewer", "Dana requested 2 changes")
    c.move("review", "marketer", "round 2")
    c.move("approved", "reviewer", "Dana approved")

    loan = ContentSpec("Personal loan promo", "lending", "personal_loan", "pnw", "One payment, less stress",
                       "Consolidate at a guaranteed 9.9% APR and lower your monthly payment.",
                       figures=(Figure("Personal loan APR", 9.9, "personal_loan_apr"),))
    show("3. Personal loan promo: Dana's lessons apply before she sees it", loan, date(2026, 10, 31))

    cd = ContentSpec("Certificate special", "deposits", "certificate", "pnw", "A guaranteed 4.1% APY",
                     "Guaranteed rate for 12 months.", figures=(Figure("12-month APY", 4.1, "certificate_apy"),))
    show("4. Certificate: 'guaranteed' is accurate on a fixed rate, so the lending lesson stays out", cd, date(2026, 10, 31))

    STORE.retire("lsn_0002", "legal")
    print(f"\n{B}5. Dana retires lsn_0002. Only Legal or an admin could have.{X}")
    try:
        STORE.retire("lsn_0001", "brand")
    except PermissionError as e:
        print(f"  {R}refused:{X} {e}")
    show("   Next lending draft: the retired lesson no longer fires", loan.with_(campaign="Loan, round 2"), date(2026, 11, 2))

    print(f"\n{B}Campaign log{X} ({c.name}, {c.rounds} review rounds)")
    for frm, to, actor, note in c.log:
        print(f"  {frm:>8} -> {to:<9} {D}{actor:<9}{X} {note}")


if __name__ == "__main__":
    main()
