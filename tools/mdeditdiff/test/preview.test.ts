// Tests the Mac app's preview renderer (app/Sources/MDEditDiffApp/Resources/Preview/preview.js) in Node.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const previewDir = path.join(here, "..", "..", "app", "Sources", "MDEditDiffApp", "Resources", "Preview");

function loadRenderer(): (src: string) => string {
  const ctx: Record<string, unknown> = {};
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(previewDir, "markdown-it.min.js"), "utf8"), ctx);
  vm.runInContext(fs.readFileSync(path.join(previewDir, "preview.js"), "utf8"), ctx);
  return ctx.mdRenderHTML as (src: string) => string;
}

const render = loadRenderer();

const REFERENCE = `# Title

A paragraph with **bold**, *italic*, ~~struck~~, \`code\`, and a [link](https://example.com).

> A quote.

1. First
2. Second
   - Nested
   - Items

- [ ] Open task
- [x] Done task

\`\`\`swift
let x = 1
\`\`\`

---

| Fee | Amount |
| --- | ---: |
| Bag | $30 |

![Diagram](images/diagram.png)

## Title
`;

test("preview renders every supported construct", () => {
  const html = render(REFERENCE);
  for (const needle of [
    '<h1 id="title">Title</h1>',
    '<h2 id="title-1">Title</h2>',
    "<strong>bold</strong>",
    "<em>italic</em>",
    "<s>struck</s>",
    "<code>code</code>",
    '<a href="https://example.com">link</a>',
    "<blockquote>",
    "<ol>",
    "<li>Nested</li>",
    '<li class="task-list-item"><input type="checkbox" disabled aria-label="Not done"> Open task</li>',
    '<input type="checkbox" disabled checked aria-label="Done"> Done task',
    '<pre><code class="language-swift">let x = 1',
    "<hr>",
    '<div class="table-wrap"><table>',
    '<th style="text-align:right">Amount</th>',
    '<img src="images/diagram.png" alt="Diagram">',
  ]) {
    assert.ok(html.includes(needle), `missing ${needle}\n${html}`);
  }
});

test("preview never renders raw HTML or script links from a document", () => {
  const html = render('<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n\n[x](javascript:alert(1)) [y](vbscript:x) [z](data:text/html,hi)\n');
  assert.ok(!html.includes("<script>"));
  assert.ok(!html.includes("<img src=x"));
  assert.ok(html.includes("&lt;script&gt;"));
  assert.ok(!/href="(javascript|vbscript|data):/i.test(html));
});

test("preview.html loads only local scripts and blocks remote content", () => {
  const page = fs.readFileSync(path.join(previewDir, "preview.html"), "utf8");
  assert.match(page, /default-src 'none'/);
  assert.match(page, /img-src mdeditdiff-res: data:/);
  assert.ok(!/https?:\/\//.test(page.replace(/<meta[^>]*>/g, "")));
});
