// Compact plain-text rendering of results, for agents reading tool output and people in a terminal.
import * as path from "node:path";
import { inlineWords } from "./diff.js";
const who = (r) => r.source === "checkpoint" && r.author ? `${r.author}${r.note ? `: "${r.note}"` : ""}` : "changed outside, not reported";
const indent = (s, pad = "    ") => s.split("\n").map((l) => pad + l).join("\n");
export function renderChange(c) {
    const where = `${c.section} (${c.kind}, line ${c.line})`;
    if (c.type === "added")
        return `+ added    ${where}\n${indent(c.new)}`;
    if (c.type === "removed")
        return `- removed  ${c.section} (${c.kind}, was line ${c.line})\n${indent(c.old)}`;
    return `~ modified ${where}\n${indent(inlineWords(c.words))}`;
}
export function renderChanges(r) {
    const name = path.basename(r.file);
    const seen = r.marked_seen ? " Marked as seen." : "";
    if (r.status === "first_look") {
        return `${name}: first look for reader "${r.reader}". Full text of ${r.to.revision} follows.${seen}\n\n${r.text}`;
    }
    if (r.status === "no_changes") {
        return `${name}: no changes for "${r.reader}" since ${r.since.revision}.${seen}`;
    }
    const s = r.summary;
    const counts = [s.modified && `${s.modified} modified`, s.added && `${s.added} added`, s.removed && `${s.removed} removed`]
        .filter(Boolean)
        .join(", ");
    const lines = [
        `${name}: ${r.changes.length} change${r.changes.length === 1 ? "" : "s"} (${counts}) since ${r.since.revision}, your last look, up to ${r.to.revision}.${seen}`,
        `By: ${r.revisions.map((v) => `${v.revision} ${who(v)}`).join("; ")}`,
        "Word changes are shown as [-removed-] {+added+}.",
        "",
        ...r.changes.map(renderChange),
    ];
    if (r.text !== undefined)
        lines.push("", "Full current text:", "", r.text);
    return lines.join("\n");
}
export function renderDiff(r) {
    const head = `${path.basename(r.file)}: ${r.changes.length} change${r.changes.length === 1 ? "" : "s"} from ${r.from.revision} to ${r.to.revision}.`;
    if (!r.changes.length)
        return head;
    return [head, `By: ${r.revisions.map((v) => `${v.revision} ${who(v)}`).join("; ")}`, "", ...r.changes.map(renderChange)].join("\n");
}
export function renderHistory(r) {
    const lines = [`${path.basename(r.file)}: ${r.total} revision${r.total === 1 ? "" : "s"}, newest first.`];
    for (const v of r.revisions)
        lines.push(`${v.revision}  ${v.time}  ${who(v)}`);
    const readers = Object.entries(r.readers);
    if (readers.length)
        lines.push("", "Last looked: " + readers.map(([k, v]) => `${k} at ${v}`).join(", "));
    return lines.join("\n");
}
export function renderRevision(r) {
    return `${path.basename(r.file)} ${r.revision.revision} (${r.revision.time}, ${who(r.revision)}):\n\n${r.text}`;
}
