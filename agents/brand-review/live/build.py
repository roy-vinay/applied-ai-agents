"""Build live/index.html: a copy of the web demo, wired to the real agent code.

The original demo (../index.html) is never modified. This script reads it, applies a short
list of exact patches, and injects the agent's Python files plus a small bridge so that:

  - every ad is drawn by agent/render.py
  - brand checks and "blocks sending" come from agent/rules.py and the render checks
  - Legal's lessons are learned, applied and retired by agent/lessons.py and retrieval.py
  - the refinance directions come from agent/drafter.py

Everything else in the demo (nudges, deadlines, insights numbers, agent run timings) stays
scripted, and the page says so. Each patch must match exactly once, or the build fails.

    python live/build.py            # writes live/index.html
    python live/build.py --check    # fail if live/index.html is stale (used in CI)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PYODIDE = "314.0.7"
FILES = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "agent").glob("*.py")) + ["live/bridge.py"]

BRIDGE_JS = r"""
<script src="https://cdn.jsdelivr.net/npm/pyodide@__V__/pyodide.js"></script>
<script id="py-src" type="application/json">__SRC__</script>
<script>
window.PY = null;
window.PY_BOOT = (async () => {
  const src = JSON.parse(document.getElementById("py-src").textContent);
  const py = await loadPyodide({indexURL: "https://cdn.jsdelivr.net/npm/pyodide@__V__/"});
  for (const [p, s] of Object.entries(src)) {
    py.FS.mkdirTree("/app/" + p.split("/").slice(0, -1).join("/"));
    py.FS.writeFile("/app/" + p, s);
  }
  py.runPython('import sys; sys.path.insert(0, "/app/live"); sys.path.insert(0, "/app")');
  const b = py.pyimport("bridge"), cache = new Map();
  const memo = (fn, k) => { if (!cache.has(k)) { if (cache.size > 500) cache.clear(); cache.set(k, fn(k)); } return cache.get(k); };
  window.PY = {
    ad: o => memo(k => b.render_ad(k.slice(2)), "ad" + JSON.stringify(o)),
    checks: o => JSON.parse(memo(k => b.check_ad(k.slice(2)), "ck" + JSON.stringify(o))),
    reset: () => { cache.clear(); return b.reset(); },
    learn: () => b.learn_payment_claim(),
    retire: id => b.retire(id),
    ploan: () => JSON.parse(b.ploan_prereview()),
    directions: () => JSON.parse(b.directions()),
    version: py.runPython("import sys; sys.version.split()[0]"),
  };
})();
// The demo's description of an ad, in the shape agent/render.py and agent/rules.py expect.
function pySp(sp, c) {
  return {id: c ? c.id : (S.drawer || ""), campaign: c ? c.name : "", head: sp.head || "",
    sub: c && c.hideSub ? "" : (sp.sub || ""), cta: sp.cta || "", disc: c && c.hideDisc ? "" : (sp.disc || ""),
    short: sp.short || "", bg: c && c.contrastFixed ? shade(sp.bg) : sp.bg, photo: sp.photo ? 1 : 0,
    photoMissing: sp.photoMissing ? 1 : 0, data: sp.data || null,
    min_contrast: +((S.R && S.R.brand.contrast) || 4.5), banner_max: +((S.R && S.R.brand.banner) || 30)};
}
function pyAd(sp, fmt, w, extra, c) {
  const svg = PY.ad(Object.assign(pySp(sp, c), {fmt}))
    .replace(/width="\d+" height="\d+"/, 'width="100%" style="display:block;height:auto"');
  return `<div class="adbox" data-drawn-by="agent/render.py" title="Drawn by agent/render.py" style="position:relative;width:${w}px;max-width:100%;flex:none">${svg}${extra || ""}</div>`;
}
const PY_FMT = {post: "post_1x1", portrait: "portrait_4x5", story: "story_9x16", d300: "display_300x250", d728: "leaderboard_728x90"};
// Brand checks from agent/rules.py and the render checks, mapped onto the demo's six rows.
function checks(c) {
  const k = checksJS(c);
  if (!window.PY) return k;
  const f = PY.checks(pySp(c.sp, c));
  const pick = p => f.filter(x => p(x.rule));
  const row = (n, list, req, fix, fixl, none) => {
    const bad = list.filter(x => !x.ok);
    return {n, ok: !bad.length, req, ev: list.length ? (bad[0] || list[0]).evidence : none,
            gap: bad.map(x => x.evidence).join("; "), fix, fixl};
  };
  const rules = [
    {n: "Brand fonts", ok: true, ev: "agent/render.py draws brand type only"},
    row("Approved image", pick(r => r === "approved_image" || r.endsWith(":image")), true, "", "Pick an approved image", "No image slot"),
    row("Contrast", pick(r => r === "contrast"), true, "contrast", "Let the Designer darken the background", ""),
    row("Sourced numbers", pick(r => r.startsWith("figure:") || r.includes(":number ") || r.includes(":bar ") || r.endsWith(":source_printed")), true, "source", "Use the source values", "No numbers printed"),
    row("Disclaimer", pick(r => r === "disclaimer" || r.endsWith(":disclaimer_rendered") || r.endsWith(":disclaimer_fit")), true, "adddisc", "Add the disclaimer", ""),
    row("Banner fit", pick(r => r === "banner_fit" || r === "leaderboard_728x90:headline_fit"), false, "shorten", "Let the agent shorten it", ""),
  ];
  return {rules, score: rules.filter(r => r.ok).length, human: k.human, blocked: rules.filter(r => r.req && !r.ok)};
}
</script>
"""

PATCHES = [
    ("<title>Brand Review: guided simulation</title>",
     "<title>Brand Review: live, running the agent code</title>"),
    ('Guided simulation<span class="simfull"> · no live AI · fictional brand and offers</span>',
     '<span title="Ads, brand checks, drafted directions and Legal\'s lessons come from agent/*.py, running in your browser. '
     'Nudges, deadlines, insights numbers and agent run timings are scripted.">Live: agent code running in your browser'
     '<span class="simfull"> · nudges and insights scripted · fictional brand</span></span>'),
    ('<div id="toastRoot"></div>', '<div id="toastRoot"></div>__BRIDGE__'),
    ('function ad(sp,w,extra=""){',
     'function ad(sp,w,extra=""){if(window.PY)return pyAd(sp,sp.data?"infographic":"post_1x1",w,extra,null);'),
    ("function fmtAd(c,kind,w,big){",
     "function fmtAd(c,kind,w,big){if(window.PY)return pyAd(c.sp,c.sp.data&&kind!==\"d728\"?\"infographic\":PY_FMT[kind],w,\"\",c);"),
    ("function checks(c){", "function checksJS(c){"),
    ("function lessonActive(){",
     'function lessonActive(){if(window.PY)return PY.ploan().lessons.some(l=>/could lower/.test(l.source));'),
    ('c=>{c.sp.sub=c.sp.sub.replace("and lower your","and you could lower your");}',
     'c=>{c.sp.sub=window.PY?PY.ploan().sub:c.sp.sub.replace("and lower your","and you could lower your");}'),
    ('scope:"Lending · all regions"});}',
     'scope:"Lending · all regions"});if(window.PY){S.amem["Legal pre-reviewer"][0].pyId=PY.learn();}}'),
    ('S.amem[r].splice(+i,1);toast("Retired.',
     'if(window.PY&&m.pyId)PY.retire(m.pyId);S.amem[r].splice(+i,1);toast("Retired.'),
    ("function reset(){CLK=600;",
     'function reset(){if(window.PY){const id=PY.reset();setTimeout(()=>{const g=(S.amem["Legal pre-reviewer"]||[])'
     '.find(m=>/guaranteed/.test(m.x));if(g)g.pyId=id;},0);}CLK=600;'),
    ("reset();render();",
     '$("view").innerHTML=\'<div class="card" style="padding:24px;margin:20px">Loading the agent code: Python in your '
     'browser, about 10 MB on first visit…</div>\';PY_BOOT.then(()=>{PY.directions().forEach((n,i)=>{if(DIRS[i])DIRS[i].n=n;});'
     'reset();render();}).catch(e=>{$("view").innerHTML=\'<div class="card" style="padding:24px;margin:20px">'
     'Could not load the agent code: \'+e+\'</div>\';});'),
]


def build() -> str:
    page = (ROOT / "index.html").read_text()
    for old, new in PATCHES:
        n = page.count(old)
        if n != 1:
            raise SystemExit(f"patch anchor found {n} times (need exactly 1): {old[:70]}")
        page = page.replace(old, new)
    sources = json.dumps({f: (ROOT / f).read_text() for f in FILES}).replace("</", "<\\/")
    bridge = BRIDGE_JS.replace("__V__", PYODIDE).replace("__SRC__", sources)
    return page.replace("__BRIDGE__", bridge)


def main() -> int:
    out = ROOT / "live" / "index.html"
    page = build()
    if "--check" in sys.argv:
        if not out.exists() or out.read_text() != page:
            print("live/index.html is out of date. Run: python live/build.py")
            return 1
        print(f"live/index.html matches the demo and the code ({len(PATCHES)} patches, {len(FILES)} files)")
        return 0
    out.write_text(page)
    print(f"wrote live/index.html: {len(PATCHES)} patches applied, {len(FILES)} Python files inlined")
    return 0


if __name__ == "__main__":
    sys.exit(main())
