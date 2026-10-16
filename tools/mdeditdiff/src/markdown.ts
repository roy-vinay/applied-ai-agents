// Split Markdown into blocks that a person would think of as one unit:
// a heading, a paragraph, one list item, one table row, a code block, a quote.
// Each block gets a comparison key that ignores line wrapping (and list numbering),
// so rewrapping a paragraph or renumbering a list does not count as a change.

export type BlockKind =
  | "heading"
  | "paragraph"
  | "list-item"
  | "table-row"
  | "code"
  | "quote"
  | "rule"
  | "front-matter";

export interface Block {
  kind: BlockKind;
  /** Original text of the block, lines joined with "\n". */
  text: string;
  /** Comparison key: whitespace-insensitive where Markdown is. */
  key: string;
  /** 1-based line where the block starts. */
  line: number;
  /** Headings above this block, outermost first. */
  section: string[];
}

const FENCE = /^ {0,3}(`{3,}|~{3,})/;
const ATX = /^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*#*[ \t]*$/;
const RULE = /^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$/;
const SETEXT = /^ {0,3}(=+|-+)[ \t]*$/;
const LIST = /^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+|$)(.*)$/;
const QUOTE = /^ {0,3}>/;
const TABLE_DELIM = /^[ \t]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$/;

export const collapse = (s: string): string => s.replace(/\s+/g, " ").trim();

function headingText(raw: string): string {
  return collapse(raw.replace(/[ \t]*#+[ \t]*$/, ""));
}

function tableKey(line: string): string {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((c) => collapse(c))
    .join(" | ");
}

function isBlockStart(line: string): boolean {
  return FENCE.test(line) || ATX.test(line) || QUOTE.test(line) || LIST.test(line) || RULE.test(line);
}

export function parseBlocks(source: string): Block[] {
  const lines = source.split(/\r\n|\n|\r/);
  const blocks: Block[] = [];
  const headings: { level: number; text: string }[] = [];
  const section = () => headings.map((h) => h.text);
  const push = (kind: BlockKind, start: number, end: number, key: string) => {
    blocks.push({ kind, text: lines.slice(start, end).join("\n"), key: `${kind}:${key}`, line: start + 1, section: section() });
  };
  const setHeading = (level: number, text: string) => {
    while (headings.length && headings[headings.length - 1].level >= level) headings.pop();
    headings.push({ level, text });
  };

  let i = 0;
  // YAML front matter at the very top.
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
      let j = i + 1;
      const closeRe = new RegExp(`^ {0,3}${marker[0] === "`" ? "`" : "~"}{${marker.length},}[ \\t]*$`);
      while (j < lines.length && !closeRe.test(lines[j])) j++;
      const end = Math.min(j + 1, lines.length);
      push("code", i, end, lines.slice(i, end).join("\n"));
      i = end;
      continue;
    }

    const atx = line.match(ATX);
    if (atx) {
      const text = headingText(atx[2] ?? "");
      setHeading(atx[1].length, text);
      // A heading's own section is its parents, not itself.
      const self = headings.pop()!;
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
      let j = i;
      while (j < lines.length && lines[j].trim() !== "" && (QUOTE.test(lines[j]) || !isBlockStart(lines[j]))) j++;
      const key = collapse(lines.slice(i, j).map((l) => l.replace(/^ {0,3}>[ \t]?/, "")).join(" "));
      push("quote", i, j, key);
      i = j;
      continue;
    }

    const item = line.match(LIST);
    if (item) {
      const indent = item[1].replace(/\t/g, "    ").length;
      let j = i + 1;
      while (j < lines.length && lines[j].trim() !== "") {
        const next = lines[j];
        if (LIST.test(next) || FENCE.test(next) || ATX.test(next) || QUOTE.test(next)) break;
        j++;
      }
      const ordered = /\d/.test(item[2]);
      // Numbers are dropped from the key so renumbering a list is not a change.
      const marker = ordered ? "1." : "-";
      const body = collapse([item[4], ...lines.slice(i + 1, j)].join(" "));
      push("list-item", i, j, `${Math.floor(indent / 2)}:${marker}:${body}`);
      i = j;
      continue;
    }

    // Table: a row with pipes followed by a delimiter row.
    if (line.includes("|") && i + 1 < lines.length && TABLE_DELIM.test(lines[i + 1]) && lines[i + 1].includes("-")) {
      push("table-row", i, i + 2, tableKey(line));
      let j = i + 2;
      while (j < lines.length && lines[j].trim() !== "" && lines[j].includes("|")) {
        push("table-row", j, j + 1, tableKey(lines[j]));
        j++;
      }
      i = j;
      continue;
    }

    // Paragraph (possibly a setext heading).
    let j = i + 1;
    let setext: number | null = null;
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
      const self = headings.pop()!;
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

/** A short human label for where a block sits, for example "Steps > Rollout". */
export function locate(b: Block): string {
  return b.section.length ? b.section.join(" > ") : "(top)";
}
