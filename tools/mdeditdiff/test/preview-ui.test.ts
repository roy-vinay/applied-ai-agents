// Runs the Mac app's preview page in a real browser engine and checks change highlighting.
// Skipped when no browser is available (CI installs one for this job).

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import * as path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const page = pathToFileURL(path.join(here, "..", "..", "app", "Sources", "MDEditDiffApp", "Resources", "Preview", "preview.html")).href;

const BASE = `# Export reports to CSV

Customers want to download any report as a spreadsheet.

## Steps

1. Add an **Export** button to the report page.
2. Build the CSV on the server.
3. Ship behind the \`csv_export\` feature flag.

## Open questions

- Should exports include archived rows?
- What is the row limit?

## Rollout

| Stage | Who |
| --- | --- |
| Internal | Support |
| Beta | 10 customers |
`;

const NEW = BASE.replace("2. Build the CSV on the server.", "2. Build the CSV on the server, streaming rows so large reports never time out.")
  .replace("- Should exports include archived rows?\n", "")
  .replace("- What is the row limit?", "- What is the row limit? Proposed: 100,000 rows.")
  .replace("## Rollout", "Decision: archived rows are excluded.\n\n## Rollout")
  .replace("| Beta | 10 customers |", "| Beta | 25 customers |");

let browser: any = null;
let skip = "";

before(async () => {
  try {
    const { chromium } = await import("playwright");
    browser = await chromium.launch(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {});
  } catch (e) {
    skip = `no browser available (${(e as Error).message.split("\n")[0]})`;
  }
});
after(async () => browser?.close());

async function open(width = 900) {
  const ctx = await browser.newContext({ bypassCSP: true, viewport: { width, height: 900 } });
  const p = await ctx.newPage();
  const errors: string[] = [];
  p.on("pageerror", (e: Error) => errors.push(e.message));
  await p.goto(page);
  await p.evaluate(() => ((window as any).mdTestLog = []));
  return { p, errors };
}

test("highlights added, changed and removed blocks with word-level marks", async (t) => {
  if (skip) return t.skip(skip);
  const { p, errors } = await open();
  await p.evaluate(([base, cur]: string[]) => {
    (window as any).mdRender(cur);
    (window as any).mdSetReview({ mode: "unread", baseText: base, revisions: [{ revision: "r2", source: "observed" }, { revision: "r3", source: "checkpoint", author: "planner", note: "Proposed a row limit" }] });
  }, [BASE, NEW]);

  const info = await p.evaluate(() => {
    const q = (s: string) => Array.from(document.querySelectorAll("#doc " + s.split(",").join(", #doc "))).map((e) => (e as HTMLElement).innerText.trim());
    return {
      bar: (document.getElementById("review-bar") as HTMLElement).innerText,
      added: q(".md-added"),
      modified: q(".md-modified"),
      removed: q(".md-removed .md-removed-body"),
      ins: q("ins.md-ins"),
      del: q("del.md-del"),
      boldKept: !!document.querySelector("#doc li strong"),
      log: (window as any).mdTestLog,
      removedBeforeNext: (document.querySelector("#doc .md-removed") as HTMLElement)?.nextElementSibling?.textContent?.trim(),
    };
  });
  assert.deepEqual(errors, []);
  assert.match(info.bar, /5 changes since you last read/);
  assert.match(info.bar, /planner: “Proposed a row limit”/);
  assert.match(info.bar, /1 not reported/);
  assert.deepEqual(info.added, ["Decision: archived rows are excluded."]);
  assert.equal(info.modified.length, 3);
  assert.deepEqual(info.ins, [", streaming rows so large reports never time out", "Proposed: 100,000 rows.", "25"]);
  assert.deepEqual(info.del, ["10"]);
  assert.deepEqual(info.removed, ["Should exports include archived rows?"]);
  assert.equal(info.removedBeforeNext, "What is the row limit? Proposed: 100,000 rows.");
  assert.ok(info.boldKept);
  assert.deepEqual(info.log[0], { action: "count", n: 5, mode: "unread" });
});

