"""Guard layers, added one at a time. Each returns True if the reply may be shown."""
from __future__ import annotations

import re

from kb import ABSTAIN, POLICIES

WORDNUM = {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
           "twelve": 12}
UNIT_HOURS = {"hour": 1, "day": 24, "business day": 24, "week": 168, "month": 730, "year": 8760}
MONEY = re.compile(r"\$\s?(\d+(?:\.\d+)?)")
PCT = re.compile(r"(\d+)\s?%")
QTY = re.compile(r"\b(\d+|a|an|one|two|three|four|five|six|seven|twelve)\s+"
                 r"(business days?|hours?|days?|weeks?|months?|years?|kg|kilograms?)\b", re.I)
BARE = re.compile(r"\b(\d+)\b")


def is_abstention(text: str) -> bool:
    return text == ABSTAIN or "won't guess" in text


def words(text: str) -> set[str]:
    return set(re.findall(r"[a-z\-]+", text.lower()))


def facts(text: str, normalize: bool) -> set:
    """Checkable facts in a sentence: amounts, percentages, durations, weights, other numbers."""
    out, spans = set(), []
    for m in MONEY.finditer(text):
        out.add(("usd", float(m.group(1))) if normalize else m.group(0).replace(" ", ""))
        spans.append(m.span())
    for m in PCT.finditer(text):
        out.add(("pct", int(m.group(1))) if normalize else m.group(0).replace(" ", ""))
        spans.append(m.span())
    for m in QTY.finditer(text):
        n, unit = m.group(1).lower(), m.group(2).lower().rstrip("s")
        if normalize:
            value = int(n) if n.isdigit() else WORDNUM[n]
            if unit in ("kg", "kilogram"):
                out.add(("kg", value))
            else:
                out.add(("hours", value * UNIT_HOURS[unit]))
        else:
            out.add(m.group(0).lower())
        spans.append(m.span())
    for m in BARE.finditer(text):
        if not any(a <= m.start() < b for a, b in spans):
            out.add(("n", int(m.group(1))) if normalize else m.group(0))
    return out


def passage(cites: list[str]) -> str:
    return " ".join(POLICIES[c]["text"] for c in cites if c in POLICIES)


# Each layer includes every layer above it.
def l1_citation_required(q, reply):
    return is_abstention(reply["text"]) or bool(reply["cites"])


def l2_citation_exists(q, reply):
    return l1_citation_required(q, reply) and all(c in POLICIES for c in reply["cites"])


def l3_citation_relevant(q, reply):
    return l2_citation_exists(q, reply) and all(words(q) & POLICIES[c]["topic"] for c in reply["cites"])


def l4_facts_verbatim(q, reply):
    if not l3_citation_relevant(q, reply):
        return False
    src = passage(reply["cites"]).lower()
    return all(str(f).lower() in src for f in facts(reply["text"], normalize=False))


def l5_facts_normalized(q, reply):
    if not l3_citation_relevant(q, reply):
        return False
    return facts(reply["text"], normalize=True) <= facts(passage(reply["cites"]), normalize=True)


LAYERS = [
    ("No guards", lambda q, r: True),
    ("+ Citation required", l1_citation_required),
    ("+ Citation must exist", l2_citation_exists),
    ("+ Citation must match the question", l3_citation_relevant),
    ("+ Every number must appear in the cited policy (exact text)", l4_facts_verbatim),
    ("+ Same check, with units normalized (24 hours = a day)", l5_facts_normalized),
]
