import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createHash } from "node:crypto";
import { changesSince, checkpoint, diffRevisions, history, markSeen, showRevision } from "../src/api.js";
import { Store, UserError } from "../src/store.js";

let dir: string;
let store: Store;
let plan: string;
const sha = (p: string) => createHash("sha256").update(fs.readFileSync(p)).digest("hex");

const PLAN = `# Launch plan

## Steps

1. Draft the announcement.
2. Run the database migration.
3. Ship the release.

## Risks

The migration may take 20 minutes.
`;

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), "mdeditdiff-"));
  store = new Store(path.join(dir, ".store"));
  plan = path.join(dir, "plan.md");
  fs.writeFileSync(plan, PLAN);
});

test("first look returns the full text; then no changes", () => {
  const r1 = changesSince(store, plan, "implementer", { markSeen: true });
  assert.equal(r1.status, "first_look");
  assert.equal((r1 as any).text, PLAN);
  const r2 = changesSince(store, plan, "implementer", { markSeen: true });
  assert.equal(r2.status, "no_changes");
});

test("acceptance: a person edits two steps; the agent gets exactly those two modified blocks", () => {
  changesSince(store, plan, "implementer", { markSeen: true });
  fs.writeFileSync(
    plan,
    PLAN.replace("Draft the announcement.", "Draft the announcement and the FAQ.").replace("Ship the release.", "Ship the release on Tuesday."),
  );
  const r = changesSince(store, plan, "implementer", { markSeen: true });
  assert.equal(r.status, "changed");
  if (r.status !== "changed") return;
  assert.deepEqual(r.summary, { added: 0, removed: 0, modified: 2 });
  assert.deepEqual(
    r.changes.map((c) => [c.old, c.new]),
    [
      ["1. Draft the announcement.", "1. Draft the announcement and the FAQ."],
      ["3. Ship the release.", "3. Ship the release on Tuesday."],
    ],
  );
});

test("acceptance: two readers with different baselines get different, correct answers", () => {
  changesSince(store, plan, "a", { markSeen: true });
  fs.writeFileSync(plan, PLAN + "\nFirst addition.\n");
  changesSince(store, plan, "b", { markSeen: true }); // b first looks after addition 1
  fs.writeFileSync(plan, PLAN + "\nFirst addition.\n\nSecond addition.\n");
  const ra = changesSince(store, plan, "a", { markSeen: true });
  const rb = changesSince(store, plan, "b", { markSeen: true });
  assert.equal(ra.status, "changed");
  assert.equal(rb.status, "changed");
  if (ra.status !== "changed" || rb.status !== "changed") return;
  assert.deepEqual(ra.changes.map((c) => c.new), ["First addition.", "Second addition."]);
  assert.deepEqual(rb.changes.map((c) => c.new), ["Second addition."]);
});

test("peek does not move the baseline", () => {
  changesSince(store, plan, "a", { markSeen: true });
  fs.writeFileSync(plan, PLAN + "\nNew.\n");
  assert.equal(changesSince(store, plan, "a", { markSeen: false }).status, "changed");
  assert.equal(changesSince(store, plan, "a", { markSeen: false }).status, "changed");
  markSeen(store, plan, "a");
  assert.equal(changesSince(store, plan, "a").status, "no_changes");
});

test("acceptance: checkpoints carry author and note, and appear in history and changes", () => {
  changesSince(store, plan, "implementer", { markSeen: true });
  fs.writeFileSync(plan, PLAN.replace("3. Ship the release.", "3. Notify support.\n4. Ship the release."));
  const c = checkpoint(store, plan, "planner", "Added a support step");
  assert.equal(c.status, "recorded");
  const r = changesSince(store, plan, "implementer", { markSeen: true });
  assert.equal(r.status, "changed");
  if (r.status !== "changed") return;
  assert.deepEqual(r.revisions.map((v) => [v.author, v.note]), [["planner", "Added a support step"]]);
  const h = history(store, plan);
  assert.equal(h.revisions[0].author, "planner");
  assert.equal(h.readers.implementer, h.revisions[0].revision);
});

