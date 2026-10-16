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
    const q = (s: string) => Array.from(document.querySelectorAll(s)).map((e) => (e as HTMLElement).innerText.trim());
    return {
      bar: (document.getElementById("review-bar") as HTMLElement).innerText,
      added: q(".md-added"),
      modified: q(".md-modified"),
      removed: q(".md-removed .md-removed-body"),
      ins: q("ins.md-ins"),
      del: q("del.md-del"),
      boldKept: !!document.querySelector("li strong"),
      log: (window as any).mdTestLog,
      removedBeforeNext: (document.querySelector(".md-removed") as HTMLElement)?.nextElementSibling?.textContent?.trim(),
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
  const current = await p.evaluate(() => document.querySelectorAll(".md-current").length);
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
  assert.equal(await p.evaluate(() => document.querySelectorAll(".md-change").length), 0);
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
  const s1 = await p.evaluate(() => ({ st: (window as any).mdFindState(), label: document.getElementById("find-count")!.textContent, current: document.querySelectorAll("mark.find-current").length }));
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
  assert.equal(await p.evaluate(() => document.querySelectorAll("mark.find-hit").length), 3);
  await p.fill("#find-input", "export reports");
  await p.waitForFunction(() => (window as any).mdFindState().query === "export reports");
  assert.equal(await p.evaluate(() => (window as any).mdFindState().count), 1); // only the title

  // Matches survive a re-render (live refresh) and are removed cleanly on close.
  await p.evaluate((cur: string) => (window as any).mdRender(cur + "\nExport reports again.\n"), NEW);
  assert.equal(await p.evaluate(() => (window as any).mdFindState().count), 2);
  await p.keyboard.press("Escape");
  const closed = await p.evaluate(() => ({ marks: document.querySelectorAll("mark").length, open: (window as any).mdFindState().open, h1: document.querySelector("h1")!.innerHTML }));
  assert.equal(closed.marks, 0);
  assert.equal(closed.open, false);
  assert.equal(closed.h1, "Export reports to CSV");

  await p.fill("#find-input", "").catch(() => {});
  await p.evaluate(() => (window as any).mdFindOpen("zzz-not-here"));
  assert.equal(await p.evaluate(() => document.getElementById("find-count")!.textContent), "Not found");
  assert.deepEqual(errors, []);
});
