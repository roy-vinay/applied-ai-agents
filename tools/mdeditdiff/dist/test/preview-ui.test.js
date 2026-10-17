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
let browser = null;
let skip = "";
before(async () => {
    try {
        const { chromium } = await import("playwright");
        browser = await chromium.launch(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {});
    }
    catch (e) {
        skip = `no browser available (${e.message.split("\n")[0]})`;
    }
});
after(async () => browser?.close());
async function open(width = 900) {
    const ctx = await browser.newContext({ bypassCSP: true, viewport: { width, height: 900 } });
    const p = await ctx.newPage();
    const errors = [];
    p.on("pageerror", (e) => errors.push(e.message));
    await p.goto(page);
    await p.evaluate(() => (window.mdTestLog = []));
    return { p, errors };
}
test("highlights added, changed and removed blocks with word-level marks", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await open();
    await p.evaluate(([base, cur]) => {
        window.mdRender(cur);
        window.mdSetReview({ mode: "unread", baseText: base, revisions: [{ revision: "r2", source: "observed" }, { revision: "r3", source: "checkpoint", author: "planner", note: "Proposed a row limit" }] });
    }, [BASE, NEW]);
    const info = await p.evaluate(() => {
        const q = (s) => Array.from(document.querySelectorAll("#doc " + s.split(",").join(", #doc "))).map((e) => e.innerText.trim());
        return {
            bar: document.getElementById("review-bar").innerText,
            added: q(".md-added"),
            modified: q(".md-modified"),
            removed: q(".md-removed .md-removed-body"),
            ins: q("ins.md-ins"),
            del: q("del.md-del"),
            boldKept: !!document.querySelector("#doc li strong"),
            log: window.mdTestLog,
            removedBeforeNext: document.querySelector("#doc .md-removed")?.nextElementSibling?.textContent?.trim(),
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
    if (skip)
        return t.skip(skip);
    const { p, errors } = await open();
    await p.evaluate(([base, cur]) => {
        window.mdRender(cur);
        window.mdSetReview({ mode: "unread", baseText: base, revisions: [] });
    }, [BASE, NEW]);
    await p.click(".md-restore");
    await p.click("text=Mark as read");
    await p.click("text=Next ›");
    await p.click("text=Next ›");
    const current = await p.evaluate(() => document.querySelectorAll("#doc .md-current").length);
    await p.evaluate(() => window.mdShowHistory([
        { revision: "r3", time: "2026-10-16T05:00:00Z", source: "checkpoint", author: "planner", note: "Proposed a row limit" },
        { revision: "r2", time: "2026-10-16T04:00:00Z", source: "observed" },
    ], "r2"));
    await p.click("#history >> text=Compare");
    await p.click("#history >> text=Restore");
    const log = await p.evaluate(() => window.mdTestLog.filter((m) => m.action !== "count"));
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
    if (skip)
        return t.skip(skip);
    const { p } = await open();
    await p.evaluate((cur) => window.mdRender(cur), NEW);
    assert.equal(await p.evaluate(() => document.getElementById("review-bar").hidden), true);
    assert.equal(await p.evaluate(() => document.querySelectorAll("#doc .md-change").length), 0);
    await p.evaluate((base) => window.mdSetReview({ mode: "compare", baseText: base, title: "r1 (planner)" }), BASE);
    assert.match(await p.evaluate(() => document.getElementById("review-bar").innerText), /5 changes since r1 \(planner\)[\s\S]*Done/);
});
test("screenshot for review", async (t) => {
    if (skip || !process.env.PREVIEW_SHOTS)
        return t.skip("set PREVIEW_SHOTS=dir to save screenshots");
    for (const scheme of ["light", "dark"]) {
        const ctx = await browser.newContext({ bypassCSP: true, viewport: { width: 900, height: 1100 }, colorScheme: scheme });
        const p = await ctx.newPage();
        await p.goto(page);
        await p.evaluate(([base, cur]) => {
            window.mdRender(cur);
            window.mdSetReview({ mode: "unread", baseText: base, revisions: [{ revision: "r2", source: "observed" }, { revision: "r3", source: "checkpoint", author: "planner", note: "Proposed a row limit" }] });
        }, [BASE, NEW]);
        await p.screenshot({ path: path.join(process.env.PREVIEW_SHOTS, `preview-${scheme}.png`), fullPage: true });
        await p.evaluate(() => window.mdShowHistory([{ revision: "r3", time: "2026-10-16T05:00:00Z", source: "checkpoint", author: "planner", note: "Proposed a row limit" }, { revision: "r2", time: "2026-10-16T04:00:00Z", source: "observed" }, { revision: "r1", time: "2026-10-16T03:00:00Z", source: "checkpoint", author: "vinay", note: "Saved in mdEditDiff" }], "r1"));
        await p.screenshot({ path: path.join(process.env.PREVIEW_SHOTS, `history-${scheme}.png`) });
        await ctx.close();
    }
});
test("find in the rendered document: counts, crosses formatting, not blocks, steps and closes", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await open();
    await p.evaluate((cur) => window.mdRender(cur), NEW + "\nThe **CSV** export ships.\n\nexport\n\nreports\n");
    await p.evaluate(() => window.mdFindOpen());
    await p.fill("#find-input", "csv");
    await p.waitForFunction(() => window.mdFindState().count > 0);
    const s1 = await p.evaluate(() => ({ st: window.mdFindState(), label: document.getElementById("find-count").textContent, current: document.querySelectorAll("#doc mark.find-current").length }));
    // "CSV" in the title, step 2, the `csv_export` code, and the bold CSV.
    assert.equal(s1.st.count, 4);
    assert.equal(s1.label, "1 of 4");
    assert.equal(s1.current, 1);
    await p.press("#find-input", "Enter");
    await p.press("#find-input", "Shift+Enter");
    await p.press("#find-input", "Shift+Enter");
    assert.equal(await p.evaluate(() => window.mdFindState().index), 3);
    // Across formatting ("an **Export** button") but never across two blocks ("export" / "reports").
    await p.fill("#find-input", "an export button");
    await p.waitForFunction(() => window.mdFindState().query === "an export button");
    assert.equal(await p.evaluate(() => window.mdFindState().count), 1);
    assert.equal(await p.evaluate(() => document.querySelectorAll("#doc mark.find-hit").length), 3);
    await p.fill("#find-input", "export reports");
    await p.waitForFunction(() => window.mdFindState().query === "export reports");
    assert.equal(await p.evaluate(() => window.mdFindState().count), 1); // only the title
    // Matches survive a re-render (live refresh) and are removed cleanly on close.
    await p.evaluate((cur) => window.mdRender(cur + "\nExport reports again.\n"), NEW);
    assert.equal(await p.evaluate(() => window.mdFindState().count), 2);
    await p.keyboard.press("Escape");
    const closed = await p.evaluate(() => ({ marks: document.querySelectorAll("#doc mark").length, open: window.mdFindState().open, h1: document.querySelector("#doc h1").innerHTML }));
    assert.equal(closed.marks, 0);
    assert.equal(closed.open, false);
    assert.equal(closed.h1, "Export reports to CSV");
    await p.fill("#find-input", "").catch(() => { });
    await p.evaluate(() => window.mdFindOpen("zzz-not-here"));
    assert.equal(await p.evaluate(() => document.getElementById("find-count").textContent), "Not found");
    assert.deepEqual(errors, []);
});
// ------------------------------------------------------------------------------------------------
// Pages
function longDoc() {
    const para = (i) => `Paragraph ${i}. ` + "The delivery timeline depends on the vendor and on how fast the review goes. ".repeat(4);
    const parts = ["# Launch plan", "", para(0), ""];
    for (let s = 1; s <= 4; s++) {
        parts.push(`## Section ${s}`, "");
        for (let i = 1; i <= 6; i++)
            parts.push(para(s * 10 + i), "");
    }
    parts.push("## Steps", "");
    for (let i = 1; i <= 60; i++)
        parts.push(`${i}. Step number ${i} of the rollout`);
    parts.push("", "## Owners", "", "| Area | Owner |", "| --- | --- |");
    for (let i = 1; i <= 80; i++)
        parts.push(`| Area ${i} | Person ${i} |`);
    parts.push("", "## Script", "", "```");
    for (let i = 1; i <= 120; i++)
        parts.push(`    line ${i}: run step ${i}`);
    parts.push("```", "", "The end.", "");
    return parts.join("\n");
}
async function openPaged(width = 1200, height = 800) {
    const ctx = await browser.newContext({ bypassCSP: true, viewport: { width, height } });
    const p = await ctx.newPage();
    const errors = [];
    p.on("pageerror", (e) => errors.push(e.message));
    await p.goto(page);
    await p.evaluate(() => (window.mdTestLog = []));
    return { p, errors };
}
test("pages: content flows onto fixed pages with nothing lost, lists and tables continue", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await openPaged();
    const md = longDoc();
    await p.evaluate((src) => { window.mdSetLayout({ paged: false }); window.mdRender(src); }, md);
    const continuous = await p.evaluate(() => document.getElementById("doc").innerText.replace(/\s+/g, " ").trim());
    await p.evaluate(() => window.mdSetLayout({ paged: true }));
    const r = await p.evaluate(() => {
        const pages = Array.from(document.querySelectorAll("#doc .page"));
        const bodies = pages.map((pg) => pg.querySelector(".page-body"));
        // Repeated table headers are expected on continuation pages; leave them out of the comparison.
        const text = bodies.map((b) => {
            const c = b.cloneNode(true);
            c.querySelectorAll("table.pg-cont > thead").forEach((h) => h.remove());
            document.body.appendChild(c);
            const t = c.innerText;
            c.remove();
            return t;
        }).join(" ").replace(/\s+/g, " ").trim();
        const over = bodies.map((b, i) => {
            const last = b.lastElementChild;
            return last ? last.getBoundingClientRect().bottom - b.getBoundingClientRect().top : 0;
        }).filter((h) => h > 864.5);
        const heights = new Set(pages.map((pg) => pg.offsetHeight));
        const ols = Array.from(document.querySelectorAll("#doc ol"));
        return {
            count: pages.length, text, over, heights: Array.from(heights),
            olStarts: ols.map((o) => o.start),
            contTables: document.querySelectorAll("#doc table.pg-cont thead").length,
            thumbs: document.querySelectorAll("#thumb-list button.thumb").length,
            current: document.querySelector("#thumb-list .thumb-current")?.getAttribute("aria-label"),
            state: window.mdPagesState(),
            pageOf: document.getElementById("page-of").textContent,
        };
    });
    assert.deepEqual(errors, []);
    assert.ok(r.count >= 6, `expected several pages, got ${r.count}`);
    assert.equal(r.text, continuous);
    assert.deepEqual(r.over, []);
    assert.deepEqual(r.heights, [1056]);
    assert.ok(r.olStarts.length >= 2 && r.olStarts[0] === 1 && r.olStarts.slice(1).every((s, i) => s > r.olStarts[i]), `list numbering continues: ${r.olStarts}`);
    assert.ok(r.contTables >= 1, "continued tables repeat their header");
    assert.equal(r.thumbs, r.count);
    assert.equal(r.current, "Page 1");
    assert.equal(r.pageOf, " of " + r.count);
});
test("pages: thumbnails jump, scrolling moves the selection, Go to Page validates", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await openPaged();
    await p.evaluate((src) => window.mdRender(src), longDoc());
    await p.click('#thumb-list button[aria-label="Page 3"]');
    await p.waitForTimeout(50);
    const at3 = await p.evaluate(() => ({ cur: window.mdPagesState().current, top: Math.round(document.querySelectorAll("#doc .page")[2].getBoundingClientRect().top) }));
    assert.equal(at3.cur, 3);
    assert.ok(at3.top >= 0 && at3.top <= 30, `page 3 at the top (${at3.top})`);
    // Scroll so page 4 holds the middle of the window: the thumbnail selection follows.
    await p.evaluate(() => { const pg = document.querySelectorAll("#doc .page")[3]; window.scrollBy(0, pg.getBoundingClientRect().top - 100); });
    await p.waitForFunction(() => window.mdPagesState().current === 4);
    assert.equal(await p.evaluate(() => document.querySelector("#thumb-list .thumb-current").getAttribute("aria-label")), "Page 4");
    await p.evaluate(() => window.mdFocusPageInput());
    await p.keyboard.type("999");
    await p.keyboard.press("Enter");
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 4);
    assert.equal(await p.evaluate(() => document.getElementById("page-input").classList.contains("pb-bad")), true);
    await p.waitForTimeout(950);
    await p.evaluate(() => window.mdFocusPageInput());
    await p.keyboard.type("2");
    await p.keyboard.press("Enter");
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 2);
    // Keyboard in the thumbnail list, right after clicking a thumbnail (WebKit doesn't focus on click).
    await p.click('#thumb-list button[aria-label="Page 2"]');
    assert.equal(await p.evaluate(() => document.activeElement.getAttribute("aria-label")), "Page 2");
    await p.keyboard.press("ArrowDown");
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 3);
    await p.keyboard.press("ArrowDown");
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 4);
    await p.keyboard.press("ArrowUp");
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 3);
    assert.equal(await p.evaluate(() => document.activeElement.getAttribute("aria-label")), "Page 3");
    // Still works after the pages are laid out again (an agent edit, say).
    await p.evaluate(() => window.mdRerender());
    await p.keyboard.press("ArrowDown");
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 4);
    assert.deepEqual(errors, []);
});
test("pages: zoom keeps the page count; A4 and continuous change the layout; find works across pages", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await openPaged();
    await p.evaluate((src) => window.mdRender(src), longDoc());
    const before = await p.evaluate(() => window.mdPagesState());
    await p.evaluate(() => { window.mdPagesZoom("in"); window.mdPagesZoom("in"); });
    const zoomed = await p.evaluate(() => window.mdPagesState());
    assert.equal(zoomed.count, before.count);
    assert.ok(zoomed.zoom > before.zoom);
    assert.equal(await p.evaluate(() => document.getElementById("page-zoom").textContent), Math.round(zoomed.zoom * 100) + "%");
    await p.evaluate(() => window.mdPagesZoom("fitPage"));
    const fit = await p.evaluate(() => window.mdPagesState());
    assert.equal(fit.count, before.count);
    assert.ok(fit.zoom < 1);
    await p.evaluate(() => window.mdSetLayout({ size: "a4", zoomMode: "auto" }));
    const a4 = await p.evaluate(() => ({ st: window.mdPagesState(), w: document.querySelector("#doc .page").offsetWidth }));
    assert.equal(a4.st.size, "a4");
    assert.equal(a4.w, 794);
    await p.evaluate(() => { window.mdFindOpen("delivery timeline"); });
    const pagedHits = await p.evaluate(() => window.mdFindState().count);
    await p.evaluate(() => window.mdSetLayout({ paged: false }));
    const cont = await p.evaluate(() => ({ pages: document.querySelectorAll("#doc .page").length, thumbs: getComputedStyle(document.getElementById("thumbs")).display, bar: document.getElementById("page-bar").hidden, hits: window.mdFindState().count }));
    assert.equal(cont.pages, 0);
    assert.equal(cont.thumbs, "none");
    assert.equal(cont.bar, true);
    assert.equal(cont.hits, pagedHits);
    assert.ok(pagedHits >= 25);
    const log = await p.evaluate(() => window.mdTestLog.filter((m) => m.action === "layout"));
    assert.ok(log.length >= 2, "zoom changes are saved");
    assert.deepEqual(errors, []);
});
test("pages: an edit above keeps the reading position by text", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await openPaged();
    const md = longDoc();
    await p.evaluate((src) => window.mdRender(src), md);
    await p.evaluate(() => window.mdGoToPage(4));
    const anchor = await p.evaluate(() => {
        const els = Array.from(document.querySelectorAll("#doc [data-line]"));
        const e = els.find((x) => x.getBoundingClientRect().top >= 0);
        return { text: e.textContent.trim().slice(0, 40), top: e.getBoundingClientRect().top };
    });
    const inserted = md.replace("# Launch plan\n", "# Launch plan\n\n" + "A new paragraph an agent added at the top. ".repeat(30) + "\n");
    await p.evaluate((src) => window.mdRender(src), inserted);
    const after = await p.evaluate((text) => {
        const els = Array.from(document.querySelectorAll("#doc [data-line]"));
        const e = els.find((x) => x.textContent.trim().slice(0, 40) === text);
        return e.getBoundingClientRect().top;
    }, anchor.text);
    assert.ok(Math.abs(after - anchor.top) < 3, `stayed in place (${anchor.top} → ${after})`);
    assert.deepEqual(errors, []);
});
test("a heading can't take over the app's own ids, and #links still jump to it", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await openPaged(1040, 700);
    await p.evaluate(() => window.mdRender("# Doc\n\n[go](#history)\n\n## history\n\nText.\n\n## doc\n"));
    const r = await p.evaluate(() => ({
        panel: document.getElementById("history").tagName,
        doc: document.getElementById("doc").tagName,
        heading: getComputedStyle(document.querySelector("#doc h2")).position,
    }));
    assert.deepEqual(r, { panel: "ASIDE", doc: "MAIN", heading: "static" });
    await p.click("#doc a");
    assert.deepEqual(errors, []);
});
// ------------------------------------------------------------------------------------------------
// Highlights and notes
/** Selects the nth occurrence of `text` in the rendered document. */
async function selectText(p, text, nth = 0) {
    return p.evaluate(([text, nth]) => {
        const doc = document.getElementById("doc");
        const w = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT, {
            acceptNode: (n) => (n.parentElement.closest(".no-find, .anno-card, .page-num") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
        });
        const nodes = [];
        let all = "";
        let n;
        while ((n = w.nextNode())) {
            nodes.push([n, all.length]);
            all += n.data;
        }
        let idx = -1, from = 0;
        for (let k = 0; k <= nth; k++) {
            idx = all.indexOf(text, from);
            from = idx + 1;
        }
        if (idx < 0)
            throw new Error("not found: " + text);
        const pos = (o, end) => {
            for (let i = nodes.length - 1; i >= 0; i--)
                if (end ? nodes[i][1] < o : nodes[i][1] <= o)
                    return [nodes[i][0], o - nodes[i][1]];
            return [nodes[0][0], 0];
        };
        const r = document.createRange();
        const [sn, so] = pos(idx, false);
        const [en, eo] = pos(idx + text.length, true);
        r.setStart(sn, so);
        r.setEnd(en, eo);
        const s = getSelection();
        s.removeAllRanges();
        s.addRange(r);
        return s.toString();
    }, [text, nth]);
}
const marks = (p) => p.evaluate(() => {
    const out = {};
    document.querySelectorAll("#doc mark.anno").forEach((m) => {
        const id = m.dataset.anno;
        out[id] = (out[id] || "") + m.textContent;
    });
    return Object.values(out);
});
const PLAN = `# Launch plan

We need the **delivery timeline** from the vendor before Friday.

## Risks

- Confirm the delivery timeline with legal.
- Ship it.

| Area | Owner |
| --- | --- |
| Delivery | Sam Lee |
`;
test("notes: highlight across formatting and table cells; anchors follow edits; removed text needs reattachment", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await openPaged();
    await p.evaluate((src) => window.mdRender(src), PLAN);
    await selectText(p, "delivery timeline from");
    const a = await p.evaluate(() => window.mdAnnotateSelection("highlight", "green"));
    assert.equal(a.sourceQuote, "delivery timeline** from");
    assert.equal(a.color, "green");
    await selectText(p, "Sam Lee");
    await p.evaluate(() => window.mdAnnotateSelection("note"));
    assert.deepEqual(await marks(p), ["delivery timeline from", "Sam Lee"]);
    assert.equal(await p.evaluate(() => document.querySelectorAll("#doc mark.anno-green").length >= 1), true);
    // An agent inserts a paragraph above: both stay on their text.
    let src = PLAN.replace("# Launch plan\n", "# Launch plan\n\nA new intro from an agent.\n");
    await p.evaluate((s) => window.mdRender(s), src);
    assert.deepEqual(await marks(p), ["delivery timeline from", "Sam Lee"]);
    // Text typed inside the highlight extends it.
    src = src.replace("delivery timeline** from", "delivery timeline** (final) from");
    await p.evaluate((s) => window.mdRender(s), src);
    assert.deepEqual(await marks(p), ["delivery timeline (final) from", "Sam Lee"]);
    // The passage is rewritten: the highlight is kept under Needs Reattachment, not moved to the other
    // "delivery timeline" in the list.
    src = src.replace("We need the **delivery timeline** (final) from the vendor before Friday.", "Vendor dates are still open.");
    await p.evaluate((s) => window.mdRender(s), src);
    assert.deepEqual(await marks(p), ["Sam Lee"]);
    const st = await p.evaluate(() => window.mdAnnotationsState().items.map((x) => [x.quote, x.detached]));
    assert.deepEqual(st, [["delivery timeline from", true], ["Sam Lee", false]]);
    await p.evaluate(() => window.mdShowSidebarTab("notes"));
    assert.match(await p.evaluate(() => document.getElementById("notes-panel").innerText), /Needs Reattachment \(1\)[\s\S]*delivery timeline from/);
    // Reattach it to the list item's text.
    await selectText(p, "delivery timeline with legal");
    await p.click("#notes-panel >> text=Reattach to Selection");
    assert.deepEqual(await marks(p), ["delivery timeline with legal", "Sam Lee"]);
    assert.equal(await p.evaluate(() => window.mdAnnotationsState().items.every((x) => !x.detached)), true);
    assert.deepEqual(errors, []);
});
test("notes: collapse and expand never change the document or pages; Escape collapses to the marker", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await openPaged();
    await p.evaluate((src) => window.mdRender(src), PLAN);
    await selectText(p, "Ship it");
    await p.evaluate(() => window.mdAnnotateSelection("note"));
    await p.keyboard.type("Ask legal first");
    const before = await p.evaluate(() => ({ html: document.querySelector("#doc .page-body").textContent, rev: window.mdPagesState().revision }));
    await p.keyboard.press("Escape");
    const collapsed = await p.evaluate(() => ({
        hidden: document.querySelector("#doc .anno-card").hidden,
        expanded: document.querySelector("#doc .anno-marker").getAttribute("aria-expanded"),
        focus: document.activeElement.className,
        rev: window.mdPagesState().revision,
        note: window.mdAnnotationsState().items[0].note,
    }));
    assert.equal(collapsed.hidden, true);
    assert.equal(collapsed.expanded, "false");
    assert.match(collapsed.focus, /anno-marker/);
    assert.equal(collapsed.rev, before.rev);
    assert.equal(collapsed.note, "Ask legal first");
    await p.click("#doc .anno-marker");
    assert.equal(await p.evaluate(() => document.querySelector("#doc .anno-card").hidden), false);
    assert.equal(await p.evaluate(() => document.querySelector("#doc .page-body").textContent), before.html);
    // The note is saved without touching the Markdown, and its text is never part of Find.
    await p.evaluate(() => window.mdAnnotationsFlushSave());
    const saved = await p.evaluate(() => window.mdTestLog.filter((m) => m.action === "annotations").pop());
    assert.match(saved.json, /Ask legal first/);
    await p.evaluate(() => window.mdFindOpen("legal first"));
    assert.equal(await p.evaluate(() => window.mdFindState().count), 0);
    assert.deepEqual(errors, []);
});
test("notes: saved annotations come back on reopen, and still find their text after an outside edit", async (t) => {
    if (skip)
        return t.skip(skip);
    const one = await openPaged();
    await one.p.evaluate((src) => window.mdRender(src), PLAN);
    await selectText(one.p, "Confirm the delivery timeline");
    await one.p.evaluate(() => window.mdAnnotateSelection("highlight", "pink"));
    const json = await one.p.evaluate(() => window.mdAnnotationsState().json);
    // Reopen the same text.
    const two = await openPaged();
    await two.p.evaluate(([j, src]) => { window.mdSetAnnotations(j); window.mdRender(src); }, [json, PLAN]);
    assert.deepEqual(await marks(two.p), ["Confirm the delivery timeline"]);
    // Reopen after an agent changed the file while the app was closed (no edit history to follow).
    const edited = PLAN.replace("## Risks\n", "## Risks\n\n- New risk: staffing.\n").replace("We need the", "We still need the");
    const three = await openPaged();
    await three.p.evaluate(([j, src]) => { window.mdSetAnnotations(j); window.mdRender(src); }, [json, edited]);
    assert.deepEqual(await marks(three.p), ["Confirm the delivery timeline"]);
    assert.deepEqual([...one.errors, ...two.errors, ...three.errors], []);
});
test("notes: a highlight across a page break stays one annotation; change review doesn't remove highlights", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await openPaged();
    const md = longDoc();
    await p.evaluate((src) => window.mdRender(src), md);
    // Select from the end of a paragraph on one page into its continuation on the next.
    const got = await p.evaluate(() => {
        const cont = document.querySelector("#doc p.pg-cont");
        const line = cont.getAttribute("data-line");
        const first = document.querySelector('#doc p[data-line="' + line + '"]:not(.pg-cont)');
        const ft = first.lastChild, ct = cont.firstChild;
        const r = document.createRange();
        r.setStart(ft, ft.data.length - 12);
        r.setEnd(ct, 8);
        getSelection().removeAllRanges();
        getSelection().addRange(r);
        return r.toString();
    });
    assert.ok(got.length > 12);
    await p.evaluate(() => window.mdAnnotateSelection("highlight", "blue"));
    const r = await p.evaluate(() => ({
        pieces: new Set(Array.from(document.querySelectorAll("#doc mark.anno")).map((m) => m.closest(".page").dataset.page)).size,
        ids: new Set(Array.from(document.querySelectorAll("#doc mark.anno")).map((m) => m.dataset.anno)).size,
    }));
    assert.equal(r.ids, 1);
    assert.equal(r.pieces, 2);
    // Showing changes since the last read, then marking as read, keeps personal highlights.
    await p.evaluate((src) => window.mdSetReview({ mode: "unread", baseText: src.replace("The end.", "The beginning."), revisions: [] }), md);
    assert.equal(await p.evaluate(() => new Set(Array.from(document.querySelectorAll("#doc mark.anno")).map((m) => m.dataset.anno)).size), 1);
    await p.evaluate(() => window.mdSetReview(null));
    assert.equal(await p.evaluate(() => document.querySelectorAll("#doc mark.anno").length >= 2), true);
    assert.deepEqual(errors, []);
});
test("pages: fit the window by default, and two pages side by side like a book", async (t) => {
    if (skip)
        return t.skip(skip);
    const { p, errors } = await openPaged(1400, 900);
    await p.evaluate((src) => window.mdRender(src), longDoc());
    const single = await p.evaluate(() => {
        const r = document.querySelector("#doc .page").getBoundingClientRect();
        return { st: window.mdPagesState(), bottom: r.bottom, h: window.innerHeight };
    });
    assert.equal(single.st.zoomMode, "auto");
    assert.ok(single.bottom <= single.h, "the whole first page is in view");
    await p.evaluate(() => window.mdPagesSpread(true));
    const two = await p.evaluate(() => {
        const pages = Array.from(document.querySelectorAll("#doc .page"));
        const a = pages[0].getBoundingClientRect(), b = pages[1].getBoundingClientRect(), c = pages[2].getBoundingClientRect();
        return {
            sameRow: Math.abs(a.top - b.top) < 1 && b.left > a.right,
            nextRow: c.top > a.bottom - 1 && Math.abs(c.left - a.left) < 1,
            inView: b.right <= window.innerWidth && a.bottom <= window.innerHeight,
            st: window.mdPagesState(),
            current: Array.from(document.querySelectorAll("#thumb-list .thumb-current")).map((e) => e.getAttribute("aria-label")),
        };
    });
    assert.ok(two.sameRow, "pages 1 and 2 side by side");
    assert.ok(two.nextRow, "page 3 starts the next row");
    assert.ok(two.inView, "both pages fit in the window");
    assert.equal(two.st.count, single.st.count, "same pages, just arranged differently");
    assert.deepEqual(two.current, ["Page 1", "Page 2"]);
    await p.evaluate(() => window.mdPageStep(1));
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 3);
    // → and ← turn to the next and previous pair.
    await p.evaluate(() => document.activeElement?.blur());
    await p.keyboard.press("ArrowRight");
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 5);
    await p.keyboard.press("ArrowLeft");
    await p.keyboard.press("ArrowLeft");
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 1);
    await p.evaluate(() => window.mdPagesSpread(false));
    // One page at a time: → moves one page.
    await p.keyboard.press("ArrowRight");
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 2);
    assert.equal(await p.evaluate(() => window.mdPagesState().spread), false);
    const log = await p.evaluate(() => window.mdTestLog.filter((m) => m.action === "layout").map((m) => m.spread));
    assert.deepEqual(log, [true, false]);
    // Typing in the find bar still moves the cursor, not the page.
    await p.evaluate(() => window.mdFindOpen());
    await p.keyboard.type("ab");
    await p.keyboard.press("ArrowLeft");
    assert.equal(await p.evaluate(() => window.mdPagesState().current), 2);
    assert.deepEqual(errors, []);
});
