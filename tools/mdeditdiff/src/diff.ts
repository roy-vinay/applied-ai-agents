// Compare two Markdown texts block by block, then word by word inside changed blocks.

import { Block, BlockKind, collapse, locate, parseBlocks } from "./markdown.js";
import { diffSeq } from "./myers.js";

export type WordPart = { op: "=" | "-" | "+"; text: string };

export interface Change {
  type: "added" | "removed" | "modified";
  kind: BlockKind;
  /** Headings above the block, for example "Plan > Steps". */
  section: string;
  /** 1-based line in the newer version (or the older one for removals). */
  line: number;
  old?: string;
  new?: string;
  /** Word-level parts for modified blocks. */
  words?: WordPart[];
}

export interface DiffResult {
  summary: { added: number; removed: number; modified: number };
  changes: Change[];
}

// Words (keeping numbers like 100,000 or 2.5 whole) and single punctuation marks.
const tokenize = (s: string): string[] => collapse(s).match(/[\p{L}\p{N}_'’-]+(?:[.,:]\p{N}+)*|[^\s\p{L}\p{N}_]/gu) ?? [];

/** Text used for word comparison: list numbers are dropped so renumbering is not a change. */
const body = (b: Block): string => (b.kind === "list-item" ? b.text.replace(/^\s*([-*+]|\d{1,9}[.)])[ \t]+/, "") : b.text);

const CLOSE = /^[.,;:!?)\]}%…]/;
const OPEN = /[(\[{$“‘"]$/;
/** Join tokens back into readable text: no space before closing punctuation or after opening brackets. */
function join(tokens: string[], startAfter = ""): string {
  let out = "";
  let prev = startAfter;
  for (const t of tokens) {
    out += (out === "" && prev === "") || CLOSE.test(t) || OPEN.test(prev) ? t : " " + t;
    prev = t;
  }
  return out;
}

function similarity(a: Block, b: Block): number {
  if (a.kind !== b.kind) return 0;
  const ta = tokenize(body(a));
  const tb = tokenize(body(b));
  if (!ta.length && !tb.length) return 1;
  const count = new Map<string, number>();
  for (const t of ta) count.set(t, (count.get(t) ?? 0) + 1);
  let common = 0;
  for (const t of tb) {
    const c = count.get(t) ?? 0;
    if (c > 0) {
      common++;
      count.set(t, c - 1);
    }
  }
  return (2 * common) / (ta.length + tb.length);
}

export function wordDiff(oldText: string, newText: string): WordPart[] {
  const a = tokenize(oldText);
  const b = tokenize(newText);
  const groups: { op: WordPart["op"]; tokens: string[] }[] = [];
  for (const o of diffSeq(a, b)) {
    const op = o.op === "equal" ? "=" : o.op === "delete" ? "-" : "+";
    const tok = o.op === "insert" ? b[o.b] : a[o.a];
    const last = groups[groups.length - 1];
    if (last && last.op === op) last.tokens.push(tok);
    else groups.push({ op, tokens: [tok] });
  }
  return groups.map((g) => ({ op: g.op, text: join(g.tokens) }));
}

const PAIR_THRESHOLD = 0.5;

export function diffMarkdown(oldText: string, newText: string): DiffResult {
  const A = parseBlocks(oldText);
  const B = parseBlocks(newText);
  const ops = diffSeq(
    A.map((b) => b.key),
    B.map((b) => b.key),
  );

  const changes: Change[] = [];
  let dels: Block[] = [];
  let ins: Block[] = [];

  const flush = () => {
    // Pair removed and added blocks that look like edits of each other, keeping order.
    let start = 0;
    const out: Change[] = [];
    for (const d of dels) {
      let best = -1;
      let bestScore = PAIR_THRESHOLD;
      for (let j = start; j < ins.length; j++) {
        const s = similarity(d, ins[j]);
        if (s >= bestScore) {
          best = j;
          bestScore = s;
          if (s === 1) break;
        }
      }
      if (best < 0) {
        out.push({ type: "removed", kind: d.kind, section: locate(d), line: d.line, old: d.text });
        continue;
      }
      for (let j = start; j < best; j++) out.push(added(ins[j]));
      const n = ins[best];
      const words = wordDiff(body(d), body(n));
      if (words.every((w) => w.op === "=")) {
        // Same words, different formatting (for example rewrapped or renumbered): not a change.
      } else {
        out.push({ type: "modified", kind: n.kind, section: locate(n), line: n.line, old: d.text, new: n.text, words });
      }
      start = best + 1;
    }
    for (let j = start; j < ins.length; j++) out.push(added(ins[j]));
    changes.push(...out);
    dels = [];
    ins = [];
  };
  const added = (b: Block): Change => ({ type: "added", kind: b.kind, section: locate(b), line: b.line, new: b.text });

  for (const o of ops) {
    if (o.op === "equal") flush();
    else if (o.op === "delete") dels.push(A[o.a]);
    else ins.push(B[o.b]);
  }
  flush();

  const summary = { added: 0, removed: 0, modified: 0 };
  for (const c of changes) summary[c.type]++;
  return { summary, changes };
}

/** Inline word diff in the compact [-old-]{+new+} style. */
export function inlineWords(words: WordPart[]): string {
  let out = "";
  let prevText = "";
  for (const w of words) {
    const shown = w.op === "=" ? w.text : w.op === "-" ? `[-${w.text}-]` : `{+${w.text}+}`;
    out += out === "" || CLOSE.test(w.text) || OPEN.test(prevText) ? shown : " " + shown;
    prevText = w.text;
  }
  return out;
}
