"""Written brand rules: deterministic checks, run on every draft before anyone reviews it.

Required rules block sending. Some failures have a safe automatic fix (add the disclaimer,
shorten the banner headline); others never do (a figure that disagrees with its source is
blocked until a person confirms the right number).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from .spec import Change, ContentSpec, Finding

RATE = re.compile(r"\d+(\.\d+)?\s*%|\bAP[RY]\b")


@dataclass
class BrandRules:
    version: str = "v14"
    min_contrast: float = 4.5            # WCAG AA for normal text
    banner_max_chars: int = 30
    rate_disclaimer: str = "APR = Annual Percentage Rate. Rates and terms subject to approval."
    yield_disclaimer: str = "APY = Annual Percentage Yield. Rate fixed for the term."
    approved_images: frozenset = field(default_factory=lambda: frozenset(
        {"branch-ballard-2026", "branch-fremont-2025", "branch-tacoma-2025", "family-car-01"}))


# ---------- contrast (WCAG 2.x relative luminance) ----------

def _lum(hex_color: str) -> float:
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    lin = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in (r, g, b)]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast_ratio(fg: str, bg: str) -> float:
    a, b = sorted((_lum(fg), _lum(bg)), reverse=True)
    return (a + 0.05) / (b + 0.05)


def _darken(hex_color: str, f: float = 0.85) -> str:
    h = hex_color.lstrip("#")
    return "#" + "".join(f"{int(int(h[i:i + 2], 16) * f):02X}" for i in (0, 2, 4))


# ---------- checks ----------

def states_rate(spec: ContentSpec) -> bool:
    return bool(RATE.search(f"{spec.headline} {spec.sub}")) or bool(spec.figures)


def check(spec: ContentSpec, rules: BrandRules, source: dict | None = None) -> list[Finding]:
    source = source or {}
    out: list[Finding] = []

    ratio = contrast_ratio(spec.text_color, spec.bg_color)
    out.append(Finding("contrast", ratio >= rules.min_contrast, True,
                       f"{ratio:.1f}:1 (minimum {rules.min_contrast}:1)", "darken the background"))

    needs = states_rate(spec)
    out.append(Finding("disclaimer", (not needs) or bool(spec.disclaimer.strip()), True,
                       "rate stated, disclaimer present" if needs and spec.disclaimer else
                       "rate stated, no disclaimer" if needs else "no rate stated", "add the disclaimer"))

    banner = spec.short_headline or spec.headline
    out.append(Finding("banner_fit", len(banner) <= rules.banner_max_chars, False,
                       f"banner headline {len(banner)} chars (max {rules.banner_max_chars})", "shorten it"))

    if spec.image is None:
        out.append(Finding("approved_image", True, False, "no image slot"))
    else:
        ok = spec.image in rules.approved_images
        out.append(Finding("approved_image", ok, True,
                           f"{spec.image} is {'in' if ok else 'NOT in'} the approved library",
                           "pick an approved image"))

    for fig in spec.figures:
        if fig.source_field not in source:
            out.append(Finding(f"figure:{fig.label}", False, True,
                               f"{fig.label}: no field '{fig.source_field}' in the offer sheet",
                               "bind the figure to a source field"))
        elif abs(source[fig.source_field] - fig.value) > 1e-9:
            out.append(Finding(f"figure:{fig.label}", False, True,
                               f"{fig.label}: asset says {fig.value}, offer sheet says {source[fig.source_field]}",
                               f"use {source[fig.source_field]}"))
        else:
            out.append(Finding(f"figure:{fig.label}", True, True, f"{fig.label}: matches the offer sheet"))
    return out


def autofix(spec: ContentSpec, rules: BrandRules) -> tuple[ContentSpec, list[Change]]:
    """Apply only the fixes that can't change meaning. Figures and images are never auto-fixed."""
    changes: list[Change] = []

    if states_rate(spec) and not spec.disclaimer.strip():
        text = rules.yield_disclaimer if re.search(r"\bAPY\b", spec.text()) else rules.rate_disclaimer
        changes.append(Change("disclaimer", "", text, "rule",
                              f"Brand rule {rules.version}: disclaimer required when a rate is stated"))
        spec = spec.with_(disclaimer=text)

    banner = spec.short_headline or spec.headline
    if len(banner) > rules.banner_max_chars:
        words, short = banner.split(), ""
        for w in words:
            if len((short + " " + w).strip()) > rules.banner_max_chars:
                break
            short = (short + " " + w).strip()
        short = re.sub(r"\s+(and|or|the|your|to|for|with|a|of|at|on)$", "", short, flags=re.I)
        changes.append(Change("short_headline", banner, short, "rule",
                              f"Brand rule {rules.version}: banner headline max {rules.banner_max_chars} characters"))
        spec = spec.with_(short_headline=short)

    if contrast_ratio(spec.text_color, spec.bg_color) < rules.min_contrast:
        bg = spec.bg_color
        for _ in range(12):
            bg = _darken(bg)
            if contrast_ratio(spec.text_color, bg) >= rules.min_contrast:
                break
        changes.append(Change("bg_color", spec.bg_color, bg, "rule",
                              f"Brand rule {rules.version}: text contrast at least {rules.min_contrast}:1"))
        spec = spec.with_(bg_color=bg)

    return spec, changes
