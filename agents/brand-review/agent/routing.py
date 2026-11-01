"""Who reviews a draft. Each function owns its routing rule; the agent only suggests, people send."""
from __future__ import annotations

import re

from .rules import states_rate
from .spec import ContentSpec

PAYMENT_OR_CLAIM = re.compile(r"\b(save|savings|lower|payment|guarantee[d]?|best|free)\b", re.I)


def route(spec: ContentSpec, new_image: bool = False) -> set[str]:
    who: set[str] = set()
    if states_rate(spec) or PAYMENT_OR_CLAIM.search(spec.text()):
        who.add("legal")
    if spec.product_line == "cards" or re.search(r"\bfees?\b", spec.text(), re.I):
        who.update({"legal", "compliance"})
    if spec.product == "mortgage":
        who.add("compliance")
    if new_image or spec.product_line == "branch":
        who.add("brand")
    return who or {"brand"}
