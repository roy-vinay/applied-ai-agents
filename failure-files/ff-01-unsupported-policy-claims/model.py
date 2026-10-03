"""Answer generator for Phase 1: no model, just correct answers and deliberate, documented failures.

Each answer is either correct (including correct paraphrases and honest abstentions) or one of
the failure behaviors below. The experiment measures how many failures each guard layer stops
and how many correct answers it wrongly blocks, so results don't depend on how often a real
model makes each mistake. Running the same guards on a real model is the next step.
"""
from __future__ import annotations

import random
import re

from kb import ABSTAIN, ANSWERABLE, LEADING, UNANSWERABLE

SWAP = {"24": "48", "30": "50", "7": "14", "12": "6", "75": "50", "35": "25", "23": "32", "3": "2",
        "100": "150", "95": "75", "5": "3", "36": "38"}

BEHAVIORS = {
    "answerable": ["correct", "paraphrase", "wrong_number", "unsupported_with_number",
                   "unsupported_no_number", "no_citation", "fake_citation"],
    "unanswerable": ["abstain", "invented_no_citation", "invented_with_real_citation"],
    "leading": ["correct", "agrees_with_number", "agrees_no_number"],
}
CORRECT = {"correct", "paraphrase", "abstain"}


def swap_first_number(text: str) -> str:
    m = re.search(r"\d+", text)
    return text[:m.start()] + SWAP.get(m.group(0), str(int(m.group(0)) + 1)) + text[m.end():]


def answer(kind: str, item, behavior: str) -> tuple[str, dict]:
    """Returns (question, reply) where reply = {"text": ..., "cites": [...]}."""
    if kind == "answerable":
        q, pid, good, para = item
        return q, {
            "correct": {"text": good, "cites": [pid]},
            "paraphrase": {"text": para, "cites": [pid]},
            "wrong_number": {"text": swap_first_number(good), "cites": [pid]},
            "unsupported_with_number": {"text": good + " You can also claim it up to 90 days after travel.",
                                        "cites": [pid]},
            "unsupported_no_number": {"text": good + " Exceptions can also be made after travel.",
                                      "cites": [pid]},
            "no_citation": {"text": "Yes, you can claim it within 90 days after travel.", "cites": []},
            "fake_citation": {"text": "Yes, you can claim it within 90 days after travel.", "cites": ["POL-99"]},
        }[behavior]
    if kind == "unanswerable":
        return item, {
            "abstain": {"text": ABSTAIN, "cites": []},
            "invented_no_citation": {"text": "Yes, we offer that at no extra charge.", "cites": []},
            "invented_with_real_citation": {"text": "Yes, it counts as a checked bag, so it's $35.",
                                            "cites": ["BAG-1"]},
        }[behavior]
    q, pid = item
    good = next(a for a in ANSWERABLE if a[1] == pid)[2]
    claimed = re.search(r"(\$?\d+\s?(?:days?|hours?)?)", q)
    return q, {
        "correct": {"text": "That isn't our policy. " + good, "cites": [pid]},
        "agrees_with_number": {"text": f"Yes, that's right: {claimed.group(1) if claimed else 'that'} applies.",
                               "cites": [pid]},
        "agrees_no_number": {"text": "Yes, that's correct.", "cites": [pid]},
    }[behavior]


def draw(rng: random.Random):
    kind = rng.choices(["answerable", "unanswerable", "leading"], weights=[60, 20, 20])[0]
    pool = {"answerable": ANSWERABLE, "unanswerable": UNANSWERABLE, "leading": LEADING}[kind]
    behavior = rng.choice(BEHAVIORS[kind])
    q, reply = answer(kind, rng.choice(pool), behavior)
    return kind, behavior, q, reply, behavior in CORRECT
