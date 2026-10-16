# mdeditdiff

**What changed in a Markdown file since you last looked, and who changed it.**

AI agents increasingly work through shared Markdown files. A planner agent writes `plan.md`, an
implementer follows it, a person fixes a step, and the planner revises it again. Each of them needs to
know what changed since they last read the file. Today they find out by re-reading the whole file and
guessing, by running `git diff` (which only knows about commits), or by hoping the last writer left a note.

mdeditdiff gives every reader, agent or person, its own "last looked" point on each file. Ask it what
changed and you get back only the changed parts, in readable Markdown, with who reported them. Agents
use it through a command-line tool or an MCP server. A macOS reader app for people, built on the same
history, is in early prototype ([below](#the-mac-app-prototype)).

## What an answer looks like

A planner wrote a plan. Then a person removed a question, tightened a step and recorded a decision, without
telling anyone. Then the planner revised it and checked in. The implementer asks what changed:

```
$ mdeditdiff changes plan.md --reader implementer
plan.md: 4 changes (2 modified, 1 added, 1 removed) since r1, your last look, up to r3. Marked as seen.
By: r2 changed outside, not reported; r3 planner: "Proposed a row limit"
Word changes are shown as [-removed-] {+added+}.

~ modified Export to CSV > Steps (list-item, line 6)
    Build the CSV on the server{+, streaming rows+}.
- removed  Export to CSV > Open questions (list-item, was line 11)
    - Should exports include archived rows?
~ modified Export to CSV > Open questions (list-item, line 11)
    What is the row limit? {+Proposed: 100,000.+}
+ added    Export to CSV > Open questions (paragraph, line 13)
    Decision: archived rows are excluded.
```

The implementer gets four precise changes, with the section each one is in, instead of re-reading the
whole plan. Unchanged sections are never repeated. Rewrapped paragraphs and renumbered lists don't count
as changes. Add `--json` for structured output ([format](docs/FORMAT.md)).

## Install

Requires Node.js 20 or later.

```bash
git clone https://github.com/roy-vinay/applied-ai-agents
npm install -g ./applied-ai-agents/tools/mdeditdiff
mdeditdiff --help
```

## Use it with an agent

**MCP (Claude Code, Cursor, and other MCP clients).** Add a server that runs `mdeditdiff mcp`.
In Claude Code:

```bash
claude mcp add mdeditdiff -- mdeditdiff mcp
```

In clients configured with JSON:

```json
{ "mcpServers": { "mdeditdiff": { "command": "mdeditdiff", "args": ["mcp"] } } }
```

The server offers six tools: `changes_since`, `mark_seen`, `checkpoint`, `history`, `diff`, and
`get_revision`. None of them changes a file.

**Command line.** Any agent that can run shell commands can use the same operations:

```bash
mdeditdiff changes plan.md --reader implementer        # what changed since I last looked
mdeditdiff checkpoint plan.md --author implementer --note "Split step 4 into two steps"
```

**Tell your agents the protocol.** Paste this into your agent instructions (for example `CLAUDE.md` or
`AGENTS.md`):

> Shared Markdown files (plans, specs, notes) are tracked with mdeditdiff. Use a stable reader name for
> yourself, such as your role. Before working from a shared file, call `changes_since` instead of
> re-reading the whole file. Right after you edit a shared file, call `checkpoint` with your name and a
> one-line note saying what you changed.

## The Mac app (prototype)

`app/` holds the macOS reader for people, built on the same history. This first version (Milestone 2)
opens a Markdown file in **Read** mode, and switches to **Edit** (plain-text editor with light syntax
highlighting) or **Split** (editor and preview side by side) with ⌘1, ⌘2, ⌘3 or ⇧⌘M.

- **Saving never touches what you didn't change.** Saving without edits writes back the exact original
  bytes. Edited files keep their line endings (LF, CRLF or CR), byte-order mark, and final newline.
  Nothing autosaves over your file.
- **Safe preview.** Raw HTML in a document is shown as text, scripts never run, `javascript:` links are
  dropped, and remote images are not loaded. Local images load relative to the document.
- **Shared history.** If the `mdeditdiff` command is installed, each save is recorded as a checkpoint under
  your macOS user name, and the window subtitle shows the current revision.

Requires macOS 14 or later. To build it yourself (needs Xcode or the Swift toolchain):

```bash
cd tools/mdeditdiff/app
./scripts/build-app.sh        # creates build/mdEditDiff.app and build/mdEditDiff-macOS.zip
```

CI also builds a universal app on every change: open the latest
[mdeditdiff workflow run](https://github.com/roy-vinay/applied-ai-agents/actions/workflows/mdeditdiff.yml)
and download **mdEditDiff-macOS** under Artifacts. The app is not notarized yet, so macOS will block the
first launch: right-click the app, choose **Open**, then **Open** again (or run
`xattr -dr com.apple.quarantine mdEditDiff.app`).

Coming next: highlighted changes since you last read the file, the revision timeline, and restore
(Milestone 3).

## Commands

| Command | What it does |
| --- | --- |
| `changes <file> --reader <name>` | Changes since this reader last looked, then marks the current version as seen. `--peek` leaves the "last looked" point where it is; `--full` adds the full current text. The first call for a reader returns the whole file. |
| `seen <file> --reader <name>` | Marks the current version as seen without showing anything. |
| `checkpoint <file> --author <name> [--note <text>]` | Records the current version with your name and a short note. |
| `history <file>` | Lists revisions, newest first, and where each reader last looked. |
| `diff <file> <from> [<to>]` | Compares any two revisions, for example `r2 r5` or `r2 latest`. |
| `show <file> <revision>` | Prints a revision's full text, for example to recover a deleted section. |
| `watch <file or folder>...` | Keeps running and records a revision each time a Markdown file is saved. |
| `mcp` | Runs the MCP server. |

`--reader` and `--author` can also come from `MDEDITDIFF_READER` and `MDEDITDIFF_AUTHOR`.

## How it works

- **History.** Each time mdeditdiff is called, it reads the file and records a new revision if the content
  changed. Contents are stored compressed and deduplicated in a per-user folder (on macOS,
  `~/Library/Application Support/mdeditdiff`; on Linux, `~/.local/share/mdeditdiff`; or `$MDEDITDIFF_HOME`).
  Nothing is written next to your files, and nothing leaves your computer.
- **Readers.** Each reader name has its own "last looked" revision per file, so two agents can be at
  different points and both get correct answers.
- **Diff.** Files are split into Markdown blocks (headings, paragraphs, list items, table rows, code
  blocks), aligned, and then compared word by word inside changed blocks. Details are in
  [docs/FORMAT.md](docs/FORMAT.md).
- **Safety.** It only accepts Markdown files (`.md`, `.markdown`, `.mdx` and similar), never modifies them,
  and serializes concurrent calls so several agents can use it at once. Each file keeps up to 500
  revisions; the oldest are pruned first, except versions a reader is still using as its "last looked"
  point.

## What it can and can't tell you

- **Edits between calls are merged.** If a person and an agent both edit the file before anyone calls
  mdeditdiff, their edits land in one revision. Run `mdeditdiff watch <folder>` in the background, or have
  agents call `changes_since` before they edit, to keep edits separate.
- **Authorship is self-reported.** A checkpoint says who claims a change. mdeditdiff labels everything
  else "changed outside, not reported", and won't let an agent claim a version that may hold someone
  else's edits.
- **One file at a time.** History follows the file's path. Renaming a file starts a new history.
- **UTF-8 only.** Other encodings are refused rather than guessed.
- **Moves are not detected.** A moved paragraph shows as removed in one place and added in another.

## Develop

```bash
cd tools/mdeditdiff
npm install
npm test    # builds, then runs the unit, acceptance, two-agent simulation, concurrency and MCP tests
```

CI runs the tests on Linux and macOS with Node 20 and 22, and builds and tests the Mac app.
The app's own tests (byte-exact saving, highlighting patterns) run with `swift test` in `app/`;
its preview renderer is tested from Node (`test/preview.test.ts`).

MIT license.
