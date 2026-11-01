"""Draws docs/lifecycle-{light,dark}.svg from the rules in agent/workflow.py. Run: python docs/make_lifecycle.py"""
from html import escape
from pathlib import Path

OUT = Path(__file__).parent
SERIF = "Georgia, 'Times New Roman', serif"
SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, Menlo, monospace"
W, H = 1200, 500

T = {
    "light": dict(bg="#FFFFFF", ink="#1F2328", muted="#59636E", line="#D0D7DE", box="#F6F8FA", accent="#C2410C",
                  arrow="#59636E", agent="#2F5BEA", marketer="#B7791F", reviewer="#7A4BC2", nobody="#8C959F"),
    "dark": dict(bg="#0D1117", ink="#E6EDF3", muted="#9198A1", line="#30363D", box="#161B22", accent="#FF8A3D",
                 arrow="#9198A1", agent="#6F95FF", marketer="#F2B04A", reviewer="#B596F0", nobody="#6E7681"),
}
# (stage, holder) in order; holders match Campaign.move() in agent/workflow.py
STAGES = [("Brief", "agent"), ("Plan", "marketer"), ("Create", "agent"), ("Review", "reviewer"),
          ("Approved", "marketer"), ("Live", "nobody")]
X0, BW, GAP, Y, BH = 40, 140, 56, 176, 92


