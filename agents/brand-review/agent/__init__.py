"""Brand Review agent core: drafting, rendering every format, rules, reviewer-taught lessons,
scoped retrieval, pre-review, and the campaign workflow.

Standard library only. Deterministic: the drafting step is pluggable, and the checks and
lessons run the same way on whatever produced the draft.
"""
from .drafter import Brief, MissingFact, TemplateDrafter
from .lessons import Lesson, LessonStore
from .pipeline import Production, produce
from .render import FORMATS, check_rendered, render_all
from .prereview import PreReviewResult, prereview
from .retrieval import in_scope, retrieve
from .routing import route
from .rules import BrandRules, check, contrast_ratio
from .spec import Change, ContentSpec, Correction, Figure, Finding
from .workflow import Campaign, IllegalMove

__all__ = ["FORMATS", "Brief", "MissingFact", "Production", "TemplateDrafter", "check_rendered",
           "produce", "render_all", "BrandRules", "Campaign", "Change", "ContentSpec", "Correction", "Figure", "Finding",
           "IllegalMove", "Lesson", "LessonStore", "PreReviewResult", "check", "contrast_ratio",
           "in_scope", "prereview", "retrieve", "route"]
