"""The whole loop for one draft: brief -> draft -> pre-review -> render every format -> check what was drawn."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from .drafter import Brief, Drafter, TemplateDrafter
from .lessons import LessonStore
from .prereview import PreReviewResult, prereview
from .render import Rendered, check_rendered, render_all
from .rules import BrandRules
from .spec import Finding


@dataclass
class Production:
    review: PreReviewResult
    outputs: dict[str, Rendered]
    render_findings: list[Finding]

    @property
    def blocked(self) -> list[Finding]:
        return self.review.blocked + [f for f in self.render_findings if f.required and not f.ok]

    @property
    def can_send(self) -> bool:
        return not self.blocked and not self.review.conflicts


def produce(brief: Brief, offer_sheet: dict, rules: BrandRules, store: LessonStore | None, today: date,
            drafter: Drafter | None = None) -> Production:
    source_name = offer_sheet.get("_name", "")
    facts = {k: v for k, v in offer_sheet.items() if not k.startswith("_")}
    spec = (drafter or TemplateDrafter()).draft(brief, facts)
    review = prereview(spec, rules, store, today, facts)
    outputs = render_all(review.spec, rules, source_name)
    return Production(review, outputs, check_rendered(review.spec, outputs, facts, source_name))
