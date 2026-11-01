"""Lessons: a reviewer's correction, stored so the agent applies it before that reviewer looks again.

A lesson is data, not a retrained model. It has an owner (the reviewing function), a reason,
a scope, and a status. Only the owner, or an admin, can promote or retire it.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date

from .spec import Correction

STATUSES = ("context", "proposed", "rule", "retired")


def apply_edit(text: str, find: str, replace: str) -> str:
    """Replace every match, keeping a capital letter where the struck words had one."""
    def sub(m: re.Match) -> str:
        new = m.expand(replace)
        if m.group(0)[:1].isupper() and new[:1].islower():
            new = new[0].upper() + new[1:]
        return new
    out = re.sub(r"\s{2,}", " ", re.sub(find, sub, text, flags=re.I)).strip()
    if text[:1].isupper() and out[:1].islower():   # struck the first word: the next one starts the sentence
        out = out[0].upper() + out[1:]
    return out


STALE_AFTER_DAYS = 182


@dataclass
class Lesson:
    id: str
    text: str
    owner: str                      # legal | brand | compliance
    reason: str                     # claim | imagery | tone | legal | layout
    field: str                      # which spec field it edits
    find: str                       # regex
    replace: str
    scope: dict                     # {"product_line": ..., "product": ..., "region": ...}; "all" = any
    taught_by: str
    taught_on: date
    status: str = "context"
    uses: int = 0
    repeats_avoided: int = 0
    last_used: date | None = None
    applied_in: list = field(default_factory=list)

    def matches(self, text: str) -> bool:
        return re.search(self.find, text, flags=re.I) is not None


class LessonStore:
    def __init__(self) -> None:
        self._lessons: dict[str, Lesson] = {}
        self._next = 1

    def __iter__(self):
        return iter(self._lessons.values())

    def __len__(self) -> int:
        return len(self._lessons)

    def get(self, lesson_id: str) -> Lesson:
        return self._lessons[lesson_id]

    def learn(self, c: Correction, scope: dict, today: date) -> Lesson:
        """Turn a reviewer's correction into a scoped lesson. The reviewer chose the scope on the review link."""
        for l in self._lessons.values():  # same correction again: don't duplicate, it's the same lesson
            if l.owner == c.function and l.find == c.find and l.replace == c.replace and l.scope == scope:
                return l
        lid = f"lsn_{self._next:04d}"
        self._next += 1
        lesson = Lesson(id=lid, text=c.note or f"'{c.find}' -> '{c.replace}'", owner=c.function, reason=c.reason,
                        field=c.field, find=c.find, replace=c.replace, scope=dict(scope),
                        taught_by=c.reviewer, taught_on=today)
        self._lessons[lid] = lesson
        return lesson

    def _authorize(self, lesson: Lesson, actor_function: str) -> None:
        if actor_function not in (lesson.owner, "admin"):
            raise PermissionError(f"{actor_function} cannot change a lesson owned by {lesson.owner}")

    def propose(self, lesson_id: str, actor_function: str) -> None:
        l = self._lessons[lesson_id]
        if l.status == "context":   # anyone may propose; only the owner decides
            l.status = "proposed"

    def promote(self, lesson_id: str, actor_function: str) -> None:
        l = self._lessons[lesson_id]
        self._authorize(l, actor_function)
        l.status = "rule"

    def retire(self, lesson_id: str, actor_function: str) -> None:
        l = self._lessons[lesson_id]
        self._authorize(l, actor_function)
        l.status = "retired"

    def stale(self, today: date) -> list[Lesson]:
        return [l for l in self._lessons.values() if l.status != "retired"
                and (today - (l.last_used or l.taught_on)).days > STALE_AFTER_DAYS]
