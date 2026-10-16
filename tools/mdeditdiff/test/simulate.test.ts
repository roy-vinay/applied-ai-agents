// End-to-end: two agents and a person share plan.md through the real CLI and MCP server.

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const CLI = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "src", "cli.js");

function setup() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mdeditdiff-sim-"));
  const env = { ...process.env, MDEDITDIFF_HOME: path.join(dir, ".store") };
  const run = (...args: string[]) => execFileSync(process.execPath, [CLI, ...args], { cwd: dir, env, encoding: "utf8" });
  return { dir, env, run, plan: path.join(dir, "plan.md") };
}

const PLAN_V1 = `# Feature: export to CSV

## Steps

1. Add an Export button to the report page.
2. Build the CSV on the server.
3. Write tests for empty reports.
4. Ship behind a feature flag.

## Open questions

- Should exports include archived rows?
- What is the row limit?

## Notes

${"Background paragraph with context the implementer already read. ".repeat(40)}
`;

test("two agents and a person: the implementer learns exactly what changed, in far less text than a re-read", () => {
  const { run, plan } = setup();

  // Planner writes the plan and records it.
  fs.writeFileSync(plan, PLAN_V1);
  run("checkpoint", "plan.md", "--author", "planner", "--note", "First plan");

  // Implementer reads it for the first time.
  const first = JSON.parse(run("changes", "plan.md", "--reader", "implementer", "--json"));
  assert.equal(first.status, "first_look");

  // A person answers a question and tightens a step, without telling anyone.
  fs.writeFileSync(
    plan,
    PLAN_V1.replace("- Should exports include archived rows?\n", "")
      .replace("2. Build the CSV on the server.", "2. Build the CSV on the server, streaming rows.")
      .replace("## Notes", "Decision: archived rows are excluded.\n\n## Notes"),
  );

  // Planner looks before editing (the recommended protocol), which records the person's edit separately.
  run("changes", "plan.md", "--reader", "planner");
  // Planner revises again and checks in.
  fs.writeFileSync(plan, fs.readFileSync(plan, "utf8").replace("- What is the row limit?", "- What is the row limit? (planner: propose 100k)"));
  run("checkpoint", "plan.md", "--author", "planner", "--note", "Proposed a row limit");

  const text = run("changes", "plan.md", "--reader", "implementer");
  const json = JSON.parse(run("changes", "plan.md", "--reader", "implementer2", "--json", "--peek"));
  assert.equal(json.status, "first_look"); // a new reader always starts from the full text

  assert.match(text, /4 changes \(2 modified, 1 added, 1 removed\) since r1, your last look, up to r3/);
  assert.match(text, /By: r2 changed outside, not reported; r3 planner: "Proposed a row limit"/);
  assert.match(text, /changed outside, not reported/); // the person's edit
  assert.match(text, /planner: "Proposed a row limit"/);
  assert.match(text, /server\{\+, streaming rows\+\}\./);
  assert.match(text, /Should exports include archived rows\?/);
  assert.ok(!text.includes("Background paragraph"), "unchanged sections are not repeated");
  const current = fs.readFileSync(plan, "utf8");
  assert.ok(text.length < current.length * 0.6, `change answer ${text.length} chars vs full file ${current.length}`);

  // Nothing new afterwards.
  assert.match(run("changes", "plan.md", "--reader", "implementer"), /no changes/);
});

test("concurrent agents do not lose revisions or corrupt history", async () => {
  const { env, dir, plan, run } = setup();
  fs.writeFileSync(plan, "# Log\n");
  const N = 12;
  // Each process appends a line then checkpoints, all at once.
  await Promise.all(
    Array.from({ length: N }, (_, i) =>
      new Promise<void>((resolve, reject) => {
        fs.appendFileSync(plan, `\nEntry ${i}.\n`);
        const p = spawn(process.execPath, [CLI, "checkpoint", "plan.md", "--author", `agent-${i}`], { cwd: dir, env });
        p.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`exit ${code}`))));
      }),
    ),
  );
  const h = JSON.parse(run("history", "plan.md", "--json", "--limit", "500"));
  assert.ok(h.total >= 1 && h.total <= N);
  const ids = h.revisions.map((r: any) => r.revision);
  assert.equal(new Set(ids).size, ids.length);
  // The final content is captured exactly once more at most.
  const last = JSON.parse(run("show", "plan.md", "latest", "--json"));
  assert.equal(last.text, fs.readFileSync(plan, "utf8"));
});

test("CLI reports clear errors with exit code 1", () => {
  const { run } = setup();
  assert.throws(() => run("changes", "missing.md", "--reader", "a"), (e: any) => e.status === 1 && /File not found/.test(e.stderr));
  assert.throws(() => run("changes", "notes.txt", "--reader", "a"), (e: any) => e.status === 1 && /Only Markdown/.test(e.stderr));
  assert.throws(() => run("changes", "x.md"), (e: any) => e.status === 1 && /--reader is required/.test(e.stderr));
});

test("MCP server: lists the tools and answers changes_since over stdio", async () => {
  const { dir, env, plan } = setup();
  fs.writeFileSync(plan, "# Plan\n\n- one\n");
  const client = new Client({ name: "test", version: "0" });
  await client.connect(
    new StdioClientTransport({ command: process.execPath, args: [CLI, "mcp"], cwd: dir, env: env as Record<string, string> }),
  );
  try {
    const tools = (await client.listTools()).tools.map((t) => t.name).sort();
    assert.deepEqual(tools, ["changes_since", "checkpoint", "diff", "get_revision", "history", "mark_seen"]);
    const call = async (name: string, args: Record<string, unknown>) => {
      const r: any = await client.callTool({ name, arguments: args });
      return { text: r.content[0].text as string, isError: !!r.isError };
    };
    assert.match((await call("changes_since", { path: plan, reader: "agent" })).text, /first look/);
    fs.writeFileSync(plan, "# Plan\n\n- one\n- two\n");
    assert.match((await call("checkpoint", { path: plan, author: "other", note: "added two" })).text, /Recorded/);
    const ch = await call("changes_since", { path: plan, reader: "agent" });
    assert.match(ch.text, /1 change .*\n.*other: "added two"/);
    assert.match(ch.text, /- two/);
    const bad = await call("changes_since", { path: path.join(dir, "x.txt"), reader: "agent" });
    assert.ok(bad.isError);
  } finally {
    await client.close();
  }
});
