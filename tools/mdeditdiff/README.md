# mdEditDiff

**An editor for people, a diff for agents. See what changed in a Markdown file since you last looked, and who changed it.**

AI agents increasingly work through shared Markdown files. A planner agent writes `plan.md`, an
implementer follows it, a person fixes a step, and the planner revises it again. Everyone involved needs to
know what changed since they last read the file. Today they find out by re-reading the whole file, by
running `git diff` (which only knows about commits), or by hoping the last writer left a note.

mdEditDiff keeps a private change history for each Markdown file on your computer and gives every reader,
agent or person, its own "last looked" point. It comes in two parts that share that history:

- **For agents: the `mdeditdiff` command-line tool and MCP server.** An agent asks what changed and gets back
  only the changed parts, word by word, with the section each change is in and who reported it. It works
  with Claude Code, Cursor and any agent that can run a command, and it never changes your files.
- **For people: the mdEditDiff Mac app.** A native reader and editor that opens Markdown files from
  Finder as formatted documents, with Read, Edit and Split modes. Saving never touches anything you didn't
  edit, and each save is recorded in the same history the agents use. (Early prototype; highlighted
  changes and the revision timeline are coming next.)

Everything stays on your computer. There is no account, no cloud service and no telemetry.

## Get it

### The Mac app

Requires macOS 14 (Sonoma) or later, on Apple silicon or Intel.

1. Sign in to GitHub, open the latest
   [mdeditdiff build](https://github.com/roy-vinay/applied-ai-agents/actions/workflows/mdeditdiff.yml?query=branch%3Amain+is%3Asuccess),
   click the top run, and download **mdEditDiff-macOS** under **Artifacts**.
2. Unzip it (it may be zipped twice) and drag **mdEditDiff.app** into **Applications**.
3. Allow it to open the first time. The app isn't notarized by Apple yet, so macOS blocks it with
   *"Apple could not verify mdEditDiff"*. Click **Done**, then either:
   - open **System Settings > Privacy & Security**, scroll down, click **Open Anyway**, and confirm; or
   - run `xattr -dr com.apple.quarantine /Applications/mdEditDiff.app` in Terminal.
4. Open a file: right-click any `.md` file in Finder and choose **Open With > mdEditDiff**. To make it the
   default, select a `.md` file, press ⌘I, pick mdEditDiff under **Open with**, and click **Change All**.

Using it: files open in **Read** mode. Press **⌘2** to edit the Markdown, **⌘3** to edit with a live
preview beside it, **⌘1** to go back to reading, and **⌘S** to save.

### The command-line tool and MCP server

Requires Node.js 20 or later (check with `node -v`; get it from [nodejs.org](https://nodejs.org)).

```bash
git clone https://github.com/roy-vinay/applied-ai-agents
npm install -g ./applied-ai-agents/tools/mdeditdiff
mdeditdiff --help
```

Connect it to Claude Code:

```bash
claude mcp add mdeditdiff -- mdeditdiff mcp
```

With the tool installed, the Mac app records each save in the shared history, and the window subtitle shows
the current revision (for example "History r4").

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

## Use it with an agent

**MCP (Claude Code, Cursor, and other MCP clients).** Add a server that runs `mdeditdiff mcp`, as shown
above for Claude Code. In clients configured with JSON:

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

## About the Mac app

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

To download a ready-built app instead, see [Get it](#the-mac-app).

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
