import { test } from "node:test";
import assert from "node:assert/strict";
import { parseBlocks } from "../src/markdown.js";
import { diffMarkdown } from "../src/diff.js";
import { diffSeq } from "../src/myers.js";
test("myers: edit script rebuilds the target and is minimal on random input", () => {
    let seed = 7;
    const rnd = () => (seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31;
    for (let t = 0; t < 300; t++) {
        const a = Array.from({ length: Math.floor(rnd() * 30) }, () => "abcde"[Math.floor(rnd() * 5)]);
        const b = Array.from({ length: Math.floor(rnd() * 30) }, () => "abcde"[Math.floor(rnd() * 5)]);
        const ops = diffSeq(a, b);
        const rebuilt = ops.filter((o) => o.op !== "delete").map((o) => (o.op === "equal" ? a[o.a] : b[o.b]));
        const kept = ops.filter((o) => o.op !== "insert").map((o) => a[o.a]);
        assert.deepEqual(rebuilt, b);
        assert.deepEqual(kept, a);
        // Equal count must be the LCS length.
        const dp = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0));
        for (let i = a.length - 1; i >= 0; i--)
            for (let j = b.length - 1; j >= 0; j--)
                dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
        assert.equal(ops.filter((o) => o.op === "equal").length, dp[0][0]);
    }
});
test("blocks: headings, list items, table rows, code, quotes, front matter", () => {
    const md = [
        "---",
        "title: x",
        "---",
        "# Title",
        "",
        "Intro line one",
        "line two.",
        "",
        "Sub",
        "---",
        "",
        "- one",
        "- two",
        "  continued",
        "  1. nested",
        "",
        "| a | b |",
        "|---|---|",
        "| 1 | 2 |",
        "",
        "```js",
        "",
        "code();",
        "```",
        "> quoted",
        "> more",
        "",
        "***",
    ].join("\n");
    const kinds = parseBlocks(md).map((b) => b.kind);
    assert.deepEqual(kinds, [
        "front-matter",
        "heading",
        "paragraph",
        "heading",
        "list-item",
        "list-item",
        "list-item",
        "table-row",
        "table-row",
        "code",
        "quote",
        "rule",
    ]);
    const blocks = parseBlocks(md);
    assert.deepEqual(blocks[4].section, ["Title", "Sub"]);
    assert.equal(blocks[2].line, 6);
});
test("diff: rewrapping, renumbering and line endings are not changes", () => {
    const a = "# T\n\n1. alpha\n2. beta\n\nSome words here\nand there.\n";
    const b = "# T\r\n\r\n1. zero\r\n2. alpha\r\n3. beta\r\n\r\nSome words\r\nhere and there.\r\n";
    const r = diffMarkdown(a, b);
    assert.deepEqual(r.summary, { added: 1, removed: 0, modified: 0 });
    assert.equal(r.changes[0].new, "1. zero");
});
test("diff: modified, added and removed blocks with sections and word parts", () => {
    const a = "# Plan\n\n## Steps\n\n- Run the migration.\n- Ship it.\n\n## Risks\n\nIt may be slow.\n";
    const b = "# Plan\n\n## Steps\n\n- Run the migration at night.\n- Tell support.\n- Ship it.\n\n## Risks\n";
    const r = diffMarkdown(a, b);
    assert.deepEqual(r.summary, { added: 1, removed: 1, modified: 1 });
    const mod = r.changes.find((c) => c.type === "modified");
    assert.equal(mod.section, "Plan > Steps");
    assert.deepEqual(mod.words.filter((w) => w.op !== "="), [{ op: "+", text: "at night" }]);
    const rem = r.changes.find((c) => c.type === "removed");
    assert.equal(rem.section, "Plan > Risks");
    assert.equal(rem.old, "It may be slow.");
});
test("diff: table cell edit is one modified row; code change is one modified block", () => {
    const a = "| k | v |\n|---|---|\n| fee | $30 |\n| bags | 2 |\n\n```\nx = 1\n```\n";
    const b = "| k | v |\n| --- | --- |\n| fee | $35 |\n| bags | 2 |\n\n```\nx = 2\n```\n";
    const r = diffMarkdown(a, b);
    assert.deepEqual(r.summary, { added: 0, removed: 0, modified: 2 });
    assert.deepEqual(r.changes.map((c) => c.kind), ["table-row", "code"]);
});
test("diff: unrelated replacement is removed plus added, not modified", () => {
    const r = diffMarkdown("Completely different sentence about cats.\n", "Quarterly revenue grew in Europe.\n");
    assert.deepEqual(r.summary, { added: 1, removed: 1, modified: 0 });
});
test("diff: a 1 MB document with a few edits is fast", () => {
    const paras = Array.from({ length: 8000 }, (_, i) => `Paragraph ${i} has some ordinary words in it for testing size and speed.`);
    const a = paras.join("\n\n");
    const b2 = [...paras];
    b2[10] = "Paragraph 10 was rewritten entirely by an agent.";
    b2.splice(4000, 1);
    b2.push("A new closing paragraph.");
    const t = Date.now();
    const r = diffMarkdown(a, b2.join("\n\n"));
    const ms = Date.now() - t;
    assert.ok(a.length > 500_000);
    assert.equal(r.changes.length, 4); // rewrite = removed + added, plus one removal and one addition
    assert.ok(ms < 2000, `took ${ms} ms`);
});
test("diff: numbers stay whole and punctuation joins naturally", () => {
    const r = diffMarkdown("The limit is 50,000 rows.\n", "The limit is 100,000 rows, for now.\n");
    assert.deepEqual(r.changes[0].words.filter((w) => w.op !== "="), [
        { op: "-", text: "50,000" },
        { op: "+", text: "100,000" },
        { op: "+", text: ", for now" },
    ]);
});
test("diff: removed blocks say where they would go in the newer version", () => {
    const a = "# T\n\nKeep one.\n\nGone.\n\nKeep two.\n\nAlso gone.\n";
    const b = "# T\n\nKeep one.\n\nKeep two.\n";
    const r = diffMarkdown(a, b);
    const removed = r.changes.filter((c) => c.type === "removed");
    assert.deepEqual(removed.map((c) => [c.old, c.at_line]), [
        ["Gone.", 5],
        ["Also gone.", undefined],
    ]);
    // A removal followed by an insertion is placed before the inserted block.
    const r2 = diffMarkdown("A.\n\nOld unrelated words here.\n\nZ.\n", "A.\n\nBrand new sentence entirely.\n\nZ.\n");
    assert.equal(r2.changes.find((c) => c.type === "removed").at_line, 3);
});