test("restore, mark as read, next/previous and history post the right actions", async (t) => {
  if (skip) return t.skip(skip);
  const { p, errors } = await open();
  await p.evaluate(([base, cur]: string[]) => {
    (window as any).mdRender(cur);
    (window as any).mdSetReview({ mode: "unread", baseText: base, revisions: [] });
  }, [BASE, NEW]);
  await p.click(".md-restore");
  await p.click("text=Mark as read");
  await p.click("text=Next ›");
  await p.click("text=Next ›");
  const current = await p.evaluate(() => document.querySelectorAll("#doc .md-current").length);
  await p.evaluate(() =>
    (window as any).mdShowHistory(
      [
        { revision: "r3", time: "2026-10-16T05:00:00Z", source: "checkpoint", author: "planner", note: "Proposed a row limit" },
        { revision: "r2", time: "2026-10-16T04:00:00Z", source: "observed" },
      ],
      "r2",
    ),
  );
  await p.click("#history >> text=Compare");
  await p.click("#history >> text=Restore");
  const log = await p.evaluate(() => (window as any).mdTestLog.filter((m: any) => m.action !== "count"));
  assert.deepEqual(errors, []);
  assert.equal(current, 1);
  assert.deepEqual(log, [
    { action: "restoreBlock", text: "- Should exports include archived rows?", beforeLine: 13, kind: "list-item" },
    { action: "markRead" },
    { action: "compare", revision: "r2" },
    { action: "restoreVersion", revision: "r2" },
  ]);
});

test("no review: no bar and no highlights; compare mode shows its own title", async (t) => {
  if (skip) return t.skip(skip);
  const { p } = await open();
  await p.evaluate((cur: string) => (window as any).mdRender(cur), NEW);
  assert.equal(await p.evaluate(() => (document.getElementById("review-bar") as HTMLElement).hidden), true);
  assert.equal(await p.evaluate(() => document.querySelectorAll("#doc .md-change").length), 0);
  await p.evaluate((base: string) => (window as any).mdSetReview({ mode: "compare", baseText: base, title: "r1 (planner)" }), BASE);
  assert.match(await p.evaluate(() => (document.getElementById("review-bar") as HTMLElement).innerText), /5 changes since r1 \(planner\)[\s\S]*Done/);
});

test("screenshot for review", async (t) => {
  if (skip || !process.env.PREVIEW_SHOTS) return t.skip("set PREVIEW_SHOTS=dir to save screenshots");
  for (const scheme of ["light", "dark"] as const) {
    const ctx = await browser.newContext({ bypassCSP: true, viewport: { width: 900, height: 1100 }, colorScheme: scheme });
    const p = await ctx.newPage();
    await p.goto(page);
    await p.evaluate(([base, cur]: string[]) => {
      (window as any).mdRender(cur);
      (window as any).mdSetReview({ mode: "unread", baseText: base, revisions: [{ revision: "r2", source: "observed" }, { revision: "r3", source: "checkpoint", author: "planner", note: "Proposed a row limit" }] });
    }, [BASE, NEW]);
    await p.screenshot({ path: path.join(process.env.PREVIEW_SHOTS, `preview-${scheme}.png`), fullPage: true });
    await p.evaluate(() => (window as any).mdShowHistory([{ revision: "r3", time: "2026-10-16T05:00:00Z", source: "checkpoint", author: "planner", note: "Proposed a row limit" }, { revision: "r2", time: "2026-10-16T04:00:00Z", source: "observed" }, { revision: "r1", time: "2026-10-16T03:00:00Z", source: "checkpoint", author: "vinay", note: "Saved in mdEditDiff" }], "r1"));
    await p.screenshot({ path: path.join(process.env.PREVIEW_SHOTS, `history-${scheme}.png`) });
    await ctx.close();
  }
});

