# mdeditdiff response format, version 1

Every command accepts `--json`, and every MCP tool accepts `json: true`. This page describes that JSON so
other tools can read it, or implement the same answers themselves. Every response has a `format` field;
it is `1` for this version. Fields may be added in a later version; existing fields will not change meaning
within version 1.

## Revision

A revision is one recorded version of a file.

```json
{ "revision": "r3", "time": "2026-10-16T05:01:44.482Z", "source": "checkpoint", "author": "planner", "note": "Proposed a row limit" }
```

| Field | Meaning |
| --- | --- |
| `revision` | `r` plus a number that increases by one per recorded version of this file. |
| `time` | When the version was recorded (UTC, ISO 8601). |
| `source` | `checkpoint`: someone reported this version with their name. `observed`: mdeditdiff found new content that nobody reported. |
| `author`, `note` | Present for checkpoints. Self-reported and not verified. |

## `changes` / `changes_since`

`status` is one of three values.

**`first_look`**: this reader has never looked at this file (or its last-looked version was pruned).

```json
{ "format": 1, "status": "first_look", "file": "/abs/plan.md", "reader": "implementer",
  "to": { "revision": "r1", ... }, "text": "# Export to CSV\n...", "marked_seen": true }
```

**`no_changes`**: nothing a reader would notice changed since `since`. Bytes may still differ, for example
when a paragraph was only rewrapped.

```json
{ "format": 1, "status": "no_changes", "file": "...", "reader": "...", "since": {...}, "to": {...}, "marked_seen": true }
```

**`changed`**:

```json
{
  "format": 1,
  "status": "changed",
  "file": "/abs/plan.md",
  "reader": "implementer",
  "since": { "revision": "r1", ... },
  "to": { "revision": "r3", ... },
  "revisions": [
    { "revision": "r2", "source": "observed", ... },
    { "revision": "r3", "source": "checkpoint", "author": "planner", "note": "Proposed a row limit", ... }
  ],
  "marked_seen": true,
  "summary": { "added": 1, "removed": 1, "modified": 2 },
  "changes": [
    {
      "type": "modified",
      "kind": "list-item",
      "section": "Export to CSV > Steps",
      "line": 6,
      "old": "2. Build the CSV on the server.",
      "new": "2. Build the CSV on the server, streaming rows.",
      "words": [
        { "op": "=", "text": "Build the CSV on the server" },
        { "op": "+", "text": ", streaming rows" },
        { "op": "=", "text": "." }
      ]
    }
  ],
  "text": "only present when full text was requested",
  "base_text": "only present with --with-base: the full text of the reader's last-looked version"
}
```

`revisions` lists every version recorded after `since`, up to and including `to`, oldest first. It says who
reported changes in that range. It does not say which revision produced which change.

## Change

| Field | Meaning |
| --- | --- |
| `type` | `added`, `removed`, or `modified`. |
| `kind` | `heading`, `paragraph`, `list-item`, `table-row`, `code`, `quote`, `rule`, or `front-matter`. |
| `section` | The headings above the block, outermost first, joined with ` > `. `(top)` if none. |
| `line` | 1-based line where the block starts: in the newer version, or in the older version for `removed`. |
| `at_line` | For `removed` only: 1-based line, in the newer version, of the block that now follows the removed one, so it can be shown or restored in place. Absent when it was at the end. |
| `old`, `new` | The block's full text before and after. `added` has only `new`; `removed` has only `old`. |
| `words` | For `modified` only: the block's words in order, each run marked `=` (unchanged), `-` (removed) or `+` (added). List markers and numbers are left out. |

### How blocks are compared

1. Each version is split into blocks: one heading, paragraph, list item, table row, code block, quote,
   rule, or front matter each.
2. Blocks are compared by a key that ignores line wrapping, line endings, and list numbering, so
   rewrapping a paragraph or renumbering a list is not a change. Code blocks and front matter are compared
   exactly.
3. Blocks are aligned with a shortest-edit diff. Within each run of removed and added blocks, a removed
   block is paired with an added block of the same kind when at least half their words match; a pair is
   reported as `modified`, anything else as `removed` or `added`.
4. Moved blocks are reported as a removal and an addition.

## `history`

```json
{ "format": 1, "file": "...", "total": 3, "revisions": [ newest first ], "readers": { "implementer": "r3" } }
```

## `diff`

Same `summary` and `changes` as above, plus `from`, `to`, and `revisions` between them.

## `show` / `get_revision`

```json
{ "format": 1, "file": "...", "revision": { ... }, "text": "full text of that revision" }
```

## `checkpoint`

```json
{ "format": 1, "file": "...", "status": "recorded", "revision": { ... }, "message": "..." }
```

`status` is `recorded` (a new revision with your name), `claimed` (your edit had already been captured
without a name, right after a version you had seen, so it now carries your name), or `unchanged` (nothing
new to record, or the unlabeled version may include other people's edits and was left unlabeled).
