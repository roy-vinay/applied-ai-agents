// Generated from tools/mdeditdiff/src/diff.ts by 'npm run bundle'. Do not edit.
"use strict";
var MDDiff = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // src/diff.ts
  var diff_exports = {};
  __export(diff_exports, {
    diffMarkdown: () => diffMarkdown,
    diffSeq: () => diffSeq,
    inlineWords: () => inlineWords,
    parseBlocks: () => parseBlocks,
    tokenize: () => tokenize,
    wordDiff: () => wordDiff
  });

  // src/markdown.ts
  var FENCE = /^ {0,3}(`{3,}|~{3,})/;
  var ATX = /^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*#*[ \t]*$/;
  var RULE = /^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$/;
  var SETEXT = /^ {0,3}(=+|-+)[ \t]*$/;
  var LIST = /^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+|$)(.*)$/;
  var QUOTE = /^ {0,3}>/;
  var TABLE_DELIM = /^[ \t]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$/;
  var collapse = (s) => s.replace(/\s+/g, " ").trim();
  function headingText(raw) {
    return collapse(raw.replace(/[ \t]*#+[ \t]*$/, ""));
  }
  function tableKey(line) {
    return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => collapse(c)).join(" | ");
  }
  function isBlockStart(line) {
    return FENCE.test(line) || ATX.test(line) || QUOTE.test(line) || LIST.test(line) || RULE.test(line);
  }
  function parseBlocks(source) {
    const lines = source.split(/\r\n|\n|\r/);
    const blocks = [];
    const headings = [];
    const section = () => headings.map((h) => h.text);
    const push = (kind, start, end, key) => {
      blocks.push({ kind, text: lines.slice(start, end).join("\n"), key: `${kind}:${key}`, line: start + 1, section: section() });
    };
    const setHeading = (level, text) => {
      while (headings.length && headings[headings.length - 1].level >= level) headings.pop();
      headings.push({ level, text });
    };
    let i = 0;
    if (lines[0] === "---") {
      const close = lines.findIndex((l, k) => k > 0 && (l === "---" || l === "..."));
      if (close > 0) {
        push("front-matter", 0, close + 1, lines.slice(0, close + 1).join("\n"));
        i = close + 1;
      }
    }
    while (i < lines.length) {
      const line = lines[i];
      if (line.trim() === "") {
        i++;
        continue;
      }
      const fence = line.match(FENCE);
      if (fence) {
        const marker = fence[1];
        let j2 = i + 1;
        const closeRe = new RegExp(`^ {0,3}${marker[0] === "`" ? "`" : "~"}{${marker.length},}[ \\t]*$`);
        while (j2 < lines.length && !closeRe.test(lines[j2])) j2++;
        const end = Math.min(j2 + 1, lines.length);
        push("code", i, end, lines.slice(i, end).join("\n"));
        i = end;
        continue;
      }
      const atx = line.match(ATX);
      if (atx) {
        const text = headingText(atx[2] ?? "");
        setHeading(atx[1].length, text);
        const self = headings.pop();
        push("heading", i, i + 1, `${atx[1].length}:${text}`);
        headings.push(self);
        i++;
        continue;
      }
      if (RULE.test(line)) {
        push("rule", i, i + 1, "---");
        i++;
        continue;
      }
      if (QUOTE.test(line)) {
        let j2 = i;
        while (j2 < lines.length && lines[j2].trim() !== "" && (QUOTE.test(lines[j2]) || !isBlockStart(lines[j2]))) j2++;
        const key = collapse(lines.slice(i, j2).map((l) => l.replace(/^ {0,3}>[ \t]?/, "")).join(" "));
        push("quote", i, j2, key);
        i = j2;
        continue;
      }
      const item = line.match(LIST);
      if (item) {
        const indent = item[1].replace(/\t/g, "    ").length;
        let j2 = i + 1;
        while (j2 < lines.length && lines[j2].trim() !== "") {
          const next = lines[j2];
          if (LIST.test(next) || FENCE.test(next) || ATX.test(next) || QUOTE.test(next)) break;
          j2++;
        }
        const ordered = /\d/.test(item[2]);
        const marker = ordered ? "1." : "-";
        const body2 = collapse([item[4], ...lines.slice(i + 1, j2)].join(" "));
        push("list-item", i, j2, `${Math.floor(indent / 2)}:${marker}:${body2}`);
        i = j2;
        continue;
      }
      if (line.includes("|") && i + 1 < lines.length && TABLE_DELIM.test(lines[i + 1]) && lines[i + 1].includes("-")) {
        push("table-row", i, i + 2, tableKey(line));
        let j2 = i + 2;
        while (j2 < lines.length && lines[j2].trim() !== "" && lines[j2].includes("|")) {
          push("table-row", j2, j2 + 1, tableKey(lines[j2]));
          j2++;
        }
        i = j2;
        continue;
      }
      let j = i + 1;
      let setext = null;
      while (j < lines.length && lines[j].trim() !== "") {
        const m = lines[j].match(SETEXT);
        if (m) {
          setext = m[1][0] === "=" ? 1 : 2;
          break;
        }
        if (isBlockStart(lines[j])) break;
        j++;
      }
      if (setext !== null) {
        const text = collapse(lines.slice(i, j).join(" "));
        setHeading(setext, text);
        const self = headings.pop();
        push("heading", i, j + 1, `${setext}:${text}`);
        headings.push(self);
        i = j + 1;
        continue;
      }
      push("paragraph", i, j, collapse(lines.slice(i, j).join(" ")));
      i = j;
    }
    return blocks;
  }
  function locate(b) {
    return b.section.length ? b.section.join(" > ") : "(top)";
  }

  // src/myers.ts
  var MAX_D = 4e3;
  function diffSeq(a, b) {
    let pre = 0;
    while (pre < a.length && pre < b.length && a[pre] === b[pre]) pre++;
    let suf = 0;
    while (suf < a.length - pre && suf < b.length - pre && a[a.length - 1 - suf] === b[b.length - 1 - suf]) suf++;
    const out = [];
    for (let k = 0; k < pre; k++) out.push({ op: "equal", a: k, b: k });
    const midA = a.slice(pre, a.length - suf);
    const midB = b.slice(pre, b.length - suf);
    for (const o of middle(midA, midB)) out.push({ op: o.op, a: o.a + pre, b: o.b + pre });
    for (let k = suf; k > 0; k--) out.push({ op: "equal", a: a.length - k, b: b.length - k });
    return out;
  }
  function middle(a, b) {
    const n = a.length;
    const m = b.length;
    if (n === 0) return b.map((_, j) => ({ op: "insert", a: 0, b: j }));
    if (m === 0) return a.map((_, i) => ({ op: "delete", a: i, b: 0 }));
    const max = n + m;
    const offset = max;
    let v = new Int32Array(2 * max + 2);
    const trace = [];
    let found = -1;
    for (let d = 0; d <= Math.min(max, MAX_D); d++) {
      trace.push(v.slice());
      for (let k = -d; k <= d; k += 2) {
        let x2;
        if (k === -d || k !== d && v[offset + k - 1] < v[offset + k + 1]) x2 = v[offset + k + 1];
        else x2 = v[offset + k - 1] + 1;
        let y2 = x2 - k;
        while (x2 < n && y2 < m && a[x2] === b[y2]) {
          x2++;
          y2++;
        }
        v[offset + k] = x2;
        if (x2 >= n && y2 >= m) {
          found = d;
          break;
        }
      }
      if (found >= 0) {
        trace.push(v.slice());
        break;
      }
    }
    if (found < 0) {
      return [
        ...a.map((_, i) => ({ op: "delete", a: i, b: 0 })),
        ...b.map((_, j) => ({ op: "insert", a: n, b: j }))
      ];
    }
    const ops = [];
    let x = n;
    let y = m;
    for (let d = found; d >= 0; d--) {
      const vd = trace[d];
      const k = x - y;
      let prevK;
      if (d === 0) prevK = 0;
      else if (k === -d || k !== d && vd[offset + k - 1] < vd[offset + k + 1]) prevK = k + 1;
      else prevK = k - 1;
      const prevX = d === 0 ? 0 : vd[offset + prevK];
      const prevY = prevX - prevK;
      while (x > prevX && y > prevY) {
        x--;
        y--;
        ops.push({ op: "equal", a: x, b: y });
      }
      if (d > 0) {
        if (x === prevX) {
          y--;
          ops.push({ op: "insert", a: x, b: y });
        } else {
          x--;
          ops.push({ op: "delete", a: x, b: y });
        }
      }
    }
    return ops.reverse();
  }

  // src/diff.ts
  var tokenize = (s) => collapse(s).match(/[\p{L}\p{N}_'’-]+(?:[.,:]\p{N}+)*|[^\s\p{L}\p{N}_]/gu) ?? [];
  var body = (b) => b.kind === "list-item" ? b.text.replace(/^\s*([-*+]|\d{1,9}[.)])[ \t]+/, "") : b.text;
  var CLOSE = /^[.,;:!?)\]}%…]/;
  var OPEN = /[(\[{$“‘"]$/;
  function join(tokens, startAfter = "") {
    let out = "";
    let prev = startAfter;
    for (const t of tokens) {
      out += out === "" && prev === "" || CLOSE.test(t) || OPEN.test(prev) ? t : " " + t;
      prev = t;
    }
    return out;
  }
  function similarity(a, b) {
    if (a.kind !== b.kind) return 0;
    const ta = tokenize(body(a));
    const tb = tokenize(body(b));
    if (!ta.length && !tb.length) return 1;
    const count = /* @__PURE__ */ new Map();
    for (const t of ta) count.set(t, (count.get(t) ?? 0) + 1);
    let common = 0;
    for (const t of tb) {
      const c = count.get(t) ?? 0;
      if (c > 0) {
        common++;
        count.set(t, c - 1);
      }
    }
    return 2 * common / (ta.length + tb.length);
  }
  function wordDiff(oldText, newText) {
    const a = tokenize(oldText);
    const b = tokenize(newText);
    const groups = [];
    for (const o of diffSeq(a, b)) {
      const op = o.op === "equal" ? "=" : o.op === "delete" ? "-" : "+";
      const tok = o.op === "insert" ? b[o.b] : a[o.a];
      const last = groups[groups.length - 1];
      if (last && last.op === op) last.tokens.push(tok);
      else groups.push({ op, tokens: [tok] });
    }
    return groups.map((g) => ({ op: g.op, text: join(g.tokens) }));
  }
  var PAIR_THRESHOLD = 0.5;
  function diffMarkdown(oldText, newText) {
    const A = parseBlocks(oldText);
    const B = parseBlocks(newText);
    const ops = diffSeq(
      A.map((b) => b.key),
      B.map((b) => b.key)
    );
    const changes = [];
    let dels = [];
    let ins = [];
    const flush = (nextLine) => {
      let start = 0;
      const out = [];
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
          const at = ins[start]?.line ?? nextLine;
          out.push({ type: "removed", kind: d.kind, section: locate(d), line: d.line, old: d.text, ...at ? { at_line: at } : {} });
          continue;
        }
        for (let j = start; j < best; j++) out.push(added(ins[j]));
        const n = ins[best];
        const words = wordDiff(body(d), body(n));
        if (words.every((w) => w.op === "=")) {
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
    const added = (b) => ({ type: "added", kind: b.kind, section: locate(b), line: b.line, new: b.text });
    for (const o of ops) {
      if (o.op === "equal") flush(B[o.b].line);
      else if (o.op === "delete") dels.push(A[o.a]);
      else ins.push(B[o.b]);
    }
    flush();
    const summary = { added: 0, removed: 0, modified: 0 };
    for (const c of changes) summary[c.type]++;
    return { summary, changes };
  }
  function inlineWords(words) {
    let out = "";
    let prevText = "";
    for (const w of words) {
      const shown = w.op === "=" ? w.text : w.op === "-" ? `[-${w.text}-]` : `{+${w.text}+}`;
      out += out === "" || CLOSE.test(w.text) || OPEN.test(prevText) ? shown : " " + shown;
      prevText = w.text;
    }
    return out;
  }
  return __toCommonJS(diff_exports);
})();