def svg(theme: str) -> str:
    c = T[theme]
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" '
         f'aria-label="Campaign lifecycle. Brief, held by the agent, moves to Plan when the agent drafts it. The marketer '
         f'approves the plan to move it to Create, held by the agent, which fixes its own failed self-checks. Only the '
         f'marketer can send it to Review, and only when every required check passes. A reviewer either requests a change, '
         f'which sends it back to Create and adds a round, or approves it. Conflicting reviewers go to the marketer. Only '
         f'a person moves Approved to Live; the agent never publishes. Illegal moves raise an error and are tested in CI.">',
         ''.join(f'<marker id="m-{k}-{theme}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
                 f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{c[k]}"/></marker>'
                 for k in ("arrow", "accent", "agent", "marketer", "reviewer")).join(["<defs>", "</defs>"]),
         f'<rect width="{W}" height="{H}" fill="{c["bg"]}"/>']

    def text(x, y, s, size=13, fill=None, weight=400, font=SANS, anchor="start"):
        o.append(f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" font-weight="{weight}" '
                 f'fill="{fill or c["ink"]}" text-anchor="{anchor}">{escape(s)}</text>')

    def path(d, color="arrow", width=1.6, dashed=False):
        o.append(f'<path d="{d}" fill="none" stroke="{c[color]}" stroke-width="{width}" '
                 f'{"stroke-dasharray=\"6 5\" " if dashed else ""}marker-end="url(#m-{color}-{theme})"/>')

    x_of = lambda i: X0 + i * (BW + GAP)
    text(40, 44, "CAMPAIGN LIFECYCLE", 12, c["muted"], 700)
    text(W - 40, 44, "one holder at a time · moves enforced by agent/workflow.py", 12.5, c["muted"], 400, SANS, "end")
    o.append(f'<line x1="40" y1="58" x2="{W - 40}" y2="58" stroke="{c["line"]}"/>')

    for i, (stage, holder) in enumerate(STAGES):
        x = x_of(i)
        o.append(f'<rect x="{x}" y="{Y}" width="{BW}" height="{BH}" rx="12" fill="{c["box"]}" stroke="{c[holder]}" stroke-width="2"/>')
        o.append(f'<rect x="{x}" y="{Y}" width="{BW}" height="6" rx="3" fill="{c[holder]}"/>')
        text(x + 16, Y + 40, stage, 22, c["ink"], 700, SERIF)
        o.append(f'<circle cx="{x + 21}" cy="{Y + 66}" r="5" fill="{c[holder]}"/>')
        text(x + 32, Y + 71, "done" if holder == "nobody" else f"held by {holder}", 12.5, c["muted"])

    # forward moves: (from index, label, who moves it, guarded?)
    forward = [(0, "drafts", "agent", False), (1, "approves", "marketer", False),
               (2, "sends", "marketer", True), (3, "approves", "reviewer", False), (4, "hands off", "marketer", True)]
    for i, label, who, guarded in forward:
        x1, x2, ym = x_of(i) + BW, x_of(i + 1), Y + BH / 2
        path(f"M{x1 + 2},{ym} L{x2 - 3},{ym}", "accent" if guarded else who, 2.2 if guarded else 1.8)
        text((x1 + x2) / 2, ym - 9, label, 11.5, c["accent"] if guarded else c[who], 700, SANS, "middle")

    # guard notes, under their arrows
    for i, lines in ((2, ["blocked if any required", "check fails"]), (4, ["a person only;", "the agent never publishes"])):
        xm = x_of(i) + BW + GAP / 2
        o.append(f'<line x1="{xm}" y1="{Y + BH / 2 + 6}" x2="{xm}" y2="{Y + BH + 92}" stroke="{c["accent"]}" stroke-dasharray="3 3"/>')
        for k, line in enumerate(lines):
            text(xm, Y + BH + 108 + k * 16, line, 12, c["accent"], 600, SANS, "middle")

    # Plan, above: the drafter stops when a fact is missing (agent/drafter.py)
    x = x_of(1)
    path(f"M{x + 36},{Y - 2} C{x + 26},{Y - 56} {x + BW - 26},{Y - 56} {x + BW - 36},{Y - 4}", "agent")
    text(x + BW / 2, Y - 66, "asks instead of guessing", 12, c["agent"], 600, SANS, "middle")
    text(x + BW / 2, Y - 50, "a missing fact", 12, c["agent"], 600, SANS, "middle")
    # Review -> Create, above: a change request starts another round
    xa, xb = x_of(3), x_of(2)
    path(f"M{xa + 50},{Y - 2} C{xa + 20},{Y - 96} {xb + BW - 20},{Y - 96} {xb + BW - 30},{Y - 4}", "reviewer", 2)
    text((xa + xb + BW) / 2, Y - 92, "change requested: back to Create, round +1", 12, c["reviewer"], 700, SANS, "middle")
    # Create, below: failed self-check, the agent fixes it
    x = x_of(2)
    path(f"M{x + BW - 36},{Y + BH + 2} C{x + BW - 26},{Y + BH + 52} {x + 26},{Y + BH + 52} {x + 36},{Y + BH + 4}", "agent")
    text(x + BW / 2, Y + BH + 66, "self-check fails:", 12, c["agent"], 600, SANS, "middle")
    text(x + BW / 2, Y + BH + 82, "the agent fixes it", 12, c["agent"], 600, SANS, "middle")
    # Review, below: conflicting lessons go to a person (agent/retrieval.py)
    x = x_of(3)
    path(f"M{x + BW - 36},{Y + BH + 2} C{x + BW - 26},{Y + BH + 52} {x + 26},{Y + BH + 52} {x + 36},{Y + BH + 4}", "marketer")
    text(x + BW / 2 + 14, Y + BH + 66, "conflicting lessons:", 12, c["marketer"], 600, SANS, "middle")
    text(x + BW / 2 + 14, Y + BH + 82, "a person decides", 12, c["marketer"], 600, SANS, "middle")

    # legend and provenance
    o.append(f'<line x1="40" y1="{H - 46}" x2="{W - 40}" y2="{H - 46}" stroke="{c["line"]}"/>')
    lx = 40
    for k, name in (("agent", "Agent"), ("marketer", "Marketer"), ("reviewer", "Reviewer"), ("accent", "Guardrail enforced in code")):
        o.append(f'<circle cx="{lx + 6}" cy="{H - 21}" r="5" fill="{c[k]}"/>')
        text(lx + 18, H - 16, name, 12.5, c["muted"])
        lx += 34 + len(name) * 7.2
    text(W - 40, H - 16, "illegal moves raise IllegalMove · agent/workflow.py · tested by eval E13", 12, c["muted"], 400, MONO, "end")
    o.append("</svg>")
    return "\n".join(o)


if __name__ == "__main__":
    for th in T:
        (OUT / f"lifecycle-{th}.svg").write_text(svg(th) + "\n")
    print("wrote docs/lifecycle-light.svg and docs/lifecycle-dark.svg")
