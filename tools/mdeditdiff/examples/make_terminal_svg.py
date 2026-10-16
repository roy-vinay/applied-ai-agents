"""Turn the output of examples/walkthrough.sh into an animated terminal SVG for the README.

Usage: ./examples/walkthrough.sh | python3 examples/make_terminal_svg.py > docs/img/walkthrough.svg
"""
import html
import re
import sys

LINE_H, CHAR_W, PAD = 19, 7.8, 18
STEP_PAUSE, LINE_GAP, HOLD = 1.6, 0.07, 6.0
COLORS = {"36": "#56b6c2", "2": "#8b93a1"}

raw = sys.stdin.read()
raw = re.sub(r"/tmp/\S+|/var/folders/\S+", "a temporary folder", raw)
lines = raw.rstrip("\n").split("\n")

t, items = 0.6, []
for line in lines:
    style = None
    m = re.match(r"\x1b\[([\d;]+)m(.*?)\x1b\[0m$", line)
    if m:
        codes, line = m.group(1).split(";"), m.group(2)
        style = "cmd" if "2" in codes else "say" if "36" in codes else "title"
        if style == "say":
            t += STEP_PAUSE
    line = re.sub(r"\x1b\[[\d;]*m", "", line)
    items.append((t, line, style))
    t += 0.35 if style == "cmd" else LINE_GAP
total = t + HOLD

width = int(PAD * 2 + CHAR_W * max(len(l) for _, l, _ in items))
height = int(PAD * 2 + 26 + LINE_H * len(items))
out = [
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="mdEditDiff walkthrough in a terminal: a planner agent, a person and an implementer agent share plan.md, and the implementer asks what changed">',
    "<style>",
    "text{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px;fill:#d7dae0;white-space:pre}",
    ".say{fill:#56b6c2;font-weight:700}.title{fill:#ffffff;font-weight:700}.cmd{fill:#8b93a1}.add{fill:#98c379}.del{fill:#e06c75}.mod{fill:#e5c07b}",
    "</style>",
    f'<rect width="{width}" height="{height}" rx="10" fill="#1e2127"/>',
    '<circle cx="20" cy="18" r="6" fill="#ff5f57"/><circle cx="40" cy="18" r="6" fill="#febc2e"/><circle cx="60" cy="18" r="6" fill="#28c840"/>',
]
for i, (start, line, style) in enumerate(items):
    a, b = start / total * 100, min(start / total * 100 + 0.8, 99)
    name = f"l{i}"
    out.append(f"<style>@keyframes {name}{{0%,{a:.2f}%{{opacity:0}}{b:.2f}%,98%{{opacity:1}}100%{{opacity:0}}}}.{name}{{animation:{name} {total:.1f}s linear infinite;opacity:0}}</style>")
    cls = style or ""
    stripped = line.lstrip()
    if not cls:
        if stripped.startswith("+ added"): cls = "add"
        elif stripped.startswith("- removed"): cls = "del"
        elif stripped.startswith("~ modified"): cls = "mod"
    y = PAD + 26 + LINE_H * (i + 1) - 5
    out.append(f'<text x="{PAD}" y="{y}" class="{name} {cls}" xml:space="preserve">{html.escape(line)}</text>')
out.append("</svg>")
print("\n".join(out))
