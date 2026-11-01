"""Rendering: one content spec, every format, each with its own layout.

Formats are re-laid out, not scaled: each has its own boxes, font range and text choice
(the 728x90 banner uses the short headline). Text is fitted by stepping the font size down
until it fits its box; if it can't fit at the minimum size, that's a render finding, not a
silent overflow. Images come only from the approved library; an empty slot renders as a
visible placeholder. Infographics draw bars from figures and print their source.

Output is SVG: text stays text, so every rendered word can be checked.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from html import escape

from .rules import BrandRules, states_rate
from .spec import ContentSpec, Finding

SERIF = "Georgia, 'Times New Roman', serif"
SANS = "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"
CTA_BG = "#B5431A"
# Average glyph width as a share of font size. Deliberately a little generous, so an
# estimate that fits here fits in real fonts too.
EM = {"serif": 0.56, "sans": 0.54}


@dataclass(frozen=True)
class Box:
    x: float
    y: float
    w: float
    h: float


@dataclass(frozen=True)
class Layout:
    name: str
    w: int
    h: int
    headline: Box
    head_size: tuple[int, int]         # (max, min) font size
    sub: Box | None = None
    sub_size: tuple[int, int] = (0, 0)
    cta: Box | None = None
    disclaimer: Box | None = None
    disc_size: tuple[int, int] = (0, 0)
    image: Box | None = None
    chart: Box | None = None
    use_short_headline: bool = False
    logo: tuple[float, float, int] = (0, 0, 0)


FORMATS = {
    "post_1x1": Layout("Instagram post 1:1", 1080, 1080, Box(80, 380, 920, 260), (96, 56),
                       Box(80, 670, 920, 120), (40, 28), Box(80, 830, 380, 84),
                       Box(80, 960, 920, 80), (24, 18), Box(80, 140, 920, 200), logo=(80, 100, 30)),
    "portrait_4x5": Layout("Portrait 4:5", 1080, 1350, Box(80, 560, 920, 300), (104, 60),
                           Box(80, 890, 920, 140), (42, 28), Box(80, 1070, 400, 88),
                           Box(80, 1220, 920, 90), (24, 18), Box(80, 150, 920, 360), logo=(80, 100, 30)),
    "story_9x16": Layout("Story 9:16", 1080, 1920, Box(90, 820, 900, 420), (120, 70),
                         Box(90, 1270, 900, 200), (46, 30), Box(90, 1520, 460, 100),
                         Box(90, 1740, 900, 110), (26, 18), Box(90, 200, 900, 560), logo=(90, 150, 34)),
    "display_300x250": Layout("Display 300x250", 300, 250, Box(16, 40, 268, 92), (28, 16),
                              Box(16, 136, 268, 40), (13, 10), Box(16, 184, 130, 30),
                              Box(16, 220, 268, 24), (8, 7), logo=(16, 26, 11)),
    "leaderboard_728x90": Layout("Leaderboard 728x90", 728, 90, Box(150, 18, 330, 54), (26, 16),
                                 cta=Box(600, 26, 112, 38), disclaimer=Box(488, 14, 104, 64), disc_size=(9, 7),
                                 use_short_headline=True, logo=(16, 52, 13)),
}
INFOGRAPHIC = Layout("Infographic 4:5", 1080, 1350, Box(80, 150, 920, 200), (88, 56),
                     Box(80, 360, 920, 80), (36, 26), disclaimer=Box(80, 1210, 920, 100), disc_size=(24, 18),
                     chart=Box(80, 480, 920, 680), logo=(80, 100, 30))


@dataclass
class Rendered:
    format: str
    layout: Layout
    svg: str
    lines: dict = field(default_factory=dict)       # field -> list of rendered lines
    findings: list = field(default_factory=list)

    @property
    def text(self) -> str:
        return " ".join(" ".join(v) for v in self.lines.values())


def text_width(s: str, size: float, face: str) -> float:
    return len(s) * size * EM[face]


def wrap(text: str, width: float, size: float, face: str) -> list[str]:
    lines, cur = [], ""
    for word in text.split():
        trial = f"{cur} {word}".strip()
        if cur and text_width(trial, size, face) > width:
            lines.append(cur)
            cur = word
        else:
            cur = trial
    return lines + ([cur] if cur else [])


def fit(text: str, box: Box, sizes: tuple[int, int], face: str, lh: float = 1.12):
    """Largest font size at which the text fits the box. Returns (size, lines, fits)."""
    hi, lo = sizes
    for size in range(hi, lo - 1, -2):
        lines = wrap(text, box.w, size, face)
        if len(lines) * size * lh <= box.h and all(text_width(l, size, face) <= box.w for l in lines):
            return size, lines, True
    lines = wrap(text, box.w, lo, face)
    return lo, lines, False


def _text(lines, box, size, face, color, weight=400, lh=1.12, anchor="start"):
    x = box.x + (box.w / 2 if anchor == "middle" else 0)
    out = []
    for i, line in enumerate(lines):
        y = box.y + size * (i + 0.9) * lh
        out.append(f'<text x="{x:.0f}" y="{y:.0f}" font-family="{SERIF if face == "serif" else SANS}" '
                   f'font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}">{escape(line)}</text>')
    return "".join(out)


def render(spec: ContentSpec, fmt: str, rules: BrandRules, source_name: str = "") -> Rendered:
    L = INFOGRAPHIC if fmt == "infographic" else FORMATS[fmt]
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{L.w}" height="{L.h}" viewBox="0 0 {L.w} {L.h}" '
             f'role="img" aria-label="{escape(spec.headline)}">',
             f'<rect width="{L.w}" height="{L.h}" fill="{spec.bg_color}"/>']
    r = Rendered(fmt, L, "")
    fg = spec.text_color

    lx, ly, ls = L.logo
    if ls:
        parts.append(f'<text x="{lx}" y="{ly}" font-family="{SANS}" font-size="{ls}" font-weight="700" fill="{fg}">Harbor &amp; Pine</text>')

    if L.image:
        b = L.image
        if spec.image and spec.image in rules.approved_images:
            parts.append(f'<rect x="{b.x}" y="{b.y}" width="{b.w}" height="{b.h}" rx="8" fill="{fg}" fill-opacity="0.18"/>'
                         f'<text x="{b.x + 16}" y="{b.y + b.h - 18}" font-family="{SANS}" font-size="{max(12, b.h // 14)}" '
                         f'fill="{fg}" fill-opacity="0.8">approved image: {escape(spec.image)}</text>')
        elif spec.image:
            parts.append(f'<rect x="{b.x}" y="{b.y}" width="{b.w}" height="{b.h}" rx="8" fill="none" stroke="#FFB4A8" '
                         f'stroke-width="4" stroke-dasharray="14 10"/><text x="{b.x + b.w / 2}" y="{b.y + b.h / 2}" '
                         f'text-anchor="middle" font-family="{SANS}" font-size="{max(12, b.h // 10)}" fill="#FFB4A8">'
                         f'Image needed: not in the approved library</text>')
            r.findings.append(Finding(f"{fmt}:image", False, True, f"{spec.image} is not approved; placeholder shown",
                                      "pick an approved image"))

    head_text = (spec.short_headline or spec.headline) if L.use_short_headline else spec.headline
    size, lines, ok = fit(head_text, L.headline, L.head_size, "serif")
    r.lines["headline"] = lines
    parts.append(_text(lines, L.headline, size, "serif", fg, 700))
    if not ok:
        r.findings.append(Finding(f"{fmt}:headline_fit", False, True,
                                  f"headline needs {len(lines)} lines at {size}px; box holds fewer", "shorten the headline"))

    if L.sub and spec.sub:
        size, lines, ok = fit(spec.sub, L.sub, L.sub_size, "sans", 1.25)
        r.lines["sub"] = lines
        parts.append(_text(lines, L.sub, size, "sans", fg, 400, 1.25))
        if not ok:
            r.findings.append(Finding(f"{fmt}:sub_fit", False, True, "supporting line doesn't fit", "shorten it"))

    if L.cta:
        b = L.cta
        size = int(b.h * 0.42)
        label = spec.cta
        while text_width(label, size, "sans") > b.w - b.h * 0.5 and size > 7:
            size -= 1
        parts.append(f'<rect x="{b.x}" y="{b.y}" width="{b.w}" height="{b.h}" rx="{b.h / 2:.0f}" fill="{CTA_BG}"/>'
                     f'<text x="{b.x + b.w / 2}" y="{b.y + b.h / 2 + size * 0.35:.0f}" text-anchor="middle" '
                     f'font-family="{SANS}" font-size="{size}" font-weight="700" fill="#FFFFFF">{escape(label)}</text>')
        r.lines["cta"] = [label]

    if L.chart and spec.figures:
        parts.append(_chart(spec, L.chart, fg, r))

    if L.chart and spec.figures:
        src = f"Source: {source_name}." if source_name else "Source: not provided."
        r.lines["source"] = [src]
        parts.append(_text([src], Box(L.chart.x, L.chart.y + L.chart.h + 4, L.chart.w, 30), 22, "sans", fg))

    if L.disclaimer and spec.disclaimer:
        size, lines, ok = fit(spec.disclaimer, L.disclaimer, L.disc_size, "sans", 1.2)
        r.lines["disclaimer"] = lines
        parts.append(_text(lines, L.disclaimer, size, "sans", fg, 400, 1.2))
        if not ok:
            r.findings.append(Finding(f"{fmt}:disclaimer_fit", False, True,
                                      "disclaimer doesn't fit its slot at the minimum legible size", "resize the slot"))

    parts.append("</svg>")
    r.svg = "".join(parts)
    return r


def _chart(spec: ContentSpec, box: Box, fg: str, r: Rendered) -> str:
    figs = spec.figures
    top = max(f.value for f in figs) or 1
    gap = box.w * 0.08
    bw = (box.w - gap * (len(figs) - 1)) / len(figs)
    label_h, value_h = 60, 80
    max_h = box.h - label_h - value_h
    out, printed = [], []
    for i, f in enumerate(figs):
        h = max_h * f.value / top          # bars start at zero: no exaggerated differences
        x = box.x + i * (bw + gap)
        y = box.y + value_h + (max_h - h)
        value = f"{f.value:.1f}%"
        printed.append(value)
        out.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{bw:.0f}" height="{h:.0f}" rx="10" fill="{fg}" fill-opacity="0.92"/>'
                   f'<text x="{x + bw / 2:.0f}" y="{y - 20:.0f}" text-anchor="middle" font-family="{SERIF}" font-size="60" '
                   f'font-weight="700" fill="{fg}">{value}</text>'
                   f'<text x="{x + bw / 2:.0f}" y="{box.y + box.h - 14:.0f}" text-anchor="middle" font-family="{SANS}" '
                   f'font-size="32" fill="{fg}">{escape(f.label)}</text>')
    r.lines["chart"] = printed
    return "".join(out)


def render_all(spec: ContentSpec, rules: BrandRules, source_name: str = "") -> dict[str, Rendered]:
    fmts = ["infographic"] if len(spec.figures) > 1 else list(FORMATS)
    return {f: render(spec, f, rules, source_name) for f in fmts}


def check_rendered(spec: ContentSpec, outputs: dict[str, Rendered], source: dict, source_name: str = "") -> list[Finding]:
    """Checks on what was actually drawn, not on the spec: the last line of defense."""
    out: list[Finding] = []
    for fmt, r in outputs.items():
        out += r.findings
        if states_rate(spec):
            disc = " ".join(r.lines.get("disclaimer", []))
            out.append(Finding(f"{fmt}:disclaimer_rendered", bool(disc) and disc == spec.disclaimer, True,
                               "disclaimer rendered in full" if disc == spec.disclaimer else "disclaimer missing or cut",
                               "add or resize the disclaimer slot"))
        if "chart" in r.lines:
            src = r.lines.get("source", [""])[0]
            out.append(Finding(f"{fmt}:source_printed", bool(source_name) and source_name in src, True,
                               src or "no source line", "print the source under the chart"))
            for f in spec.figures:
                drawn = f"{f.value:.1f}%" in r.lines["chart"]
                ok = drawn and abs(source.get(f.source_field, float("nan")) - f.value) < 1e-9
                out.append(Finding(f"{fmt}:bar {f.label}", ok, True,
                                   f"bar {f.label} drawn at {f.value}%, offer sheet {source.get(f.source_field)}",
                                   "use the offer-sheet value"))
        for num in re.findall(r"(\d+(?:\.\d+)?)%", r.text):
            ok = any(abs(float(num) - v) < 1e-9 for v in source.values() if isinstance(v, (int, float)))
            out.append(Finding(f"{fmt}:number {num}%", ok, True,
                               f"{num}% {'matches' if ok else 'is NOT in'} the offer sheet", "use the offer-sheet value"))
    return out