test("find in the rendered document: counts, crosses formatting, not blocks, steps and closes", async (t) => {
  if (skip) return t.skip(skip);
  const { p, errors } = await open();
  await p.evaluate((cur: string) => (window as any).mdRender(cur), NEW + "\nThe **CSV** export ships.\n\nexport\n\nreports\n");
  await p.evaluate(() => (window as any).mdFindOpen());
  await p.fill("#find-input", "csv");
  await p.waitForFunction(() => (window as any).mdFindState().count > 0);
  const s1 = await p.evaluate(() => ({ st: (window as any).mdFindState(), label: document.getElementById("find-count")!.textContent, current: document.querySelectorAll("#doc mark.find-current").length }));
  // "CSV" in the title, step 2, the `csv_export` code, and the bold CSV.
  assert.equal(s1.st.count, 4);
  assert.equal(s1.label, "1 of 4");
  assert.equal(s1.current, 1);

  await p.press("#find-input", "Enter");
  await p.press("#find-input", "Shift+Enter");
  await p.press("#find-input", "Shift+Enter");
  assert.equal(await p.evaluate(() => (window as any).mdFindState().index), 3);

  // Across formatting ("an **Export** button") but never across two blocks ("export" / "reports").
  await p.fill("#find-input", "an export button");
  await p.waitForFunction(() => (window as any).mdFindState().query === "an export button");
  assert.equal(await p.evaluate(() => (window as any).mdFindState().count), 1);
  assert.equal(await p.evaluate(() => document.querySelectorAll("#doc mark.find-hit").length), 3);
  await p.fill("#find-input", "export reports");
  await p.waitForFunction(() => (window as any).mdFindState().query === "export reports");
  assert.equal(await p.evaluate(() => (window as any).mdFindState().count), 1); // only the title

  // Matches survive a re-render (live refresh) and are removed cleanly on close.
  await p.evaluate((cur: string) => (window as any).mdRender(cur + "\nExport reports again.\n"), NEW);
  assert.equal(await p.evaluate(() => (window as any).mdFindState().count), 2);
  await p.keyboard.press("Escape");
  const closed = await p.evaluate(() => ({ marks: document.querySelectorAll("#doc mark").length, open: (window as any).mdFindState().open, h1: document.querySelector("#doc h1")!.innerHTML }));
  assert.equal(closed.marks, 0);
  assert.equal(closed.open, false);
  assert.equal(closed.h1, "Export reports to CSV");

  await p.fill("#find-input", "").catch(() => {});
  await p.evaluate(() => (window as any).mdFindOpen("zzz-not-here"));
  assert.equal(await p.evaluate(() => document.getElementById("find-count")!.textContent), "Not found");
  assert.deepEqual(errors, []);
});

// ------------------------------------------------------------------------------------------------
// Pages

function longDoc(): string {
  const para = (i: number) => `Paragraph ${i}. ` + "The delivery timeline depends on the vendor and on how fast the review goes. ".repeat(4);
  const parts = ["# Launch plan", "", para(0), ""];
  for (let s = 1; s <= 4; s++) {
    parts.push(`## Section ${s}`, "");
    for (let i = 1; i <= 6; i++) parts.push(para(s * 10 + i), "");
  }
  parts.push("## Steps", "");
  for (let i = 1; i <= 60; i++) parts.push(`${i}. Step number ${i} of the rollout`);
  parts.push("", "## Owners", "", "| Area | Owner |", "| --- | --- |");
  for (let i = 1; i <= 80; i++) parts.push(`| Area ${i} | Person ${i} |`);
  parts.push("", "## Script", "", "```");
  for (let i = 1; i <= 120; i++) parts.push(`    line ${i}: run step ${i}`);
  parts.push("```", "", "The end.", "");
  return parts.join("\n");
}

async function openPaged(width = 1200, height = 800) {
  const ctx = await browser.newContext({ bypassCSP: true, viewport: { width, height } });
  const p = await ctx.newPage();
  const errors: string[] = [];
  p.on("pageerror", (e: Error) => errors.push(e.message));
  await p.goto(page);
  await p.evaluate(() => ((window as any).mdTestLog = []));
  return { p, errors };
}


