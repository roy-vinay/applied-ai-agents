"""Seeded test world: reviewers with unwritten rules, and a quarter of campaigns to replay.

Reviewers are simulated. Each has rules they enforce but never wrote down, each with a true
scope. Some phrases are traps: "guaranteed" is a forbidden promise on a loan, but accurate
on a fixed-rate certificate. A lesson that ignores scope will break the certificate.

Novel objections are one-off judgment calls (a phrase only that campaign uses), so no lesson
can predict them. They keep the benchmark honest about what lessons can't do.
"""
from __future__ import annotations

import random
import re
from dataclasses import dataclass
from datetime import date, timedelta

from agent import ContentSpec, Figure
from agent.retrieval import SCOPE_KEYS


@dataclass(frozen=True)
class Habit:
    """An unwritten rule a reviewer enforces, with the scope they actually mean."""
    id: str
    reviewer: str
    function: str
    field: str
    find: str
    replace: str
    reason: str
    note: str
    scope: dict

    def applies_to(self, spec: ContentSpec) -> bool:
        return all(self.scope.get(k, "all") in ("all", getattr(spec, k)) for k in SCOPE_KEYS)

    def objects_to(self, spec: ContentSpec) -> bool:
        return self.applies_to(spec) and re.search(self.find, getattr(spec, self.field), re.I) is not None


HABITS = [
    Habit("L1", "Dana Ruiz", "legal", "sub", r"\bguaranteed\s+", "", "claim",
          "No 'guaranteed' in lending claims", {"product_line": "lending"}),
    Habit("L2", "Dana Ruiz", "legal", "sub", r"\band lower your monthly (payments?|bill)\b",
          r"and you could lower your monthly \1", "claim",
          "'could lower', not 'lower', in payment claims", {"product_line": "lending"}),
    Habit("L3", "Dana Ruiz", "legal", "headline", r"\bthe (best|lowest) rates?\b", "a competitive rate", "claim",
          "No superlatives on rates", {}),
    Habit("C1", "Priya Shah", "compliance", "sub", r"on balance transfers\.$",
          "on balance transfers. 3% transfer fee applies.", "legal",
          "State the transfer fee next to the offer", {"product_line": "cards"}),
    Habit("B1", "Jordan Kim", "brand", "headline", r"\s*(Hurry|Act now|Don't wait)!$", "", "tone",
          "No urgency punctuation in headlines", {}),
    Habit("B2", "Jordan Kim", "brand", "sub", r"\bstop by\b", "visit us", "tone",
          "Warm, not casual: 'visit us'", {"product_line": "branch", "region": "pnw"}),
]

PRODUCTS = [  # (product_line, product, headline options, sub options)
    ("lending", "auto_refi", ["Refinance your auto loan and save", "Get the best rate on your car loan"],
     ["Guaranteed savings at {r}% APR and lower your monthly payment.", "Refinance at {r}% APR and lower your monthly payments."]),
    ("lending", "personal_loan", ["One payment, less stress", "The lowest rate for a fresh start"],
     ["Consolidate at {r}% APR and lower your monthly bill.", "Guaranteed approval decision in a day at {r}% APR."]),
    ("lending", "mortgage", ["Today's mortgage rates, made simple", "The best rates on a home loan"],
     ["Fixed 30-year from {r}% APR.", "Refinance at {r}% APR and lower your monthly payment."]),
    ("deposits", "certificate", ["A guaranteed {r}% APY", "Lock in a great rate"],
     ["Guaranteed rate for 12 months at {r}% APY.", "Earn {r}% APY, federally insured."]),
    ("cards", "balance_transfer", ["0% intro APR for 15 months", "Pay down debt faster"],
     ["0% intro APR on balance transfers.", "Save on interest on balance transfers."]),
    ("branch", "branch_hours", ["New weekend hours", "We're back, Ballard"],
     ["Open Saturdays 9 to 1. Stop by and say hello.", "Reopening soon. Stop by to see the new space."]),
]
REGIONS = ["pnw", "pnw", "national"]
SOURCE = {"auto_refi_apr": 4.2, "personal_loan_apr": 9.9, "mortgage_apr": 6.1, "certificate_apy": 4.1,
          "balance_transfer_apr": 0.0}   # the offer sheet: the only source of truth for printed numbers


def source_key(product: str) -> str:
    return "certificate_apy" if product == "certificate" else f"{product}_apr"
NOVEL = ["ride", "wheels", "nest egg", "cha-ching", "game changer", "no-brainer", "sweet deal", "level up"]


def make_quarter(n: int = 120, seed: int = 11, start: date = date(2026, 7, 1)):
    """A seeded quarter of campaigns. Each: (date, spec, novel objection or None)."""
    rng = random.Random(seed)
    out = []
    for i in range(n):
        line, product, heads, subs = rng.choice(PRODUCTS)
        rate = SOURCE.get(source_key(product), 0.0)
        head = rng.choice(heads).format(r=rate)
        sub = rng.choice(subs).format(r=rate)
        if rng.random() < 0.25:
            head += " " + rng.choice(["Hurry!", "Act now!", "Don't wait!"])
        novel = None
        if rng.random() < 0.35:
            novel = rng.choice(NOVEL) + f" #{i}"   # unique to this campaign: can't recur
            sub = f"{sub} A real {novel}."
        figs = ()
        if "%" in head + sub and line != "branch":
            key = source_key(product)
            wrong = rng.random() < 0.08          # a typo'd number the source check must catch
            figs = (Figure(product, round(rate + (0.1 if wrong else 0), 2), key),)
        spec = ContentSpec(campaign=f"C{i:03d} {product}", product_line=line, product=product,
                           region=rng.choice(REGIONS), headline=head, sub=sub, figures=figs,
                           image="branch-ballard-2026" if line == "branch" else None)
        out.append((start + timedelta(days=int(i * 90 / n)), spec, novel))
    return out
