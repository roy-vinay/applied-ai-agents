# Highlights and notes: storage format

mdEditDiff keeps personal highlights and notes on your Mac, outside the Markdown file. Nothing is
written into the document: no HTML comments, no custom markers, no files beside it. Agents using the
command-line tool or MCP server never see them, and adding or editing a note never creates a
revision, an unread change, or a new baseline.

## Where they live

One JSON file per Markdown file:

```
~/Library/Application Support/mdEditDiff/Annotations/<sha256>.json
```

`<sha256>` is the SHA-256 (hex) of the Markdown file's absolute path after resolving symlinks. Files are
written atomically. Clearing or pruning revision history doesn't touch them.

- **Moved or renamed in Finder** while open: the annotations move with the file.
- **Save As:** they stay with the original, and the app asks whether to copy them to the new file.
- **Copying the Markdown file** (for example, sending it to someone) does not carry annotations.

## Format (version 1)

```json
{
  "format": "mdeditdiff-annotations",
  "version": 1,
  "sourceHash": "1b2c3d4e",
  "items": [
    {
      "id": "9f0c2a1b7d3e4f56",
      "start": 120,
      "end": 137,
      "quote": "delivery timeline",
      "sourceQuote": "delivery timeline",
      "prefix": "We need the **",
      "suffix": "** from the vendor before Fri",
      "section": "Launch plan",
      "lastLine": 3,
      "color": "yellow",
      "note": "Confirm this with the customer.",
      "collapsed": true,
      "detached": false,
      "created": "2026-10-16T15:30:12.509Z",
      "updated": "2026-10-16T15:31:40.002Z"
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `sourceHash` | FNV-1a 32-bit hash (8 hex digits) over the UTF-16 code units of the source text the offsets refer to. |
| `start`, `end` | The anchored range in the Markdown source, as offsets in **UTF-16 code units** (the unit of JavaScript strings and `NSString`). `end` is exclusive. |
| `quote` | The text as it reads in the formatted document, whitespace collapsed. Shown in the Notes list. |
| `sourceQuote` | The exact source text from `start` to `end`, Markdown syntax included. |
| `prefix`, `suffix` | Up to 32 source characters before and after, used to tell repeated passages apart. |
| `section`, `lastLine` | The nearest heading and the 1-based line where the range starts. For display, and for "was near line N" when detached. |
| `color` | `yellow`, `green`, `blue`, `pink`, `purple`, or `null` for a note without a highlight. |
| `note` | Plain text, or `null` for a highlight without a note. Notes are never rendered as Markdown or HTML. |
| `collapsed` | Whether the note card is closed. View state only. |
| `detached` | `true` when the text can't be found without guessing ("Needs Reattachment"). `start`/`end` then keep their last values. |

## How anchors follow the text

When the source changes, each annotation is placed again, in this order:

1. **Follow the edit.** The change is reduced to one replacement (common prefix and suffix). Text inserted
   before the passage moves it; text inserted strictly inside extends it; text inserted exactly at either edge
   stays outside. If the result is the same text as before, the anchor is kept.
2. **Find the exact quote.** The source quote is searched for with whitespace differences ignored (so
   rewrapped paragraphs still match). One occurrence is accepted if the quote is at least 12 characters or
   its surrounding text matches. With several occurrences, the one whose surrounding text matches clearly
   best is chosen; if context doesn't decide, nothing is chosen. Nearness alone is never used.
3. **Keep what survived.** If the edit only touched part of the passage (a small edit, up to 400
   characters), the surviving text stays highlighted.
4. Otherwise the annotation is marked `detached` and listed under **Needs Reattachment**, with its original
   quote. Select the right text and choose **Reattach to Selection**, or delete it.

Mapping the formatted text back to the source aligns each rendered block's visible characters with the
source lines of that block, skipping Markdown syntax. Text that can't be aligned (for example, an image's
"not found" notice) can't be highlighted, and the app says so instead of guessing.
