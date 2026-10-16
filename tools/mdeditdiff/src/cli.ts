#!/usr/bin/env node
// mdeditdiff command-line tool. Run `mdeditdiff --help` for usage.

import { parseArgs } from "node:util";
import { changesSince, checkpoint, diffRevisions, history, markSeen, showRevision, watch } from "./api.js";
import { renderChanges, renderDiff, renderHistory, renderRevision } from "./format.js";
import { Store, UserError } from "./store.js";
import { VERSION } from "./version.js";

const HELP = `mdeditdiff ${VERSION}: what changed in a Markdown file since you last looked, and who changed it.

Usage:
  mdeditdiff changes <file> --reader <name> [--peek] [--full] [--json]
      Changes since this reader last looked. Marks the current version as seen
      unless --peek is given. The first call for a reader returns the full text.
      --with-base adds the full text of the version you last looked at (JSON only).
  mdeditdiff seen <file> --reader <name>
      Mark the current version as seen without showing changes.
  mdeditdiff checkpoint <file> --author <name> [--note <text>]
      Record the current version with your name and a short note for the next reader.
  mdeditdiff history <file> [--limit <n>]
      List revisions, newest first, and where each reader last looked.
  mdeditdiff diff <file> <from> [<to>]
      Compare two revisions (for example r3 r7, or r3 latest).
  mdeditdiff show <file> <revision>
      Print the full text of a revision.
  mdeditdiff watch <file or folder>...
      Keep running and record a revision each time a Markdown file changes, so
      edits by different people and agents stay separate. Rapid saves are merged.
  mdeditdiff mcp
      Run as an MCP server over standard input and output.

Options:
  --json           Print JSON instead of text (format: docs/FORMAT.md)
  --store <dir>    History location (default: per-user app data folder, or $MDEDITDIFF_HOME)
  -h, --help       Show this help
  -v, --version    Show the version

Environment:
  MDEDITDIFF_READER, MDEDITDIFF_AUTHOR   Defaults for --reader and --author
  MDEDITDIFF_HOME                        History location

mdeditdiff never changes your files. History stays on this computer.`;

function main(argv: string[]): number {
  const { values, positionals } = parseArgs({
    args: argv,
    allowPositionals: true,
    options: {
      reader: { type: "string" },
      author: { type: "string" },
      note: { type: "string" },
      limit: { type: "string" },
      store: { type: "string" },
      peek: { type: "boolean" },
      full: { type: "boolean" },
      "with-base": { type: "boolean" },
      json: { type: "boolean" },
      help: { type: "boolean", short: "h" },
      version: { type: "boolean", short: "v" },
    },
  });
  if (values.version) {
    console.log(VERSION);
    return 0;
  }
  const [cmd, file, ...rest] = positionals;
  if (values.help || !cmd) {
    console.log(HELP);
    return cmd || values.help ? 0 : 1;
  }
  if (cmd === "mcp") {
    // Loaded lazily so the plain CLI starts fast.
    import("./mcp.js").then((m) => m.serve(values.store)).catch((e) => {
      console.error(e);
      process.exit(2);
    });
    return -1;
  }

  const store = new Store(values.store);
  if (cmd === "watch") {
    const targets = [file, ...rest].filter(Boolean);
    if (!targets.length) throw new UserError("Usage: mdeditdiff watch <file or folder>...");
    watch(store, targets, {
      onCapture: (f, r) => console.log(`${r.time}  ${r.revision}  ${f}`),
      onError: (f, e) => console.error(`mdeditdiff: ${f}: ${e.message}`),
    });
    console.error(`Watching ${targets.join(", ")}. Press Ctrl-C to stop.`);
    return -1;
  }
  const out = (data: unknown, text: string) => console.log(values.json ? JSON.stringify(data, null, 2) : text);
  const need = (v: string | undefined, flag: string, env: string) => {
    const x = v ?? process.env[env];
    if (!x) throw new UserError(`${flag} is required (or set ${env}).`);
    return x;
  };

  switch (cmd) {
    case "changes": {
      const r = changesSince(store, file, need(values.reader, "--reader", "MDEDITDIFF_READER"), {
        markSeen: !values.peek,
        full: values.full,
        withBase: values["with-base"],
      });
      out(r, renderChanges(r));
      return 0;
    }
    case "seen": {
      const r = markSeen(store, file, need(values.reader, "--reader", "MDEDITDIFF_READER"));
      out(r, `Marked ${r.seen.revision} as seen for "${r.reader}".`);
      return 0;
    }
    case "checkpoint": {
      const r = checkpoint(store, file, need(values.author, "--author", "MDEDITDIFF_AUTHOR"), values.note);
      out(r, `${r.revision.revision}: ${r.message}`);
      return 0;
    }
    case "history": {
      const r = history(store, file, values.limit ? Number(values.limit) : 50);
      out(r, renderHistory(r));
      return 0;
    }
    case "diff": {
      if (!rest[0]) throw new UserError("Usage: mdeditdiff diff <file> <from> [<to>]");
      const r = diffRevisions(store, file, rest[0], rest[1] ?? "latest");
      out(r, renderDiff(r));
      return 0;
    }
    case "show": {
      if (!rest[0]) throw new UserError("Usage: mdeditdiff show <file> <revision>");
      const r = showRevision(store, file, rest[0]);
      out(r, renderRevision(r));
      return 0;
    }
    default:
      throw new UserError(`Unknown command "${cmd}". Run mdeditdiff --help.`);
  }
}

try {
  const code = main(process.argv.slice(2));
  if (code >= 0) process.exitCode = code;
} catch (e) {
  if (e instanceof UserError || (e as any)?.code === "ERR_PARSE_ARGS_UNKNOWN_OPTION") {
    console.error(`mdeditdiff: ${(e as Error).message}`);
    process.exitCode = 1;
  } else {
    console.error(e);
    process.exitCode = 2;
  }
}
