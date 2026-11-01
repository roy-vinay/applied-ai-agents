"""What happens when a reviewer corrects a draft: fix this campaign, or teach the agent.

On the review link, a reviewer's correction comes with a choice:

  fix this campaign only   the draft is corrected; the agent learns nothing; the next
                           campaign can carry the same mistake back to this reviewer
  teach my agent           the draft is corrected AND the correction becomes a lesson,
                           owned by the reviewer's function, inside the scope they pick
                           (say, all lending in every region); later drafts in that scope
                           are fixed before the reviewer ever sees them

Teaching never changes policy. A lesson is context until its owner promotes it to a rule.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from .lessons import Lesson, LessonStore, apply_edit
from .spec import Change, ContentSpec, Correction


@dataclass
class Corrected:
    spec: ContentSpec
    change: Change
    lesson: Lesson | None      # None when the reviewer fixed this campaign only


def apply_correction(spec: ContentSpec, c: Correction, *, teach: bool, store: LessonStore | None = None,
                     scope: dict | None = None, today: date | None = None) -> Corrected:
    before = getattr(spec, c.field)
    after = apply_edit(before, c.find, c.replace)
    change = Change(c.field, before, after, "correction",
                    f"{c.reviewer} ({c.function}), reason: {c.reason}"
                    + (f"; taught to the {c.function} agent" if teach else "; this campaign only"))
    lesson = None
    if teach:
        if store is None or scope is None or today is None:
            raise ValueError("teaching needs a lesson store, a scope chosen by the reviewer, and a date")
        lesson = store.learn(c, scope, today)
    return Corrected(spec.with_(**{c.field: after}), change, lesson)
