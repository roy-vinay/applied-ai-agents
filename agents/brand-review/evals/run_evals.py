"""Must-pass evals: properties that can never fail. One failure blocks the change in CI.

    python -m evals.run_evals
"""
from __future__ import annotations

import sys
from datetime import date

from agent.drafter import DIRECTIONS, PRODUCTS, Brief, MissingFact, TemplateDrafter
from agent.pipeline import produce
from agent.render import FORMATS, render_all, check_rendered
from agent import (BrandRules, Campaign, ContentSpec, Correction, Figure, IllegalMove, LessonStore,
                   check, contrast_ratio, prereview)

D = date(2026, 10, 22)
TODAY = date(2026, 10, 31)
SRC = {"auto_refi_apr": 4.2, "certificate_apy": 4.1}
R = BrandRules()


def refi(**kw) -> ContentSpec:
    base = dict(campaign="Auto refi", product_line="lending", product="auto_refi", region="pnw",
                headline="Refinance your auto loan and save",
                sub="Guaranteed savings at 4.2% APR and lower your monthly payment.",
                figures=(Figure("Auto refi APR", 4.2, "auto_refi_apr"),))
    base.update(kw)
    return ContentSpec(**base)


def cert(**kw) -> ContentSpec:
    base = dict(campaign="Certificate", product_line="deposits", product="certificate", region="pnw",
                headline="A guaranteed 4.1% APY", sub="Guaranteed rate for 12 months.",
                figures=(Figure("12-month APY", 4.1, "certificate_apy"),))
    base.update(kw)
    return ContentSpec(**base)


def dana_lessons() -> LessonStore:
    s = LessonStore()
    s.learn(Correction("Dana Ruiz", "legal", "sub", r"guaranteed ", "", "claim",
                       note="No 'guaranteed' in lending claims"), {"product_line": "lending"}, D)
    s.learn(Correction("Dana Ruiz", "legal", "sub", r"and lower your monthly payment",
                       "and you could lower your monthly payment", "claim",
                       note="'could lower', not 'lower', in payment claims"), {"product_line": "lending"}, D)
    return s


def blocked_rules(spec, **kw):
    return {f.rule for f in prereview(spec, R, kw.pop("store", None), TODAY, SRC, **kw).blocked}


def e01():
    """A rate never ships without a disclaimer."""
    res = prereview(refi(disclaimer=""), R, None, TODAY, SRC)
    assert res.spec.disclaimer and any(c.field == "disclaimer" and c.kind == "rule" for c in res.changes)
    assert all(f.ok for f in check(res.spec, R, SRC) if f.rule == "disclaimer")


def e02():
    """A figure that disagrees with the offer sheet blocks sending, and is never auto-changed."""
    res = prereview(refi(figures=(Figure("Auto refi APR", 4.3, "auto_refi_apr"),)), R, None, TODAY, SRC)
    assert "figure:Auto refi APR" in {f.rule for f in res.blocked} and not res.can_send
    assert res.spec.figures[0].value == 4.3


def e03():
    """A figure with no source field blocks sending."""
    assert "figure:Auto refi APR" in blocked_rules(refi(figures=(Figure("Auto refi APR", 4.2, "nope"),)))


def e04():
    """Text below the contrast minimum gets fixed, and the fix really meets WCAG."""
    res = prereview(refi(bg_color="#7FB3C8"), R, None, TODAY, SRC)
    assert contrast_ratio("#FFFFFF", "#7FB3C8") < 4.5 <= contrast_ratio(res.spec.text_color, res.spec.bg_color)


def e05():
    """An unapproved image blocks sending."""
    assert "approved_image" in blocked_rules(refi(image="stock-smiling-couple"))


def e06():
    """A lending lesson fires on another lending product."""
    s = dana_lessons()
    loan = refi(campaign="Personal loan", product="personal_loan",
                sub="Consolidate at 9.9% APR and lower your monthly payment.", figures=())
    res = prereview(loan, R, s, TODAY, SRC)
    assert "you could lower" in res.spec.sub and any(c.kind == "lesson" for c in res.changes)


def e07():
    """A lending lesson never fires outside lending ("guaranteed" is accurate on a fixed rate)."""
    res = prereview(cert(), R, dana_lessons(), TODAY, SRC)
    assert "Guaranteed" in res.spec.sub and not res.lessons_applied


def e08():
    """A region-scoped lesson stays in its region."""
    s = LessonStore()
    s.learn(Correction("Jordan Kim", "brand", "sub", r"stop by", "visit us", "tone"),
            {"product_line": "branch", "region": "pnw"}, D)
    spec = lambda region: ContentSpec("Hours", "branch", "branch_hours", region, "New weekend hours",
                                      "Open Saturdays. Stop by and say hello.")
    assert "Visit us" in prereview(spec("pnw"), R, s, TODAY).spec.sub
    assert "Stop by" in prereview(spec("national"), R, s, TODAY).spec.sub


