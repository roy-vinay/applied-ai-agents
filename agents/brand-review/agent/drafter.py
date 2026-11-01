"""Drafting: brief in, content spec out.

The drafter is pluggable. This one is deterministic (approved copy patterns per product), so
anyone can run it without a key. An LLM drafter would implement the same `draft()` signature;
everything downstream (rules, lessons, rendering, checks) runs the same on its output.

One rule no drafter may break: every number in the copy comes from the offer sheet. If the
fact isn't there, the drafter stops and asks instead of guessing.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

from .spec import ContentSpec, Figure

DIRECTIONS = ("benefit", "rate", "seasonal")


class MissingFact(Exception):
    """The brief needs a number the offer sheet doesn't have. A person must supply it."""


@dataclass(frozen=True)
class Brief:
    campaign: str
    product: str                       # key into PRODUCTS
    region: str = "pnw"
    direction: str = "benefit"         # benefit | rate | seasonal
    compare: tuple[str, ...] = ()      # offer-sheet keys to chart, for an infographic
    notes: str = ""


@dataclass(frozen=True)
class ProductCopy:
    line: str
    key: str                           # the offer-sheet field for the headline rate
    unit: str                          # APR | APY
    heads: dict = field(default_factory=dict)
    sub: str = ""
    cta: str = "Learn more"
    image: str | None = None
    bg: str = "#0E4D64"


PRODUCTS = {
    "auto_refi": ProductCopy(
        "lending", "auto_refi_apr", "APR",
        {"benefit": "Refinance your auto loan and save", "rate": "Move your auto loan to {r}% APR",
         "seasonal": "A lower rate for the road ahead"},
        "Refinance at {r}% APR and you could lower your monthly payment.", "See your new rate",
        "family-car-01", "#0E4D64"),
    "personal_loan": ProductCopy(
        "lending", "personal_loan_apr", "APR",
        {"benefit": "One payment, less stress", "rate": "Consolidate at {r}% APR",
         "seasonal": "Start the new year with one payment"},
        "Consolidate at {r}% APR and you could lower your monthly payment.", "Check your rate",
        None, "#24506B"),
    "certificate": ProductCopy(
        "deposits", "certificate_12m_apy", "APY",
        {"benefit": "Let your savings work harder", "rate": "A guaranteed {r}% APY",
         "seasonal": "Lock in a rate for the year ahead"},
        "Earn {r}% APY on a 12-month certificate. Rate fixed for the term.", "Open a certificate",
        None, "#7C5A2E"),
    "balance_transfer": ProductCopy(
        "cards", "balance_transfer_intro_apr", "APR",
        {"benefit": "Pay down debt faster", "rate": "{r}% intro APR on balance transfers",
         "seasonal": "A fresh start for your balance"},
        "{r}% intro APR for 15 months on balance transfers.", "Apply now", None, "#5B2A4E"),
}

TERM_LABELS = {"certificate_6m_apy": "6-month", "certificate_12m_apy": "12-month", "certificate_24m_apy": "24-month"}


class Drafter(Protocol):
    def draft(self, brief: Brief, offer_sheet: dict) -> ContentSpec: ...


class TemplateDrafter:
    """Approved copy patterns per product, filled only with offer-sheet facts."""

    def draft(self, brief: Brief, offer_sheet: dict) -> ContentSpec:
        if brief.product not in PRODUCTS:
            raise MissingFact(f"no approved copy patterns for '{brief.product}'; a person must write the first draft")
        p = PRODUCTS[brief.product]
        if p.key not in offer_sheet:
            raise MissingFact(f"offer sheet has no '{p.key}'; which rate should this campaign use?")
        r = _fmt(offer_sheet[p.key])

        if brief.compare:
            missing = [k for k in brief.compare if k not in offer_sheet]
            if missing:
                raise MissingFact(f"offer sheet has no {missing}; can't chart numbers we don't have")
            figs = tuple(Figure(TERM_LABELS.get(k, k), offer_sheet[k], k) for k in brief.compare)
            return ContentSpec(brief.campaign, p.line, brief.product, brief.region,
                               headline="Certificate rates at a glance",
                               sub="Pick the term that fits your plans.", cta="Compare certificates",
                               bg_color=p.bg, figures=figs)

        return ContentSpec(brief.campaign, p.line, brief.product, brief.region,
                           headline=p.heads[brief.direction].format(r=r), sub=p.sub.format(r=r),
                           cta=p.cta, image=p.image, bg_color=p.bg,
                           figures=(Figure(f"{brief.product} {p.unit}", offer_sheet[p.key], p.key),))

    def directions(self, brief: Brief, offer_sheet: dict) -> list[ContentSpec]:
        """Three creative directions for the marketer to choose between at the plan step."""
        return [self.draft(Brief(brief.campaign, brief.product, brief.region, d), offer_sheet) for d in DIRECTIONS]


def _fmt(x: float) -> str:
    return f"{x:.1f}".rstrip("0").rstrip(".") if x != int(x) else f"{int(x)}"
