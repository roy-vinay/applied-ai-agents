"""Pick the lessons that apply to a draft, and nothing else.

Filters, in order: not retired, owned by a function this draft is routed to, in scope
(product line, product, region), and actually matching the draft's text. Ranked by most
recently taught, then most used. Two lessons that would edit the same text differently
are a conflict: neither is applied, and the marketer decides.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from .lessons import Lesson, LessonStore
from .spec import ContentSpec

SCOPE_KEYS = ("product_line", "product", "region")


def in_scope(lesson: Lesson, spec: ContentSpec) -> bool:
    for key in SCOPE_KEYS:
        want = lesson.scope.get(key, "all")
        if want != "all" and want != getattr(spec, key):
            return False
    return True


@dataclass
class Retrieved:
    apply: list[Lesson]
    conflicts: list[tuple[Lesson, Lesson]]
    skipped_out_of_scope: list[Lesson]


def retrieve(store: LessonStore, spec: ContentSpec, routed_to: set[str], scoped: bool = True) -> Retrieved:
    candidates, out_of_scope = [], []
    for l in store:
        if l.status == "retired" or l.owner not in routed_to:
            continue
        if not l.matches(getattr(spec, l.field)):
            continue
        if scoped and not in_scope(l, spec):
            out_of_scope.append(l)
            continue
        candidates.append(l)

    candidates.sort(key=lambda l: (l.taught_on, l.uses), reverse=True)

    conflicts, apply, blocked = [], [], set()
    for i, a in enumerate(candidates):
        for b in candidates[i + 1:]:
            if a.field == b.field and a.replace != b.replace and _overlap(a, b, getattr(spec, a.field)):
                conflicts.append((a, b))
                blocked.update({a.id, b.id})
    apply = [l for l in candidates if l.id not in blocked]
    return Retrieved(apply, conflicts, out_of_scope)


def _overlap(a: Lesson, b: Lesson, text: str) -> bool:
    spans = lambda l: [m.span() for m in re.finditer(l.find, text, flags=re.I)]
    return any(s1 < e2 and s2 < e1 for s1, e1 in spans(a) for s2, e2 in spans(b))