def e09():
    """A retired lesson never fires."""
    s = dana_lessons()
    s.retire("lsn_0001", "legal")
    assert "Guaranteed" in prereview(refi(), R, s, TODAY, SRC).spec.sub


def e10():
    """Only the owning function (or an admin) can promote or retire a lesson."""
    s = dana_lessons()
    for act in (s.promote, s.retire):
        try:
            act("lsn_0001", "brand")
            raise AssertionError("brand changed a legal lesson")
        except PermissionError:
            pass
    s.promote("lsn_0001", "legal")
    assert s.get("lsn_0001").status == "rule"


def e11():
    """Conflicting lessons: neither is applied, and the draft can't be sent until a person decides."""
    s = dana_lessons()
    s.learn(Correction("Priya Shah", "compliance", "sub", r"and lower your monthly payment",
                       "and may reduce your monthly payment", "legal"), {"product_line": "lending"}, D)
    res = prereview(refi(sub="Refinance at 4.2% APR and lower your monthly payment."), R, s, TODAY, SRC)
    # Compliance isn't routed on a plain auto-loan draft, so only Legal's lesson applies...
    assert "you could lower" in res.spec.sub and not res.conflicts
    # ...but a draft that mentions fees goes to both, and the two lessons conflict.
    res2 = prereview(refi(sub="Refinance at 4.2% APR, no fees, and lower your monthly payment."), R, s, TODAY, SRC)
    assert res2.conflicts and "lower your monthly payment" in res2.spec.sub and not res2.can_send


def e12():
    """Every change the agent makes carries a source a person can read."""
    res = prereview(refi(bg_color="#7FB3C8", disclaimer=""), R, dana_lessons(), TODAY, SRC)
    assert res.changes and all(c.source.strip() and c.kind in ("rule", "lesson") for c in res.changes)


def e13():
    """The workflow can't skip review, send a blocked draft, or publish without a person."""
    c = Campaign("Auto refi")
    c.move("plan", "agent")
    for bad in (lambda: c.move("approved", "reviewer"), lambda: c.move("create", "agent")):
        try:
            bad()
            raise AssertionError("illegal move allowed")
        except IllegalMove:
            pass
    c.move("create", "marketer")
    try:
        c.move("review", "marketer", blocked=True)
        raise AssertionError("blocked draft was sent")
    except IllegalMove:
        pass
    c.move("review", "marketer")
    c.move("approved", "reviewer")
    try:
        c.move("live", "agent")
        raise AssertionError("agent published")
    except IllegalMove:
        pass
    c.move("live", "marketer")
    assert c.stage == "live" and c.rounds == 1


def e14():
    """The same correction twice is one lesson, not two."""
    s = dana_lessons()
    n = len(s)
    s.learn(Correction("Dana Ruiz", "legal", "sub", r"guaranteed ", "", "claim"), {"product_line": "lending"}, D)
    assert len(s) == n


def e15():
    """Lessons unused for six months are flagged to their owner."""
    s = dana_lessons()
    assert not s.stale(TODAY) and len(s.stale(date(2027, 6, 1))) == 2


OFFER = {"_name": "Q4 offer sheet, Oct 28", "auto_refi_apr": 4.2, "personal_loan_apr": 9.9,
         "certificate_6m_apy": 3.6, "certificate_12m_apy": 4.0, "certificate_24m_apy": 3.8,
         "balance_transfer_intro_apr": 0.0}
FACTS = {k: v for k, v in OFFER.items() if not k.startswith("_")}
CHART = Brief("Rates", "certificate", compare=("certificate_6m_apy", "certificate_12m_apy", "certificate_24m_apy"))


def all_briefs():
    return [Brief(f"{p} {d}", p, direction=d) for p in PRODUCTS for d in DIRECTIONS] + [CHART]


def e16():
    """The drafter never writes a number that isn't in the offer sheet."""
    import re
    for b in all_briefs():
        spec = TemplateDrafter().draft(b, FACTS)
        for num in re.findall(r"(\d+(?:\.\d+)?)%", spec.text()):
            assert float(num) in FACTS.values(), f"{b.campaign}: {num}% invented"


def e17():
    """When the offer sheet lacks a fact, the drafter asks instead of guessing."""
    for b, facts in ((Brief("x", "auto_refi"), {}), (Brief("x", "mortgage"), FACTS),
                     (Brief("x", "certificate", compare=("certificate_60m_apy",)), FACTS)):
        try:
            TemplateDrafter().draft(b, facts)
            raise AssertionError(f"{b.product}: drafted without the fact")
        except MissingFact:
            pass


