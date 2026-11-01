"""Draws docs/teaching-{light,dark}.svg: fixing the ad vs teaching the agent, with the replay's numbers.

Run: python docs/make_teaching.py   (reads benchmark/results.json, so the numbers stay in sync)
"""
import json
from html import escape
from pathlib import Path

HERE = Path(__file__).parent
R = json.loads((HERE.parent / "benchmark" / "results.json").read_text())
SERIF = "Georgia, 'Times New Roman', serif"
SANS = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, Menlo, monospace"
W, H = 1200, 560

T = {
    "light": dict(bg="#FFFFFF", ink="#1F2328", muted="#59636E", line="#D0D7DE", box="#F6F8FA", accent="#C2410C",
                  accent_soft="#FFF7ED", bad="#B42318", bad_soft="#FDECEA", ok="#1F7A4D", ok_soft="#E3F4EA", legal="#1F7A4D"),
    "dark": dict(bg="#0D1117", ink="#E6EDF3", muted="#9198A1", line="#30363D", box="#161B22", accent="#FF8A3D",
                 accent_soft="#221A12", bad="#FF8A7A", bad_soft="#3A1A17", ok="#4CC38A", ok_soft="#16301F", legal="#4CC38A"),
}


def svg(theme: str) -> str:
    c = T[theme]
    off, sco, uns = R["off"], R["scoped"], R["unscoped"]
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" '
         f'aria-label="Fix the ad versus teach the agent. Fixing only the ad: Dana makes the same payment-claim correction '
         f'on the auto loan, the personal loan and the mortgage; {off["repeat_corrections_per_quarter"]:.0f} repeat corrections '
         f'a quarter, {off["mean_rounds"]} review rounds per campaign. Teaching her Legal agent: the correction becomes a '
         f'lesson scoped to lending; the personal loan arrives already fixed, and the certificate is left alone because it is '
         f'out of scope; {sco["repeat_corrections_per_quarter"]:.0f} repeat corrections, {sco["mean_rounds"]} rounds, '
         f'zero out-of-scope edits.">',
         f'<rect width="{W}" height="{H}" fill="{c["bg"]}"/>']

    def text(x, y, s, size=13, fill=None, weight=400, font=SANS, anchor="start"):
        o.append(f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" font-weight="{weight}" '
                 f'fill="{fill or c["ink"]}" text-anchor="{anchor}">{escape(s)}</text>')

    def rect(x, y, w, h, fill, stroke=None, r=10, sw=1):
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" '
                 f'stroke="{stroke or fill}" stroke-width="{sw}"/>')

    def step(x, y, w, campaign, line1, line2, tone):
        fill, stroke, ink = {"bad": (c["bad_soft"], c["bad"], c["bad"]), "ok": (c["ok_soft"], c["ok"], c["ok"]),
                             "teach": (c["accent_soft"], c["accent"], c["accent"]), "plain": (c["box"], c["line"], c["muted"])}[tone]
        rect(x, y, w, 78, fill, stroke)
        text(x + 16, y + 26, campaign, 15, c["ink"], 700)
        text(x + 16, y + 48, line1, 13, ink, 600)
        text(x + 16, y + 66, line2, 12.5, c["muted"])

    def stats(x, y, items, color):
        for i, (big, small) in enumerate(items):
            xx = x + i * 172
            text(xx, y, big, 30, color, 700, SERIF)
            text(xx, y + 22, small, 12.5, c["muted"])

    text(40, 44, "WHAT A REVIEWER'S CORRECTION DOES", 12, c["muted"], 700)
    text(W - 40, 44, "Dana (Legal) strikes “lower your monthly payment” on the auto loan", 12.5, c["muted"], 400, SANS, "end")
    o.append(f'<line x1="40" y1="58" x2="{W - 40}" y2="58" stroke="{c["line"]}"/>')

    # Left: fix the ad
    lx, rx, pw = 40, 620, 540
    rect(lx, 76, pw, 456, c["bg"], c["line"], 16)
    text(lx + 24, 112, "Fix the ad", 24, c["ink"], 700, SERIF)
    text(lx + 24, 136, "“This campaign only.” The agent learns nothing.", 13.5, c["muted"])
    step(lx + 24, 156, pw - 48, "Auto loan refinance", "Dana corrects the payment claim", "round 2 for this campaign", "bad")
    step(lx + 24, 246, pw - 48, "Personal loan", "Same claim again. Dana corrects it again", "the agent didn't know", "bad")
    step(lx + 24, 336, pw - 48, "Mortgage refinance", "And again", "every lending campaign, every quarter", "bad")
    stats(lx + 24, 466, [(f'{off["repeat_corrections_per_quarter"]:.0f}', "repeat fixes a quarter"),
                         (f'{off["mean_rounds"]:.2f}', "rounds per campaign"),
                         (f'{off["first_pass"]:.0%}', "first-pass approval")], c["bad"])

    # Right: teach the agent
    rect(rx, 76, pw, 456, c["bg"], c["accent"], 16, 2)
    text(rx + 24, 112, "Teach the agent", 24, c["ink"], 700, SERIF)
    text(rx + 24, 136, "“Teach my Legal agent: all lending.” Owned by Legal.", 13.5, c["muted"])
    step(rx + 24, 156, pw - 48, "Auto loan refinance", "Dana corrects it and teaches her agent",
         "lesson: “could lower”, not “lower” · lending · owner Legal", "teach")
    step(rx + 24, 246, pw - 48, "Personal loan", "Arrives already fixed", "the asset cites Dana's lesson as the reason", "ok")
    step(rx + 24, 336, pw - 48, "Certificate", "Left alone: out of scope", "“guaranteed” is accurate on a fixed rate", "plain")
    stats(rx + 24, 466, [(f'{sco["repeat_corrections_per_quarter"]:.0f}', "repeat fixes a quarter"),
                         (f'{sco["mean_rounds"]:.2f}', "rounds per campaign"),
                         (f'{sco["wrong_scope_edits_per_quarter"]:.0f}', "out-of-scope edits")], c["ok"])

    text(40, H - 8, f"Seeded replay of 120 campaigns, simulated reviewers. Without scope, the same lessons make "
         f"{uns['wrong_scope_edits_per_quarter']:.0f} wrong edits a quarter.", 12, c["muted"])
    text(W - 40, H - 8, "benchmark/replay.py · agent/review.py", 12, c["muted"], 400, MONO, "end")
    o.append("</svg>")
    return "\n".join(o)


if __name__ == "__main__":
    for th in T:
        (HERE / f"teaching-{th}.svg").write_text(svg(th) + "\n")
    print("wrote docs/teaching-light.svg and docs/teaching-dark.svg")
