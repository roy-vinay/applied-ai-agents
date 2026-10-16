# Changelog

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
