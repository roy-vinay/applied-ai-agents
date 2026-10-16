// The operations agents and people call. The CLI and MCP server are thin wrappers
// around these. Every result is a plain JSON-safe object (see docs/FORMAT.md).

import { diffMarkdown, Change, DiffResult } from "./diff.js";
import * as fs from "node:fs";
import * as path from "node:path";
import { checkName, FileIndex, MARKDOWN_EXTENSIONS, Revision, Store, UserError } from "./store.js";

export const FORMAT_VERSION = 1;

export interface RevisionInfo {
  revision: string;
  time: string;
  source: "observed" | "checkpoint";
  author?: string;
  note?: string;
}

const info = (r: Revision): RevisionInfo => ({
  revision: `r${r.id}`,
  time: r.time,
  source: r.source,
  ...(r.author ? { author: r.author } : {}),
  ...(r.note ? { note: r.note } : {}),
});

export type ChangesResult =
  | { format: number; status: "first_look"; file: string; reader: string; to: RevisionInfo; text: string; marked_seen: boolean }
  | { format: number; status: "no_changes"; file: string; reader: string; since: RevisionInfo; to: RevisionInfo; marked_seen: boolean; base_text?: string }
  | ({
      format: number;
      status: "changed";
      file: string;
      reader: string;
      since: RevisionInfo;
      to: RevisionInfo;
      /** Revisions after the reader's baseline, oldest first, with who reported them. */
      revisions: RevisionInfo[];
      marked_seen: boolean;
      text?: string;
      /** Full text of the reader's last-looked revision, when requested (for example by the Mac app). */
      base_text?: string;
    } & DiffResult);

export function changesSince(
  store: Store,
  file: string,
  reader: string,
  opts: { markSeen?: boolean; full?: boolean; withBase?: boolean } = {},
): ChangesResult {
  const who = checkName("reader", reader);
  const abs = store.resolve(file);
  return store.withLock(abs, () => {
    const idx = store.load(abs);
    const { latest } = store.capture(idx);
    const base = idx.readers[who];
    const baseRev = base ? idx.revisions.find((r) => r.id === base.revision) : undefined;
    const mark = () => {
      if (opts.markSeen) idx.readers[who] = { revision: latest.id, time: new Date().toISOString() };
    };

    if (!baseRev) {
      mark();
      store.save(idx);
      return {
        format: FORMAT_VERSION,
        status: "first_look",
        file: abs,
        reader: who,
        to: info(latest),
        text: store.getText(latest),
        marked_seen: !!opts.markSeen,
      };
    }
    if (baseRev.id === latest.id) {
      mark();
      store.save(idx);
      return {
        format: FORMAT_VERSION, status: "no_changes", file: abs, reader: who, since: info(baseRev), to: info(latest), marked_seen: !!opts.markSeen,
        ...(opts.withBase ? { base_text: store.getText(baseRev) } : {}),
      };
    }
    const result = diffMarkdown(store.getText(baseRev), store.getText(latest));
    const between = idx.revisions.filter((r) => r.id > baseRev.id && r.id <= latest.id).map(info);
    mark();
    store.save(idx);
    if (result.changes.length === 0) {
      // Bytes changed but nothing a reader would notice (for example rewrapped text).
      return {
        format: FORMAT_VERSION, status: "no_changes", file: abs, reader: who, since: info(baseRev), to: info(latest), marked_seen: !!opts.markSeen,
        ...(opts.withBase ? { base_text: store.getText(baseRev) } : {}),
      };
    }
    return {
      format: FORMAT_VERSION,
      status: "changed",
      file: abs,
      reader: who,
      since: info(baseRev),
      to: info(latest),
      revisions: between,
      marked_seen: !!opts.markSeen,
      ...result,
      ...(opts.full ? { text: store.getText(latest) } : {}),
      ...(opts.withBase ? { base_text: store.getText(baseRev) } : {}),
    };
  });
}

export function markSeen(store: Store, file: string, reader: string) {
  const who = checkName("reader", reader);
  const abs = store.resolve(file);
  return store.withLock(abs, () => {
    const idx = store.load(abs);
    const { latest } = store.capture(idx);
    idx.readers[who] = { revision: latest.id, time: new Date().toISOString() };
    store.save(idx);
    return { format: FORMAT_VERSION, file: abs, reader: who, seen: info(latest) };
  });
}

