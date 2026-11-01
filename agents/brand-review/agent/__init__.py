"""Brand Review agent core: rules, reviewer-taught lessons, scoped retrieval, pre-review, workflow.

Standard library only. Deterministic: the drafting step is pluggable, and the checks and
lessons run the same way on whatever produced the draft.
"""
from .lessons import Lesson, LessonStore
from .prereview import PreReviewResult, prereview
from .retrieval import in_scope, retrieve
from .routing import route
from .rules import BrandRules, check, contrast_ratio
from .spec import Change, ContentSpec, Correction, Figure, Finding
from .workflow import Campaign, IllegalMove

__all__ = ["BrandRules", "Campaign", "Change", "ContentSpec", "Correction", "Figure", "Finding",
           "IllegalMove", "Lesson", "LessonStore", "PreReviewResult", "check", "contrast_ratio",
           "in_scope", "prereview", "retrieve", "route"]
