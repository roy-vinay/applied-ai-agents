// Local revision store shared by every agent and person on this machine.
//
// Layout under the store directory:
//   blobs/ab/abcdef....gz      file contents, gzip, named by SHA-256 of the raw bytes
//   files/<sha256 of path>.json  one index per document: revisions and reader baselines
//
// Writes to an index are serialized with a lock directory, so several agents can
// call the tool at once.

import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { gunzipSync, gzipSync } from "node:zlib";

export type Source = "observed" | "checkpoint";

export interface Revision {
  id: number;
  hash: string;
  size: number;
  time: string;
  /** "observed": the tool found new content nobody reported. "checkpoint": an agent or person reported it. */
  source: Source;
  author?: string;
  note?: string;
}

export interface FileIndex {
  version: 1;
  path: string;
  revisions: Revision[];
  readers: Record<string, { revision: number; time: string }>;
}

export class UserError extends Error {}

export const MARKDOWN_EXTENSIONS = [".md", ".markdown", ".mdown", ".mkd", ".mkdn", ".mdx"];
export const DEFAULT_MAX_REVISIONS = 500;
const NAME = /^[A-Za-z0-9][A-Za-z0-9 ._@:-]{0,63}$/;

export function defaultStoreDir(): string {
  if (process.env.MDEDITDIFF_HOME) return process.env.MDEDITDIFF_HOME;
  const home = os.homedir();
  if (process.platform === "darwin") return path.join(home, "Library", "Application Support", "mdeditdiff");
  if (process.platform === "win32") return path.join(process.env.APPDATA ?? home, "mdeditdiff");
  return path.join(process.env.XDG_DATA_HOME ?? path.join(home, ".local", "share"), "mdeditdiff");
}

export function checkName(kind: "reader" | "author", value: string): string {
  const v = (value ?? "").trim();
  if (!NAME.test(v)) {
    throw new UserError(`${kind} name must be 1 to 64 characters: letters, numbers, spaces and . _ @ : - (got "${value}")`);
  }
  return v;
}

const sha256 = (data: Buffer | string) => createHash("sha256").update(data).digest("hex");
const sleep = (ms: number) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

export class Store {
  readonly dir: string;
  readonly maxRevisions: number;

  constructor(dir = defaultStoreDir(), maxRevisions = DEFAULT_MAX_REVISIONS) {
    this.dir = dir;
    this.maxRevisions = maxRevisions;
    fs.mkdirSync(path.join(dir, "blobs"), { recursive: true });
    fs.mkdirSync(path.join(dir, "files"), { recursive: true });
  }

  /** Resolve and validate a document path. Only Markdown files are accepted. */
  resolve(file: string): string {
    if (!file) throw new UserError("A file path is required.");
    const abs = path.resolve(file);
    const ext = path.extname(abs).toLowerCase();
    if (!MARKDOWN_EXTENSIONS.includes(ext)) {
      throw new UserError(`Only Markdown files are supported (${MARKDOWN_EXTENSIONS.join(", ")}): ${file}`);
    }
    try {
      return fs.realpathSync(abs);
    } catch {
      return abs; // File may have been deleted; keep the path so history is still reachable.
    }
  }

  private indexPath(abs: string) {
    return path.join(this.dir, "files", sha256(abs) + ".json");
  }

  private blobPath(hash: string) {
    return path.join(this.dir, "blobs", hash.slice(0, 2), hash + ".gz");
  }

  /** Run fn while holding the lock for this document. */
  withLock<T>(abs: string, fn: () => T): T {
    const lock = this.indexPath(abs) + ".lock";
    const deadline = Date.now() + 10_000;
    for (;;) {
      try {
        fs.mkdirSync(lock);
        break;
      } catch (e: any) {
        if (e.code !== "EEXIST") throw e;
        try {
          if (Date.now() - fs.statSync(lock).mtimeMs > 30_000) fs.rmSync(lock, { recursive: true, force: true });
        } catch {}
        if (Date.now() > deadline) throw new UserError(`Timed out waiting for another mdeditdiff call on ${abs}`);
        sleep(15);
      }
    }
    try {
      return fn();
    } finally {
      fs.rmSync(lock, { recursive: true, force: true });
    }
  }

