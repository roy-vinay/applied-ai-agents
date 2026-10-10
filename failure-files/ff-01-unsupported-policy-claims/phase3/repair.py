"""Citation repair: clean up how real models cite, then run the unchanged Phase 1 guard.

Phase 2 found that most good answers the guards blocked had sloppy citations, not wrong facts. Repair:
  1. Recognize a plain-language "no policy covers that" as an abstention, so it isn't blocked for
     having no citation.
  2. Drop cited policies that don't match the question's topic.
  3. If nothing is left, attach the policies whose topic does match the question. An answer with no
     relevant policy at all is still blocked.
  4. Check every number against the policies the answer cites plus the relevant ones, and let the answer
     repeat numbers the customer gave ("your bag is 24 kg", "not 50%"). Phase 2 blocked many correct
     answers just for echoing the question.
The guard's idea is unchanged: numbers must come from a real policy. Its known blind spot is too: it
can't tell "not 50%" from "yes, 50%". That is the judge's job.
"""
from __future__ import annotations

import re

from common3 import POLICIES, strip_cites
from guards import facts, l5_facts_normalized, words

ABSTAIN = re.compile(r"(don't|do not|doesn't|does not) have (a |any )?(specific )?polic|no policy|"
                     r"not covered|isn't covered|connect you with an agent", re.I)


def repaired_cites(question: str, cites: list[str]) -> list[str]:
    qw = words(question)
    kept = [c for c in cites if c in POLICIES and qw & POLICIES[c]["topic"]]
    return sorted(kept) if kept else sorted(c for c, p in POLICIES.items() if qw & p["topic"])


def passes_rules_repaired(question: str, text: str, cites: list[str]) -> bool:
    body = strip_cites(text)
    said, asked = facts(body, normalize=True), facts(question, normalize=True)
    if ABSTAIN.search(body) and said <= asked:
        return True
    relevant = repaired_cites(question, cites)
    if not relevant:
        return False
    sources = set(relevant) | {c for c in cites if c in POLICIES}
    allowed = facts(" ".join(POLICIES[c]["text"] for c in sources), normalize=True) | asked
    return said <= allowed


def passes_rules_frozen(question: str, text: str, cites: list[str]) -> bool:
    """The Phase 2 guard, exactly as frozen."""
    return l5_facts_normalized(question, {"text": strip_cites(text), "cites": cites})