def e18():
    """Every brief renders in every format, fits every text box, and is ready to send."""
    for b in all_briefs():
        p = produce(b, OFFER, R, None, TODAY)
        assert p.can_send, f"{b.campaign}: {[f.evidence for f in p.blocked]}"
        assert len(p.outputs) == (1 if b.compare else len(FORMATS))


def e19():
    """When a rate is stated, every rendered format carries the full disclaimer."""
    p = produce(Brief("Refi", "auto_refi", direction="rate"), OFFER, R, None, TODAY)
    for fmt, r in p.outputs.items():
        assert " ".join(r.lines["disclaimer"]) == p.review.spec.disclaimer, fmt
        assert all(line in r.svg for line in r.lines["disclaimer"]), fmt   # drawn, not just planned


def e20():
    """The banner is re-laid out with the short headline, not shrunk from the post."""
    p = produce(Brief("Refi", "auto_refi"), OFFER, R, None, TODAY)
    lb, post = p.outputs["leaderboard_728x90"], p.outputs["post_1x1"]
    assert " ".join(lb.lines["headline"]) == p.review.spec.short_headline != p.review.spec.headline
    assert "sub" not in lb.lines and "sub" in post.lines


def e21():
    """Infographic bars match the offer sheet and print their source; a tampered bar is blocked."""
    p = produce(CHART, OFFER, R, None, TODAY)
    assert p.can_send and "Q4 offer sheet" in p.outputs["infographic"].lines["source"][0]
    spec = p.review.spec
    bad = spec.with_(figures=(spec.figures[0].__class__("6-month", 3.9, "certificate_6m_apy"),) + spec.figures[1:])
    found = check_rendered(bad, render_all(bad, R, OFFER["_name"]), FACTS, OFFER["_name"])
    assert any(not f.ok and "6-month" in f.rule for f in found)


def e22():
    """A number that isn't in the offer sheet can't sneak into rendered copy."""
    spec = TemplateDrafter().draft(Brief("Refi", "auto_refi"), FACTS).with_(sub="Rates as low as 3.9% APR.",
                                                                              disclaimer="APR = Annual Percentage Rate.")
    found = check_rendered(spec, render_all(spec, R), FACTS)
    assert any(not f.ok and "3.9%" in f.rule for f in found)


def e23():
    """An image outside the approved library renders as a visible placeholder and blocks sending."""
    spec = TemplateDrafter().draft(Brief("Refi", "auto_refi"), FACTS).with_(image="stock-smiling-couple")
    outs = render_all(spec, R)
    assert "Image needed" in outs["post_1x1"].svg
    assert any(not f.ok and f.rule.endswith(":image") for f in check_rendered(spec, outs, FACTS))


def e24():
    """Fixing this campaign only corrects the draft and teaches nothing: the next lending draft repeats the mistake."""
    from agent import apply_correction
    s = LessonStore()
    c = Correction("Dana Ruiz", "legal", "sub", r"and lower your monthly payment",
                   "and you could lower your monthly payment", "claim")
    out = apply_correction(refi(), c, teach=False, store=s)
    assert "you could lower" in out.spec.sub and out.lesson is None and len(s) == 0
    nxt = refi(campaign="Personal loan", product="personal_loan", figures=(),
               sub="Consolidate at 9.9% APR and lower your monthly payment.")
    assert "you could lower" not in prereview(nxt, R, s, TODAY, SRC).spec.sub


def e25():
    """Teaching the agent creates an owned, scoped lesson: later lending drafts arrive fixed, other products don't change."""
    from agent import apply_correction
    s = LessonStore()
    c = Correction("Dana Ruiz", "legal", "sub", r"guaranteed ", "", "claim", note="No 'guaranteed' in lending claims")
    out = apply_correction(refi(), c, teach=True, store=s, scope={"product_line": "lending"}, today=D)
    assert out.lesson and out.lesson.owner == "legal" and out.lesson.status == "context" and "taught" in out.change.source
    loan = refi(campaign="Personal loan", product="personal_loan", figures=(),
                sub="Consolidate at a guaranteed 9.9% APR.")
    assert "guaranteed" not in prereview(loan, R, s, TODAY, SRC).spec.sub.lower()
    assert "Guaranteed" in prereview(cert(), R, s, TODAY, SRC).spec.sub


CASES = [e01, e02, e03, e04, e05, e06, e07, e08, e09, e10, e11, e12, e13, e14, e15,
         e16, e17, e18, e19, e20, e21, e22, e23, e24, e25]


def main() -> int:
    failed = 0
    for case in CASES:
        name = f"{case.__name__.upper()}  {case.__doc__}"
        try:
            case()
            print(f"PASS  {name}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"FAIL  {name}  ({type(e).__name__}: {e})")
    print(f"\n{len(CASES) - failed}/{len(CASES)} must-pass evals passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
