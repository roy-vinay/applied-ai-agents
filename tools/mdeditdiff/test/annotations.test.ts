// Tests how highlights and notes keep their place in the Markdown source (annotations.js core) in Node.

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const file = path.join(here, "..", "..", "app", "Sources", "MDEditDiffApp", "Resources", "Preview", "annotations.js");
const ctx: Record<string, any> = {};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(file, "utf8"), ctx);
const core = ctx.MDAnnotationsCore;

function ctxAround(src: string, start: number, end: number) {
  return { quote: src.slice(start, end), prefix: src.slice(Math.max(0, start - 32), start), suffix: src.slice(end, end + 32) };
}

test("edit transform: before moves, inside extends, at either edge stays outside, partial delete keeps the rest", () => {
  const T = (a: string, b: string, s: number, e: number) => [...core.transform(s, e, core.diffEdit(a, b))];
  const src = "aaa delivery timeline zzz";
  const s = 4, e = 21; // "delivery timeline"
  assert.deepEqual(T(src, "NEW " + src, s, e), [8, 25]);                                  // insert before
  assert.deepEqual(T(src, "aaa delivery (firm) timeline zzz", s, e), [4, 28]);            // inside: extends
  assert.deepEqual(T(src, "aaa Xdelivery timeline zzz", s, e), [5, 22]);                  // at the start: outside
  assert.deepEqual(T(src, "aaa delivery timelineX zzz", s, e), [4, 21]);                  // at the end: outside
  assert.deepEqual(T(src, "aaa delivery zzz", s, e), [4, 13]);                            // partial delete
  const gone = T(src, "aaa zzz", s, e);
  assert.ok(gone[0] >= gone[1], "fully deleted range is empty");
});

test("locate: rewrapped text still matches; repeated text needs context; never guesses", () => {
  const src = "Intro.\n\nWe need the delivery timeline from the vendor\nbefore Friday.\n\nLater: delivery timeline again.";
  const start = src.indexOf("delivery timeline from");
  const c = ctxAround(src, start, start + "delivery timeline from the vendor before".length);
  // Rewrapped: the line break moved.
  const rewrapped = src.replace("from the vendor\nbefore Friday.", "from\nthe vendor before Friday.");
  const r = core.locate(rewrapped, c.quote, c.prefix, c.suffix);
  assert.ok(r);
  assert.equal(rewrapped.slice(r[0], r[1]).replace(/\s+/g, " "), c.quote.replace(/\s+/g, " "));

  // "delivery timeline" appears twice: with its own context it's found; with none, it isn't guessed.
  const d = src.indexOf("delivery timeline");
  const own = ctxAround(src, d, d + 17);
  const found = core.locate(src, own.quote, own.prefix, own.suffix);
  assert.deepEqual([...found], [d, d + 17]);
  assert.equal(core.locate(src, "delivery timeline", "", ""), null);
  // A short quote that appears once but whose context is gone isn't trusted either.
  assert.equal(core.locate("totally different text with Friday", "Friday", "zzzz", "yyyy"), null);
  // Missing text.
  assert.equal(core.locate(src, "not in the text", own.prefix, own.suffix), null);
});

test("hash identifies the source text", () => {
  assert.equal(core.hash("abc"), core.hash("abc"));
  assert.notEqual(core.hash("abc"), core.hash("abd"));
  assert.match(core.hash(""), /^[0-9a-f]{8}$/);
});
