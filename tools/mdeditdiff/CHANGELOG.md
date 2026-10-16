# Changelog

## 0.3.3

- **Fixed:** a thin vertical line stayed across the document after switching from Split back to Read.
- **Fixed:** a section break followed by a heading no longer shows two dividers.

## 0.3.2

- **Day and night app icon:** white by day, graphite black at night. It follows Light and Dark mode, so with Appearance set to Auto it switches with the time of day.
- **When it switches:** the Dock icon changes while the app is running. On macOS versions that support dark app icons, Finder shows the matching icon too.

## 0.3.1

A visual refresh of the Mac app. No change in behavior.

- **New app icon:** the md monogram on indigo, over a green bar (added) and a struck-through red bar (removed).
- **Native toolbar:**
  - the Read / Edit / Split switch is centered, with icons;
  - on the right, a changes button ("5 changes", which jumps to the next one, or "Up to date") and a History button.
- **Reading view:**
  - the document is set as a sheet of paper on a soft background, with New York serif body text, SF Pro headings and SF Mono code;
  - change marks sit in the left margin, like a proofreader's marks;
  - tables, quotes, inline code and section breaks are restyled;
  - light and dark mode are both tuned.
- **Editor:** more breathing room, and the same indigo accent for list markers and inline code.

## 0.3.0

The first packaged release of mdEditDiff: the Mac app and the command-line tool and MCP server.

**Mac app**
- **Changes since you last read**, highlighted in Read and Split modes:
  - added blocks;
  - changed blocks, with inserted and removed words marked;
  - removed passages shown where they used to be.
- **Review bar** showing who reported each change and their note, with Next and Previous (⌘] and ⌘[) and Mark as read (⇧⌘K).
- **Restore** a removed passage in place, as an undoable, unsaved edit.
- **Version history** (⇧⌘H): compare with any earlier version, or restore a whole version.
- **Live refresh** when an agent edits an open file. If you have unsaved edits, you choose to compare, keep yours, or load theirs.
- **Read, Edit and Split modes**, saves that never touch what you didn't change, and a safe preview (no scripts, no remote images).
- **Settings** via `defaults write`: `DefaultMode`, `Appearance`, `MarkReadOnClose`.

**Command-line tool and MCP server**
- **Commands:** `changes`, `seen`, `checkpoint`, `history`, `diff`, `show`, `watch`, and `mcp` (six MCP tools).
- **Diffs are about meaning, not bytes:** block-level, then word-level, so rewrapping and renumbering aren't changes.
- **Each reader has its own "last looked" point**, and authorship is self-reported through checkpoints.
- **For the Mac app:** `changes --with-base`, and `at_line` on removed blocks.

**Known limitations**
- The Mac app is ad-hoc signed but not notarized. macOS asks you to allow it the first time (see "Install" in the release notes).
- Needs macOS 14 or later. The command-line tool needs Node.js 20 or later.
