"""Pre-review: everything the agent does to a draft before a person sees it.

1. Route: which functions will review this draft.
2. Retrieve and apply those functions' lessons (in scope only; conflicts go to the marketer).
3. Apply safe rule fixes (disclaimer, banner length, contrast).
4. Re-check every rule. Any failing required rule blocks sending.

Every edit is returned as a Change with its source, so the asset can explain itself.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date

from .lessons import LessonStore, apply_edit
from .retrieval import retrieve
from .routing import route
from .rules import BrandRules, autofix, check
from .spec import Change, ContentSpec, Finding


@dataclass
class PreReviewResult:
    spec: ContentSpec
    routed_to: set[str]
    changes: list[Change]
    findings: list[Finding]
    conflicts: list = field(default_factory=list)
    lessons_applied: list = field(default_factory=list)

    @property
    def blocked(self) -> list[Finding]:
        return [f for f in self.findings if f.required and not f.ok]

    @property
    def can_send(self) -> bool:
        return not self.blocked and not self.conflicts


def prereview(spec: ContentSpec, rules: BrandRules, store: LessonStore | None, today: date,
              source: dict | None = None, new_image: bool = False, use_lessons: bool = True,
              scoped: bool = True) -> PreReviewResult:
    routed = route(spec, new_image=new_image)
    changes: list[Change] = []
    applied, conflicts = [], []

    if store is not None and use_lessons:
        r = retrieve(store, spec, routed, scoped=scoped)
        conflicts = r.conflicts
        for lesson in r.apply:
            before = getattr(spec, lesson.field)
            after = apply_edit(before, lesson.find, lesson.replace)
            if after == before:
                continue
            spec = spec.with_(**{lesson.field: after})
            changes.append(Change(lesson.field, before, after, "lesson",
                                  f"Lesson {lesson.id} from {lesson.taught_by} ({lesson.owner}), "
                                  f"{lesson.taught_on:%b %d}: {lesson.text}"))
            lesson.uses += 1
            lesson.last_used = today
            lesson.applied_in.append(spec.campaign)
            applied.append(lesson)

    spec, fixes = autofix(spec, rules)
    changes += fixes
    return PreReviewResult(spec, routed, changes, check(spec, rules, source), conflicts, applied)
