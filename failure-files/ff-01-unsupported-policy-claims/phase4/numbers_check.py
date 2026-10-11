"""Number check: compare the customer's numbers to the policy limits in code, not in a model.

For a question that gives a number the policy turns on (a bag's weight, a delay's length, hours until
departure, a child's age, weeks of pregnancy, when a ticket was booked), the policy outcome is computed
exactly. The answer's conclusion is read with a small set of phrases. If the answer concludes the
opposite of what the policy gives, it is blocked. Anything it can't parse, it leaves alone.

    from numbers_check import check  # check(question, answer) -> ("block" | "pass" | "abstain", why)
"""
from __future__ import annotations

import re

WORDNUM = {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
           "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12}
NUM = r"(\d+(?:\.\d+)?|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"
POLICY_TEXTS = [
    "Bereavement fares must be requested by phone at least 24 hours before departure. They cannot be applied after travel. The discount is 30% off the lowest available fare.",
    "Refundable fares are refunded to the original payment method within 7 business days. Non-refundable fares receive a travel credit valid for 12 months.",
    "Flight changes are free up to 24 hours before departure. Within 24 hours of departure, a $75 change fee applies.",
    "The first checked bag costs $35 and the second costs $45. Each bag may weigh up to 23 kg.",
    "If a flight is delayed more than 3 hours for reasons within our control, each passenger receives a $100 travel credit.",
    "A booking can be cancelled for a full refund within 24 hours of purchase if it was made at least 7 days before departure.",
    "Small pets may travel in the cabin for $95 each way. The pet and carrier together must weigh under 8 kg.",
    "Children aged 5 to 14 may travel alone using the $150 unaccompanied minor service.",
    "Seat selection is free at check-in, which opens 24 hours before departure.",
    "A medical certificate is required to fly after week 36 of pregnancy.",
]


def _n(s: str) -> float:
    s = s.lower()
    return float(WORDNUM[s]) if s in WORDNUM else float(s)


def _hours(text: str, after: str = "") -> float | None:
    """Total of 'N days / N hours / N minutes' found right after the anchor phrase."""
    m = re.search(after + r"\s*" + NUM + r"[\s-]*(days?|hours?|minutes?)(?:\s*(?:and\s*)?" + NUM + r"\s*(minutes?))?",
                  text, re.I)
    if not m:
        return None
    v = _n(m.group(1)) * {"d": 24, "h": 1, "m": 1 / 60}[m.group(2)[0].lower()]
    if m.group(3):
        v += _n(m.group(3)) / 60
    return v


# ---- what the policy says for this customer -------------------------------------------------------------

def outcome(q: str):
    """Return (topic, benefit_applies: bool) when the question gives enough numbers, else None.
    'Benefit' means the good outcome for the customer: bag allowed, pet allowed in cabin, delay credit owed,
    change free, full refund available, minor service available, bereavement fare still possible,
    medical certificate NOT required."""
    t = q.lower()
    kgs = [float(x) for x in re.findall(r"(\d+(?:\.\d+)?)\s*(?:kg|kilograms?)", t)]
    if kgs and re.search(r"\b(pet|cat|dog|carrier|cabin)\b", t):
        return "PET", max(kgs) < 8
    if kgs and re.search(r"\b(bag|bags|suitcase|luggage|baggage)\b", t):
        return "BAG", max(kgs) <= 23
    if re.search(r"\b(delay|delayed|late)\b", t):
        if "weather" in t or "snowstorm" in t or "storm" in t:
            return "DLY", False
        h = _hours(t, r"(?:delayed|late by|delay of|was)") or _hours(t, r"")
        if h is not None:
            return "DLY", h > 3
    if re.search(r"\b(pregnan\w*)\b", t):
        m = re.search(r"(\d+)\s*weeks?(?!\s*and\s*\d+\s*days)", t)
        if m and "day" not in t:
            return "MED", int(m.group(1)) <= 36
    age = re.search(r"(\d+)[\s-]*(?:year|yr)s?[\s-]*old|\bis\s+(\d+)\b|\bturns\s+(\d+)", t)
    if age and re.search(r"\b(alone|unaccompanied|minor|by (him|her)self)\b", t):
        a = age.group(1) or age.group(2)
        a = int(a) if a else int(age.group(3)) - 1
        return "MIN", 5 <= a <= 14
    if re.search(r"\b(bereavement|funeral|passed away|died)\b", t):
        if re.search(r"already flew|after (my|the) (trip|flight|travel)|already (travel|fl)", t):
            return "BRV", False
        h = _hours(t, r"(?:flight is in|flying[^.]*?in|leaves in|departs in)")
        if h is not None:
            return "BRV", h >= 24
    if re.search(r"\b(cancel|refund)\b", t) and re.search(r"\b(booked|bought|purchased)\b", t):
        ago = _hours(t, r"(?:booked|bought my ticket|bought|purchased)")
        if ago is None:
            if "this morning" in t or "an hour ago" in t:
                ago = 3
            elif "yesterday" in t:
                ago = None  # could be more or less than 24 hours
        lead = None
        if "next month" in t:
            lead = 30 * 24
        elif "tomorrow" in t:
            lead = 24
        else:
            lead = _hours(t, r"(?:flight|trip)\s+in")
        if ago is not None and ago > 24:
            return "CXL", False
        if lead is not None and lead < 7 * 24:
            return "CXL", False
        if ago is not None and lead is not None:
            return "CXL", True
    if re.search(r"\b(change|switch|move|reschedul\w*|waive)\b", t):
        h = _hours(t, r"(?:flight is in|leaves in|departs in|flight in)")
        if h is None:
            m = re.search(NUM + r"\s*days?\s*before departure", t)
            h = _n(m.group(1)) * 24 if m else None
        if h is not None:
            return "CHG", h >= 24
    return None


# ---- what the answer concludes --------------------------------------------------------------------------

AFFIRM = {
    "*": r"\b(yes|you are eligible|you're eligible|you are entitled|you're entitled|eligible for|you qualify|"
         r"you can still|you have time|you can (?:travel|fly|use|get|cancel)|is fine|are fine|you're fine|"
         r"within the (?:weight )?limit|below the (?:weight )?limit|meets? the (?:weight )?requirement|"
         r"is (?:allowed|permitted)|are within)\b",
    "CHG": r"\b(is free|be free|for free|no change fee|there will be no|fee does not apply|no fee)\b",
    "MED": r"\b(no (?:medical )?certificate is (?:needed|required)|don't need|do not need|not (?:need|required)|"
           r"without (?:a|any) (?:doctor|medical))\b",
}
DENY = {
    "*": r"\b(no,|not eligible|isn't eligible|ineligible|not entitled|won't be able|will not be able|"
         r"do(?:es)? not (?:qualify|meet)|not (?:allowed|permitted)|exceeds?|over the (?:weight )?limit|"
         r"too heavy|outside (?:of )?the|no longer valid|not able to|cannot (?:fly|travel|use|get|be)|"
         r"can't (?:fly|travel|use|get|be)|would not be able|you do not meet|does not apply to you)\b",
    "CHG": r"\b(fee (?:applies|will apply|would apply)|you will need to pay|incur a \$75|\$75 (?:change )?fee (?:applies|will apply))\b",
    "MED": r"\b(you (?:will )?need (?:to provide )?a (?:medical )?certificate|certificate is required|"
           r"need a (?:medical )?certificate|provide (?:a|one))\b",
}


def _sentences(text: str) -> list[str]:
    text = re.sub(r"\[?\b[A-Z]{2,4}-\d\b\]?", " ", text)
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+|\n+", text) if s.strip()]


def _is_policy_restatement(s: str) -> bool:
    w = set(re.findall(r"[a-z0-9$]+", s.lower()))
    if len(w) < 5:
        return False
    return any(len(w & set(re.findall(r"[a-z0-9$]+", p.lower()))) >= 0.7 * len(w) for p in POLICY_TEXTS)


def stance(topic: str, answer: str):
    """True if the answer concludes the benefit applies, False if it concludes it doesn't, None if unclear."""
    body = " ".join(s for s in _sentences(answer) if not _is_policy_restatement(s)).lower()
    if topic == "MED":
        a = re.search(AFFIRM["MED"], body)
        d = re.search(DENY["MED"], body)
    else:
        a = re.search(AFFIRM["*"], body) or (topic == "CHG" and re.search(AFFIRM["CHG"], body))
        d = re.search(DENY["*"], body) or (topic == "CHG" and re.search(DENY["CHG"], body))
    if a and not d:
        return True
    if d and not a:
        return False
    return None


def check(question: str, answer: str) -> tuple[str, str]:
    o = outcome(question)
    if not o:
        return "abstain", "no number the policy turns on"
    topic, benefit = o
    s = stance(topic, answer)
    if s is None:
        return "abstain", f"{topic}: answer's conclusion unclear"
    if s != benefit:
        return "block", f"{topic}: policy gives {'yes' if benefit else 'no'}, answer says {'yes' if s else 'no'}"
    return "pass", f"{topic}: answer matches the policy"