  load(abs: string): FileIndex {
    try {
      return JSON.parse(fs.readFileSync(this.indexPath(abs), "utf8")) as FileIndex;
    } catch (e: any) {
      if (e.code === "ENOENT") return { version: 1, path: abs, revisions: [], readers: {} };
      throw e;
    }
  }

  save(idx: FileIndex) {
    const target = this.indexPath(idx.path);
    const tmp = `${target}.${process.pid}.${Date.now()}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(idx, null, 1));
    fs.renameSync(tmp, target);
  }

  putBlob(data: Buffer): string {
    const hash = sha256(data);
    const p = this.blobPath(hash);
    if (!fs.existsSync(p)) {
      fs.mkdirSync(path.dirname(p), { recursive: true });
      const tmp = `${p}.${process.pid}.tmp`;
      fs.writeFileSync(tmp, gzipSync(data));
      fs.renameSync(tmp, p);
    }
    return hash;
  }

  getText(rev: Revision): string {
    return gunzipSync(fs.readFileSync(this.blobPath(rev.hash))).toString("utf8");
  }

  /**
   * Record the file's current content if it differs from the latest revision.
   * With a checkpoint, an author and note are attached: to a new revision, or to the
   * latest one if it has the same content and nobody has claimed it yet.
   * Returns the latest revision after capture.
   */
  capture(idx: FileIndex, claim?: { author: string; note?: string }): { latest: Revision; created: boolean; claimed: boolean } {
    let data: Buffer;
    try {
      data = fs.readFileSync(idx.path);
    } catch (e: any) {
      if (e.code === "ENOENT") {
        const known = idx.revisions.length ? " Its history is still available with `history` and `show`." : "";
        throw new UserError(`File not found: ${idx.path}.${known}`);
      }
      if (e.code === "EACCES" || e.code === "EPERM") throw new UserError(`No permission to read ${idx.path}`);
      throw e;
    }
    try {
      new TextDecoder("utf-8", { fatal: true }).decode(data);
    } catch {
      throw new UserError(`${idx.path} is not valid UTF-8 text; mdeditdiff only supports UTF-8.`);
    }
    const hash = sha256(data);
    const last = idx.revisions[idx.revisions.length - 1];
    if (last && last.hash === hash) {
      // Only claim an unreported revision if the claimant had seen the version right before it;
      // otherwise it may hold someone else's edits.
      const prev = idx.revisions[idx.revisions.length - 2];
      const sawPrev = claim && prev && idx.readers[claim.author]?.revision === prev.id;
      if (claim && !last.author && sawPrev) {
        last.source = "checkpoint";
        last.author = claim.author;
        if (claim.note) last.note = claim.note;
        return { latest: last, created: false, claimed: true };
      }
      return { latest: last, created: false, claimed: false };
    }
    this.putBlob(data);
    const rev: Revision = {
      id: (last?.id ?? 0) + 1,
      hash,
      size: data.length,
      time: new Date().toISOString(),
      source: claim ? "checkpoint" : "observed",
      ...(claim ? { author: claim.author } : {}),
      ...(claim?.note ? { note: claim.note } : {}),
    };
    idx.revisions.push(rev);
    this.prune(idx);
    return { latest: rev, created: true, claimed: !!claim };
  }

  /** Drop the oldest revisions over the limit, keeping any that a reader uses as its baseline. */
  prune(idx: FileIndex) {
    if (idx.revisions.length <= this.maxRevisions) return;
    const pinned = new Set(Object.values(idx.readers).map((r) => r.revision));
    const latest = idx.revisions[idx.revisions.length - 1].id;
    let excess = idx.revisions.length - this.maxRevisions;
    idx.revisions = idx.revisions.filter((r) => {
      if (excess > 0 && !pinned.has(r.id) && r.id !== latest) {
        excess--;
        return false;
      }
      return true;
    });
  }

  revision(idx: FileIndex, ref: string | number): Revision {
    const s = String(ref).trim().toLowerCase();
    if (s === "latest" || s === "current") {
      const last = idx.revisions[idx.revisions.length - 1];
      if (!last) throw new UserError(`No history yet for ${idx.path}`);
      return last;
    }
    const id = Number(s.replace(/^r/, ""));
    const rev = idx.revisions.find((r) => r.id === id);
    if (!rev) throw new UserError(`No revision ${ref} for ${idx.path}. Use \`history\` to list revisions.`);
    return rev;
  }
}