test("pages: content flows onto fixed pages with nothing lost, lists and tables continue", async (t) => {
  if (skip) return t.skip(skip);
  const { p, errors } = await openPaged();
  const md = longDoc();
  await p.evaluate((src: string) => { (window as any).mdSetLayout({ paged: false }); (window as any).mdRender(src); }, md);
  const continuous = await p.evaluate(() => (document.getElementById("doc") as HTMLElement).innerText.replace(/\s+/g, " ").trim());
  await p.evaluate(() => (window as any).mdSetLayout({ paged: true }));
  const r = await p.evaluate(() => {
    const pages = Array.from(document.querySelectorAll("#doc .page")) as HTMLElement[];
    const bodies = pages.map((pg) => pg.querySelector(".page-body") as HTMLElement);
    // Repeated table headers are expected on continuation pages; leave them out of the comparison.
    const text = bodies.map((b) => {
      const c = b.cloneNode(true) as HTMLElement;
      c.querySelectorAll("table.pg-cont > thead").forEach((h) => h.remove());
      document.body.appendChild(c);
      const t = c.innerText;
      c.remove();
      return t;
    }).join(" ").replace(/\s+/g, " ").trim();
    const over = bodies.map((b, i) => {
      const last = b.lastElementChild as HTMLElement;
      return last ? last.getBoundingClientRect().bottom - b.getBoundingClientRect().top : 0;
    }).filter((h) => h > 864.5);
    const heights = new Set(pages.map((pg) => pg.offsetHeight));
    const ols = Array.from(document.querySelectorAll("#doc ol")) as HTMLOListElement[];
    return {
      count: pages.length, text, over, heights: Array.from(heights),
      olStarts: ols.map((o) => o.start) as number[],
      contTables: document.querySelectorAll("#doc table.pg-cont thead").length,
      thumbs: document.querySelectorAll("#thumb-list button.thumb").length,
      current: document.querySelector("#thumb-list .thumb-current")?.getAttribute("aria-label"),
      state: (window as any).mdPagesState(),
      pageOf: document.getElementById("page-of")!.textContent,
    };
  });
  assert.deepEqual(errors, []);
  assert.ok(r.count >= 6, `expected several pages, got ${r.count}`);
  assert.equal(r.text, continuous);
  assert.deepEqual(r.over, []);
  assert.deepEqual(r.heights, [1056]);
  assert.ok(r.olStarts.length >= 2 && r.olStarts[0] === 1 && r.olStarts.slice(1).every((s: number, i: number) => s > r.olStarts[i]), `list numbering continues: ${r.olStarts}`);
  assert.ok(r.contTables >= 1, "continued tables repeat their header");
  assert.equal(r.thumbs, r.count);
  assert.equal(r.current, "Page 1");
  assert.equal(r.pageOf, " of " + r.count);
});

test("pages: thumbnails jump, scrolling moves the selection, Go to Page validates", async (t) => {
  if (skip) return t.skip(skip);
  const { p, errors } = await openPaged();
  await p.evaluate((src: string) => (window as any).mdRender(src), longDoc());
  await p.click('#thumb-list button[aria-label="Page 3"]');
  await p.waitForTimeout(50);
  const at3 = await p.evaluate(() => ({ cur: (window as any).mdPagesState().current, top: Math.round(document.querySelectorAll("#doc .page")[2].getBoundingClientRect().top) }));
  assert.equal(at3.cur, 3);
  assert.ok(at3.top >= 0 && at3.top <= 30, `page 3 at the top (${at3.top})`);

  // Scroll so page 4 holds the middle of the window: the thumbnail selection follows.
  await p.evaluate(() => { const pg = document.querySelectorAll("#doc .page")[3]; window.scrollBy(0, pg.getBoundingClientRect().top - 100); });
  await p.waitForFunction(() => (window as any).mdPagesState().current === 4);
  assert.equal(await p.evaluate(() => document.querySelector("#thumb-list .thumb-current")!.getAttribute("aria-label")), "Page 4");

  await p.evaluate(() => (window as any).mdFocusPageInput());
  await p.keyboard.type("999");
  await p.keyboard.press("Enter");
  assert.equal(await p.evaluate(() => (window as any).mdPagesState().current), 4);
  assert.equal(await p.evaluate(() => document.getElementById("page-input")!.classList.contains("pb-bad")), true);
  await p.waitForTimeout(950);
  await p.evaluate(() => (window as any).mdFocusPageInput());
  await p.keyboard.type("2");
  await p.keyboard.press("Enter");
  assert.equal(await p.evaluate(() => (window as any).mdPagesState().current), 2);

  // Keyboard in the thumbnail list.
  await p.focus('#thumb-list button[aria-label="Page 2"]');
  await p.keyboard.press("ArrowDown");
  assert.equal(await p.evaluate(() => (window as any).mdPagesState().current), 3);
  assert.deepEqual(errors, []);
});

