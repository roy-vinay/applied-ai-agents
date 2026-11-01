"""Draws docs/architecture-{light,dark}.svg. Run: python docs/make_architecture.py"""
from pathlib import Path
from html import escape

OUT = Path(__file__).parent
SERIF = "Georgia, 'Times New Roman', serif"
SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, Menlo, monospace"
W, H = 1200, 640

T = {
    "light": dict(bg="#FFFFFF", ink="#1F2328", muted="#59636E", line="#D0D7DE", box="#F6F8FA", lane="#F3F5F8",
                  core="#18202C", core_ink="#F0F3F6", core_muted="#9AA6B5", core_box="#222C3B", core_line="#3A4658",
                  accent="#C2410C", arrow="#59636E", people="#FFF7ED"),
    "dark": dict(bg="#0D1117", ink="#E6EDF3", muted="#9198A1", line="#30363D", box="#161B22", lane="#11161D",
                 core="#1C2533", core_ink="#F0F3F6", core_muted="#9AA6B5", core_box="#2A3446", core_line="#3D4A5E",
                 accent="#FF8A3D", arrow="#9198A1", people="#221A12"),
}


def svg(theme: str) -> str:
    c = T[theme]
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" '
         f'aria-label="Brand Review architecture. A brief, the offer sheet and versioned brand rules feed the agent core: '
         f'the drafter writes copy, pre-review applies reviewers\' lessons and safe rule fixes, the renderer draws every '
         f'format, and render checks verify what was drawn. The marketer sends; reviewers decide on a no-login link; '
         f'each correction becomes a scoped lesson; approved packages go to the system of record. A campaign workflow '
         f'tracks every stage.">',
         f'<defs><marker id="a-{theme}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
         f'<path d="M0,0 L10,5 L0,10 z" fill="{c["arrow"]}"/></marker>'
         f'<marker id="o-{theme}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
         f'<path d="M0,0 L10,5 L0,10 z" fill="{c["accent"]}"/></marker></defs>',
         f'<rect width="{W}" height="{H}" fill="{c["bg"]}"/>']

    def text(x, y, s, size=14, fill=None, weight=400, font=SANS, anchor="start"):
        o.append(f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" font-weight="{weight}" '
                 f'fill="{fill or c["ink"]}" text-anchor="{anchor}">{escape(s)}</text>')

    def box(x, y, w, h, title, sub, file=None, dark=False, accent=False):
        fill = c["core_box"] if dark else c["box"]
        stroke = c["accent"] if accent else (c["core_line"] if dark else c["line"])
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{fill}" stroke="{stroke}" '
                 f'stroke-width="{2 if accent else 1}"/>')
        ink, muted = (c["core_ink"], c["core_muted"]) if dark else (c["ink"], c["muted"])
        text(x + 14, y + 26, title, 15.5 if len(title) < 13 else 14.5, ink, 700)
        for i, line in enumerate(sub):
            text(x + 14, y + 47 + i * 18, line, 13, muted)
        if file:
            text(x + 14, y + h - 12, file, 11.5, c["accent"], 600, MONO)

    def arrow(points, label=None, lx=None, ly=None, orange=False, dashed=False):
        col = c["accent"] if orange else c["arrow"]
        pts = " ".join(f"{x},{y}" for x, y in points)
        o.append(f'<polyline points="{pts}" fill="none" stroke="{col}" stroke-width="{2.2 if orange else 1.6}" '
                 f'{"stroke-dasharray=\"6 5\" " if dashed else ""}marker-end="url(#{"o" if orange else "a"}-{theme})"/>')
        if label:
            text(lx, ly, label, 12.5, col, 700 if orange else 500)

    # Column headings
    text(40, 44, "INPUTS", 12, c["muted"], 700)
    text(300, 44, "AGENT CORE", 12, c["muted"], 700)
    text(940, 44, "PEOPLE AND SYSTEMS", 12, c["muted"], 700)
    o.append(f'<line x1="40" y1="58" x2="{W - 40}" y2="58" stroke="{c["line"]}"/>')

    # Inputs
    box(40, 92, 210, 78, "Brief", ["What, who, where it runs,", "and the launch date"])
    box(40, 206, 210, 78, "Offer sheet", ["The only source of every", "number an ad may print"])
    box(40, 320, 210, 78, "Brand rules", ["Versioned; owned by Brand", "(contrast, disclaimers, fit)"])

    # Agent core lane
    o.append(f'<rect x="290" y="76" width="610" height="420" rx="16" fill="{c["core"]}"/>')
    text(312, 104, "Agent core", 20, c["core_ink"], 700, SERIF)
    text(430, 104, "standard-library Python, 25 must-pass evals in CI", 12.5, c["core_muted"])
    box(312, 124, 130, 112, "Drafter", ["3 directions;", "asks if a fact", "is missing"], "drafter.py", dark=True)
    box(458, 124, 130, 112, "Pre-review", ["applies lessons,", "safe rule fixes,", "re-checks"], "prereview.py", dark=True)
    box(604, 124, 130, 112, "Renderer", ["one spec, six", "formats, each", "its own layout"], "render.py", dark=True)
    box(750, 124, 130, 112, "Render checks", ["what was drawn:", "numbers vs offer", "sheet, disclaimer"], "render.py", dark=True)
    box(312, 300, 130, 112, "Rules", ["WCAG contrast,", "disclaimers,", "approved images"], "rules.py", dark=True)
    box(458, 300, 130, 112, "Lessons", ["owned, scoped;", "only in-scope", "ones apply"], "lessons.py", dark=True, accent=True)
    box(604, 300, 130, 112, "Routing", ["picks reviewers", "and whose", "lessons apply"], "routing.py", dark=True)
    arrow([(442, 180), (456, 180)])
    arrow([(588, 180), (602, 180)])
    arrow([(734, 180), (748, 180)])
    arrow([(545, 300), (545, 238)])                                        # lessons -> pre-review
    arrow([(377, 300), (377, 270), (495, 270), (495, 238)])                # rules -> pre-review
    arrow([(420, 300), (420, 258), (815, 258), (815, 238)])                # rules -> render checks
    arrow([(604, 356), (590, 356)], dashed=True)                            # routing -> lessons
    for i, line in enumerate(["Every change carries its source.", "A failing required check blocks sending.",
                              "Conflicting lessons: a person decides."]):
        text(566, 442 + i * 18, line, 12.5, c["core_muted"])

    # Inputs -> core
    arrow([(250, 131), (310, 131)])
    arrow([(250, 245), (280, 245), (280, 160), (310, 160)])                # offer sheet -> drafter
    arrow([(250, 359), (310, 359)])                                         # brand rules -> rules

    # People
    o.append(f'<rect x="930" y="76" width="230" height="420" rx="16" fill="{c["people"]}" stroke="{c["line"]}"/>')
    box(948, 96, 194, 92, "Marketer", ["approves the plan; sends", "once every check passes"])
    box(948, 226, 194, 110, "Reviewer link", ["no login; one decision,", "past rulings, a fix;", "Legal · Brand · Compliance"], accent=True)
    box(948, 384, 194, 92, "System of record", ["approved package;", "publishing waits for a person"])
    arrow([(880, 180), (946, 142)])
    arrow([(1045, 188), (1045, 224)], "sends", 1053, 212)
    arrow([(1045, 336), (1045, 382)], "approved", 1053, 366)
    # The learning loop
    arrow([(948, 300), (915, 300), (915, 536), (523, 536), (523, 414)], "a correction with a reason becomes a scoped lesson",
          560, 528, orange=True)

    # Workflow bar
    o.append(f'<rect x="40" y="568" width="{W - 80}" height="48" rx="12" fill="{c["lane"]}" stroke="{c["line"]}"/>')
    text(60, 597, "Campaign workflow", 14, c["ink"], 700)
    stages = ["Brief", "Plan", "Create", "Review", "Approved", "Live"]
    x = 230
    for i, s in enumerate(stages):
        text(x, 597, s, 14, c["ink"], 600)
        x += len(s) * 8.6 + 14
        if i < len(stages) - 1:
            text(x, 597, "→", 14, c["muted"])
            x += 26
    text(W - 60, 597, "one holder at a time · illegal moves raise · workflow.py", 12.5, c["muted"], 400, SANS, "end")
    o.append("</svg>")
    return "\n".join(o)


for th in T:
    (OUT / f"architecture-{th}.svg").write_text(svg(th) + "\n")
print("ok")
