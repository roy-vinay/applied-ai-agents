"""Build web/index.html: the agent's real Python files, inlined into a page that runs them with Pyodide.

    python web/build.py            # writes web/index.html
    python web/build.py --check    # fail if web/index.html is out of date with the code (used in CI)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PYODIDE_VERSION = "314.0.7"
FILES = sorted(str(p.relative_to(ROOT)) for d in ("agent", "evals") for p in (ROOT / d).glob("*.py")) + ["web/app.py"]


def build() -> str:
    sources = {f: (ROOT / f).read_text() for f in FILES}
    blob = json.dumps(sources, indent=0).replace("</", "<\\/")   # safe inside a <script> tag
    page = (ROOT / "web" / "template.html").read_text()
    return page.replace("__PY_SOURCES__", blob).replace("__PYODIDE_VERSION__", PYODIDE_VERSION)


def main() -> int:
    out = ROOT / "web" / "index.html"
    page = build()
    if "--check" in sys.argv:
        if not out.exists() or out.read_text() != page:
            print("web/index.html is out of date with the agent code. Run: python web/build.py")
            return 1
        print(f"web/index.html matches the code ({len(FILES)} files inlined)")
        return 0
    out.write_text(page)
    print(f"wrote {out.relative_to(ROOT)} with {len(FILES)} files inlined")
    return 0


if __name__ == "__main__":
    sys.exit(main())