test("pages: zoom keeps the page count; A4 and continuous change the layout; find works across pages", async (t) => {
  if (skip) return t.skip(skip);
  const { p, errors } = await openPaged();
  await p.evaluate((src: string) => (window as any).mdRender(src), longDoc());
  const before = await p.evaluate(() => (window as any).mdPagesState());
  await p.evaluate(() => { (window as any).mdPagesZoom("in"); (window as any).mdPagesZoom("in"); });
  const zoomed = await p.evaluate(() => (window as any).mdPagesState());
  assert.equal(zoomed.count, before.count);
  assert.ok(zoomed.zoom > before.zoom);
  assert.equal(await p.evaluate(() => document.getElementById("page-zoom")!.textContent), Math.round(zoomed.zoom * 100) + "%");
  await p.evaluate(() => (window as any).mdPagesZoom("fitPage"));
  const fit = await p.evaluate(() => (window as any).mdPagesState());
  assert.equal(fit.count, before.count);
  assert.ok(fit.zoom < 1);

  await p.evaluate(() => (window as any).mdSetLayout({ size: "a4", zoomMode: "auto" }));
  const a4 = await p.evaluate(() => ({ st: (window as any).mdPagesState(), w: (document.querySelector("#doc .page") as HTMLElement).offsetWidth }));
  assert.equal(a4.st.size, "a4");
  assert.equal(a4.w, 794);

  await p.evaluate(() => { (window as any).mdFindOpen("delivery timeline"); });
  const pagedHits = await p.evaluate(() => (window as any).mdFindState().count);
  await p.evaluate(() => (window as any).mdSetLayout({ paged: false }));
  const cont = await p.evaluate(() => ({ pages: document.querySelectorAll("#doc .page").length, thumbs: getComputedStyle(document.getElementById("thumbs")!).display, bar: (document.getElementById("page-bar") as HTMLElement).hidden, hits: (window as any).mdFindState().count }));
  assert.equal(cont.pages, 0);
  assert.equal(cont.thumbs, "none");
  assert.equal(cont.bar, true);
  assert.equal(cont.hits, pagedHits);
  assert.ok(pagedHits >= 25);
  const log = await p.evaluate(() => (window as any).mdTestLog.filter((m: any) => m.action === "layout"));
  assert.ok(log.length >= 2, "zoom changes are saved");
  assert.deepEqual(errors, []);
});

test("pages: an edit above keeps the reading position by text", async (t) => {
  if (skip) return t.skip(skip);
  const { p, errors } = await openPaged();
  const md = longDoc();
  await p.evaluate((src: string) => (window as any).mdRender(src), md);
  await p.evaluate(() => (window as any).mdGoToPage(4));
  const anchor = await p.evaluate(() => {
    const els = Array.from(document.querySelectorAll("#doc [data-line]")) as HTMLElement[];
    const e = els.find((x) => x.getBoundingClientRect().top >= 0)!;
    return { text: e.textContent!.trim().slice(0, 40), top: e.getBoundingClientRect().top };
  });
  const inserted = md.replace("# Launch plan\n", "# Launch plan\n\n" + "A new paragraph an agent added at the top. ".repeat(30) + "\n");
  await p.evaluate((src: string) => (window as any).mdRender(src), inserted);
  const after = await p.evaluate((text: string) => {
    const els = Array.from(document.querySelectorAll("#doc [data-line]")) as HTMLElement[];
    const e = els.find((x) => x.textContent!.trim().slice(0, 40) === text)!;
    return e.getBoundingClientRect().top;
  }, anchor.text);
  assert.ok(Math.abs(after - anchor.top) < 3, `stayed in place (${anchor.top} → ${after})`);
  assert.deepEqual(errors, []);
});

test("a heading can't take over the app's own ids, and #links still jump to it", async (t) => {
  if (skip) return t.skip(skip);
  const { p, errors } = await openPaged(1040, 700);
  await p.evaluate(() => (window as any).mdRender("# Doc\n\n[go](#history)\n\n## history\n\nText.\n\n## doc\n"));
  const r = await p.evaluate(() => ({
    panel: document.getElementById("history")!.tagName,
    doc: document.getElementById("doc")!.tagName,
    heading: getComputedStyle(document.querySelector("#doc h2")!).position,
  }));
  assert.deepEqual(r, { panel: "ASIDE", doc: "MAIN", heading: "static" });
  await p.click("#doc a");
  assert.deepEqual(errors, []);
});