test("checkpoint credits an agent whose edit someone else captured first, but never claims others' edits", () => {
  checkpoint(store, plan, "planner", "v1"); // r1, planner has seen r1
  fs.writeFileSync(plan, PLAN + "\nPlanner's edit.\n");
  changesSince(store, plan, "implementer"); // captures r2 before the planner checks in
  assert.equal(checkpoint(store, plan, "planner", "added a line").status, "claimed");
  assert.equal(history(store, plan).revisions[0].author, "planner");

  // Someone who had not seen r2 cannot claim r3.
  fs.writeFileSync(plan, PLAN + "\nA person's edit.\n");
  changesSince(store, plan, "implementer"); // captures r3, unreported
  const c = checkpoint(store, plan, "bystander");
  assert.equal(c.status, "unchanged");
  assert.match(c.message, /may include changes by others/);
  assert.equal(history(store, plan).revisions[0].author, undefined);
});

test("acceptance: changes made while nothing was running are still detected", () => {
  changesSince(store, plan, "a", { markSeen: true });
  // Simulate an editor saving several times with no tool running.
  for (let i = 0; i < 5; i++) fs.writeFileSync(plan, PLAN + `\nEdit ${i}.\n`);
  const fresh = new Store(store.dir); // a new process
  const r = changesSince(fresh, plan, "a");
  assert.equal(r.status, "changed");
});

test("acceptance: one revision per distinct content; identical content is not duplicated", () => {
  for (let i = 0; i < 10; i++) {
    fs.writeFileSync(plan, PLAN + `\nVersion ${i}.\n`);
    changesSince(store, plan, "watcher", { markSeen: true });
    changesSince(store, plan, "watcher", { markSeen: true });
  }
  assert.equal(history(store, plan).total, 10);
});

test("acceptance: no call ever changes the document's bytes", () => {
  const before = sha(plan);
  changesSince(store, plan, "a", { markSeen: true });
  markSeen(store, plan, "b");
  checkpoint(store, plan, "a", "note");
  history(store, plan);
  diffRevisions(store, plan, "r1");
  showRevision(store, plan, "r1");
  assert.equal(sha(plan), before);
});

test("diff and show work across revisions, including after the file is deleted", () => {
  checkpoint(store, plan, "planner", "v1");
  fs.writeFileSync(plan, PLAN.replace("20 minutes", "an hour"));
  checkpoint(store, plan, "planner", "v2");
  const d = diffRevisions(store, plan, "r1", "r2");
  assert.equal(d.summary.modified, 1);
  fs.rmSync(plan);
  assert.equal(history(store, plan).total, 2);
  assert.equal(showRevision(store, plan, "r1").text, PLAN);
  assert.throws(() => changesSince(store, plan, "a"), /File not found.*history is still available/);
});

test("pruning keeps reader baselines and the latest revision", () => {
  const small = new Store(path.join(dir, ".small"), 3);
  changesSince(small, plan, "slow", { markSeen: true }); // r1 pinned by "slow"
  for (let i = 0; i < 6; i++) {
    fs.writeFileSync(plan, PLAN + `\nV${i}.\n`);
    checkpoint(small, plan, "bot");
  }
  const h = history(small, plan);
  assert.ok(h.total <= 4);
  assert.ok(h.revisions.some((r) => r.revision === "r1"));
  assert.equal(changesSince(small, plan, "slow").status, "changed");
});

test("rejects non-Markdown files, bad names, and non-UTF-8 content", () => {
  const txt = path.join(dir, "secret.env");
  fs.writeFileSync(txt, "KEY=1");
  assert.throws(() => changesSince(store, txt, "a"), UserError);
  assert.throws(() => changesSince(store, plan, "../../etc"), UserError);
  const bad = path.join(dir, "bad.md");
  fs.writeFileSync(bad, Buffer.from([0xff, 0xfe, 0x00, 0xd8]));
  assert.throws(() => changesSince(store, bad, "a"), /not valid UTF-8/);
});

test("watch records each saved version separately, coalescing rapid writes", async () => {
  const { watch } = await import("../src/api.js");
  const seen: string[] = [];
  const w = watch(store, [dir], { debounceMs: 150, onCapture: (_f, r) => seen.push(r.revision) });
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  try {
    await wait(100);
    fs.writeFileSync(plan, PLAN + "\nA person's edit.\n");
    await wait(500);
    for (let i = 0; i < 20; i++) fs.writeFileSync(plan, PLAN + `\nA person's edit.\n\nAgent streaming ${i}.\n`);
    await wait(500);
    // Atomic save: write a temp file and rename it over the original.
    fs.writeFileSync(plan + ".tmp.md", PLAN + "\nAtomic.\n");
    fs.renameSync(plan + ".tmp.md", plan);
    await wait(500);
  } finally {
    w.close();
  }
  const h = history(store, plan);
  assert.equal(h.total, 3, `revisions: ${JSON.stringify(h.revisions.map((r) => r.revision))}`);
});