export function checkpoint(store: Store, file: string, author: string, note?: string) {
  const who = checkName("author", author);
  const n = note?.trim();
  if (n && n.length > 500) throw new UserError("Note must be 500 characters or fewer.");
  const abs = store.resolve(file);
  return store.withLock(abs, () => {
    const idx = store.load(abs);
    const r = store.capture(idx, { author: who, ...(n ? { note: n } : {}) });
    // The author has seen what they just recorded.
    idx.readers[who] = { revision: r.latest.id, time: new Date().toISOString() };
    store.save(idx);
    const status = r.created ? "recorded" : r.claimed ? "claimed" : "unchanged";
    return {
      format: FORMAT_VERSION,
      file: abs,
      status,
      revision: info(r.latest),
      message:
        status === "recorded"
          ? "Recorded a new revision with your name."
          : status === "claimed"
            ? "The current content was already captured without an author; it is now labeled with your name."
            : r.latest.author
              ? `Nothing new to record; the current content is already r${r.latest.id} by ${r.latest.author}.`
              : `The current content was already captured as r${r.latest.id} without an author, and may include changes by others, so it was not labeled with your name. To be credited, call changes_since before you edit and checkpoint right after.`,
    };
  });
}

export function history(store: Store, file: string, limit = 50) {
  const abs = store.resolve(file);
  return store.withLock(abs, () => {
    const idx = store.load(abs);
    try {
      store.capture(idx);
      store.save(idx);
    } catch (e) {
      if (!(e instanceof UserError) || !idx.revisions.length) throw e;
      // File deleted or unreadable: still show what we have.
    }
    const revs = idx.revisions.slice(-Math.max(1, limit)).reverse().map(info);
    const readers = Object.fromEntries(Object.entries(idx.readers).map(([k, v]) => [k, `r${v.revision}`]));
    return { format: FORMAT_VERSION, file: abs, total: idx.revisions.length, revisions: revs, readers };
  });
}

export function diffRevisions(store: Store, file: string, from: string, to = "latest") {
  const abs = store.resolve(file);
  return store.withLock(abs, () => {
    const idx: FileIndex = store.load(abs);
    try {
      store.capture(idx);
      store.save(idx);
    } catch (e) {
      if (!(e instanceof UserError) || !idx.revisions.length) throw e;
    }
    const a = store.revision(idx, from);
    const b = store.revision(idx, to);
    const result = diffMarkdown(store.getText(a), store.getText(b));
    const between = idx.revisions.filter((r) => r.id > Math.min(a.id, b.id) && r.id <= Math.max(a.id, b.id)).map(info);
    return { format: FORMAT_VERSION, file: abs, from: info(a), to: info(b), revisions: between, ...result };
  });
}

export function showRevision(store: Store, file: string, ref: string) {
  const abs = store.resolve(file);
  return store.withLock(abs, () => {
    const idx = store.load(abs);
    const rev = store.revision(idx, ref);
    return { format: FORMAT_VERSION, file: abs, revision: info(rev), text: store.getText(rev) };
  });
}

export type { Change };

/**
 * Watch files or folders and record a revision whenever a Markdown file changes,
 * so edits by different people and agents land in separate revisions even when
 * nobody calls the tool in between. Rapid writes are coalesced.
 */
export function watch(
  store: Store,
  targets: string[],
  opts: { debounceMs?: number; onCapture?: (file: string, rev: RevisionInfo) => void; onError?: (file: string, e: Error) => void } = {},
): { close: () => void } {
  const debounce = opts.debounceMs ?? 1500;
  const timers = new Map<string, NodeJS.Timeout>();
  const watchers: fs.FSWatcher[] = [];
  const isMd = (f: string) => MARKDOWN_EXTENSIONS.includes(path.extname(f).toLowerCase());
  const skip = /(^|[\\/])(node_modules|\.git)([\\/]|$)/;

  const capture = (file: string) => {
    try {
      if (!fs.existsSync(file)) return;
      const abs = store.resolve(file);
      store.withLock(abs, () => {
        const idx = store.load(abs);
        const r = store.capture(idx);
        if (r.created) {
          store.save(idx);
          opts.onCapture?.(abs, info(r.latest));
        }
      });
    } catch (e) {
      opts.onError?.(file, e as Error);
    }
  };
  const schedule = (file: string) => {
    if (!isMd(file) || skip.test(file)) return;
    clearTimeout(timers.get(file));
    timers.set(file, setTimeout(() => (timers.delete(file), capture(file)), debounce));
  };

  for (const t of targets) {
    const abs = path.resolve(t);
    const stat = fs.statSync(abs);
    if (stat.isDirectory()) {
      watchers.push(fs.watch(abs, { recursive: true }, (_e, name) => name && schedule(path.join(abs, name.toString()))));
    } else {
      if (!isMd(abs)) throw new UserError(`Only Markdown files can be watched: ${t}`);
      // Watch the folder, not the file, so atomic saves (write new file, rename over old) keep working.
      const base = path.basename(abs);
      watchers.push(fs.watch(path.dirname(abs), (_e, name) => name?.toString() === base && schedule(abs)));
      capture(abs);
    }
  }
  return {
    close: () => {
      watchers.forEach((w) => w.close());
      timers.forEach((t) => clearTimeout(t));
    },
  };
}
