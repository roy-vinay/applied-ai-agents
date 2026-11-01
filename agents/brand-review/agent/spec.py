"""The content spec: one structured description of an ad that every format renders from.

Agents edit the spec, never pixels. That is what makes every change checkable and explainable.
"""
from __future__ import annotations

from dataclasses import dataclass, field, replace

TEXT_FIELDS = ("headline", "short_headline", "sub", "cta", "disclaimer")


@dataclass(frozen=True)
class Figure:
    """A number printed on the asset, bound to a field in a source table (an offer sheet)."""
    label: str          # "12-month certificate"
    value: float        # what the asset says
    source_field: str   # key in the offer sheet, e.g. "cert_12m_apy"


@dataclass(frozen=True)
class ContentSpec:
    campaign: str
    product_line: str           # lending, deposits, cards, branch
    product: str                # auto_refi, personal_loan, certificate, ...
    region: str                 # pnw, national, ...
    headline: str
    sub: str = ""
    cta: str = "Learn more"
    short_headline: str = ""    # used on the 728x90 banner
    disclaimer: str = ""
    text_color: str = "#FFFFFF"
    bg_color: str = "#0E4D64"
    image: str | None = None    # asset id from the approved library, or None
    figures: tuple[Figure, ...] = ()

    def text(self) -> str:
        return " ".join(getattr(self, f) for f in TEXT_FIELDS)

    def with_(self, **changes) -> "ContentSpec":
        return replace(self, **changes)


@dataclass(frozen=True)
class Change:
    """One edit the agent made, and why. Every change must carry a source."""
    field: str
    before: str
    after: str
    kind: str     # rule | lesson | correction | fallback
    source: str   # e.g. "Brand rule: disclaimer required when a rate is stated"


@dataclass
class Finding:
    rule: str
    ok: bool
    required: bool
    evidence: str
    suggested_fix: str = ""


@dataclass
class Correction:
    """What a reviewer does on the review link: change a span of text, with a reason."""
    reviewer: str
    function: str        # legal, brand, compliance
    field: str
    find: str            # regex for what they struck
    replace: str         # what they wrote instead
    reason: str          # claim, imagery, tone, legal, layout
    campaign: str = ""
    note: str = ""
    extra: dict = field(default_factory=dict)
