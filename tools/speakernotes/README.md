<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-masthead-dark.svg"><img src="../../.github/assets/speakernotes-masthead-light.svg" width="100%" alt="SpeakerNotes: speaker notes that float over your slides and stay out of your screen share. By Vinay Roy."></picture>

**Speaker notes that float over your slides on Zoom and Google Meet, one slide at a time, and stay out of your
screen share.** You see them; your audience sees your slides.

<p>
<a href="https://github.com/roy-vinay/applied-ai-agents/releases/download/speakernotes-latest/SpeakerNotes-macOS.zip"><picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/btn-speakernotes-download-dark.svg"><img src="../../.github/assets/btn-speakernotes-download-light.svg" width="49%" alt="Download for Mac: free for macOS 13 and later. Get SpeakerNotes-macOS.zip"></picture></a>
<a href="#install"><picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/btn-speakernotes-install-dark.svg"><img src="../../.github/assets/btn-speakernotes-install-light.svg" width="49%" alt="One-line install: paste one command, run it again to update"></picture></a>
</p>

<p>
  <img src="docs/img/app-present.png" width="32%" alt="Presenting: one slide's notes, with the parts of an agent highlighted">
  <img src="docs/img/app-emphasize.png" width="32%" alt="The Emphasize panel: describe what to emphasize, see what's emphasized">
  <img src="docs/img/app-text-settings.png" width="32%" alt="Text settings: size, typeface and line spacing">
</p>

Jump to: [how it hides](#share) · [slides](#slides) · [reading](#read) · [demo-safe](#demo) · [decisions](#decisions) · [shortcuts](#shortcuts) · [install](#install)

<a name="problem"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-sec-problem-dark.svg"><img src="../../.github/assets/speakernotes-sec-problem-light.svg" width="100%" alt="The problem: your notes, or your audience's view"></picture>

On one laptop screen, Presenter View doesn't survive a full-screen share. Either the share takes over and your
notes disappear, or you share the whole screen and everyone reads them. A second monitor fixes it, but not in a
hotel room or on a call from the car.

SpeakerNotes is the smallest fix: a small window that sits on top of everything, shows the notes for the slide
you're on, and asks macOS to leave it out of every screen capture.

<a name="glance"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-sec-glance-dark.svg"><img src="../../.github/assets/speakernotes-sec-glance-light.svg" width="100%" alt="At a glance: what it does"></picture>

<p>
<a href="#share"><picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-glance-private-dark.svg"><img src="../../.github/assets/speakernotes-glance-private-light.svg" width="49%" alt="Private: asks macOS to leave the notes out of every screen capture. Checked in CI on every change."></picture></a>
<a href="#slides"><picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-glance-slides-dark.svg"><img src="../../.github/assets/speakernotes-glance-slides-light.svg" width="49%" alt="One slide at a time: Markdown notes with --- between slides, moved from any app."></picture></a>
<a href="#read"><picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-glance-readable-dark.svg"><img src="../../.github/assets/speakernotes-glance-readable-light.svg" width="49%" alt="Easy to read: size, typeface and spacing, plus emphasis by hand or on-device AI."></picture></a>
<a href="#demo"><picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-glance-demo-dark.svg"><img src="../../.github/assets/speakernotes-glance-demo-light.svg" width="49%" alt="Demo-safe: Dock icon, Open at Login, reopens on the same slide, never steals focus."></picture></a>
</p>

<a name="share"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-sec-share-dark.svg"><img src="../../.github/assets/speakernotes-sec-share-light.svg" width="100%" alt="How it stays out of your share"></picture>

macOS lets an app mark a window as private to screen capture. SpeakerNotes does that for its notes window, so a
whole-screen share or a recording shows what's underneath instead. CI checks it on every change by capturing the
same part of the screen with hiding off, then on:

<p>
  <img src="docs/img/capture-visible-crop.png" width="49%" alt="Hiding off: the notes window appears in the capture">
  <img src="docs/img/capture-hidden-crop.png" width="49%" alt="Hiding on: the same capture shows only the slide behind the notes">
</p>
<p><sub><b>Left:</b> what you see. <b>Right:</b> what your screen share and recordings see, from the same capture with hiding on.</sub></p>

Most video apps honor this, but not every capture method on every macOS version does, so test once on the Mac you
present from: share your **entire screen** in a call with just yourself, and record it. If the notes ever show
up, share only your slides window; the notes then can't appear.

<a name="slides"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-sec-slides-dark.svg"><img src="../../.github/assets/speakernotes-sec-slides-light.svg" width="100%" alt="One slide at a time"></picture>

Write notes in Markdown with a line of `---` between slides. With no `---` lines, each `#` or `##` heading starts
a slide, so a Word or PDF script converts easily.

```markdown
# What is an AI agent?
- A model that can **take actions**, not just answer

---

## The agent loop
Perceive, plan, act, reflect. ==Pause here.==
```

<kbd>⌃⌥→</kbd> and <kbd>⌃⌥←</kbd> move between slides from any app. Turn on **Move with My Slide Keys** and your
usual arrow keys move the notes too. Click the slide counter to jump to any slide by title, press
<kbd>⌃⌥Space</kbd> for a teleprompter scroll, and <kbd>⌘E</kbd> to edit in place.

<a name="read"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-sec-read-dark.svg"><img src="../../.github/assets/speakernotes-sec-read-light.svg" width="100%" alt="Make it easy to read"></picture>

The **Aa** button sets size, typeface (System, Rounded, Serif, Mono) and line spacing. Highlight, bold, color or
underline a phrase everywhere it appears: select text and right-click, write `==like this==`, or describe it. Type
"highlight the parts of an agent" and Apple's on-device model reads every slide and finds them, on your Mac, with
macOS 26 and Apple Intelligence. Emphasis is saved beside each file and never changes the file itself.

<a name="demo"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-sec-demo-dark.svg"><img src="../../.github/assets/speakernotes-sec-demo-light.svg" width="100%" alt="Built for a live demo"></picture>

<p>
  <img src="docs/img/app-empty.png" width="49%" alt="With nothing open: Open Notes, Write Notes, and recent files">
  <img src="docs/img/app-edit.png" width="49%" alt="Editing: Markdown with headings and slide breaks colored">
</p>

A Dock icon that always brings the notes back, **Open at Login**, and a relaunch that returns to the same file and
slide. Unplug a projector mid-talk and the window moves back onto a screen you can see. It never takes focus from
your slides, and **Click-through** (<kbd>⌃⌥T</kbd>) lets clicks pass through it entirely.

<a name="decisions"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-sec-decisions-dark.svg"><img src="../../.github/assets/speakernotes-sec-decisions-light.svg" width="100%" alt="Decisions and trade-offs"></picture>

<p>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-decision-hide-dark.svg"><img src="../../.github/assets/speakernotes-decision-hide-light.svg" width="49%" alt="Hide, don't detect: the notes are always private to capture."></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-decision-model-dark.svg"><img src="../../.github/assets/speakernotes-decision-model-light.svg" width="49%" alt="The model finds, code decides: a phrase is kept only if it appears word for word."></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-decision-file-dark.svg"><img src="../../.github/assets/speakernotes-decision-file-light.svg" width="49%" alt="Emphasis beside the file: the notes file stays exactly as written."></picture>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-decision-permissions-dark.svg"><img src="../../.github/assets/speakernotes-decision-permissions-light.svg" width="49%" alt="No permissions by default: following slide keys is opt-in."></picture>
</p>

<a name="shortcuts"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-sec-shortcuts-dark.svg"><img src="../../.github/assets/speakernotes-sec-shortcuts-light.svg" width="100%" alt="Shortcuts"></picture>

<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-shortcuts-dark.svg"><img src="../../.github/assets/speakernotes-shortcuts-light.svg" width="100%" alt="Shortcuts. From any app: Control Option arrows for next or previous slide, Control Option Space to auto-scroll, Control Option up and down for speed, Control Option T for click-through, Control Option N to show or hide. In the notes: arrows or Space for slides, Command O and S to open and save, Command E to edit, Command T and plus and minus for text, Command brackets for see-through."></picture>

<a name="status"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-sec-status-dark.svg"><img src="../../.github/assets/speakernotes-sec-status-light.svg" width="100%" alt="Status"></picture>

<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-status-dark.svg"><img src="../../.github/assets/speakernotes-status-light.svg" width="100%" alt="Status: 12 parser tests on every change; Apple silicon and Intel builds that open on macOS 13; launch, linking and capture hiding checked in CI; instructions not tested in CI."></picture>

Early, version 0.2. CI runs on macOS 26 for every change. Instructions aren't tested there, because the build
machines can't run Apple Intelligence.

<a name="install"></a>
<picture><source media="(prefers-color-scheme: dark)" srcset="../../.github/assets/speakernotes-sec-install-dark.svg"><img src="../../.github/assets/speakernotes-sec-install-light.svg" width="100%" alt="Install and build"></picture>

Paste this in Terminal. Run it again any time to update; your notes and settings are kept.

```bash
curl -fsSL https://raw.githubusercontent.com/roy-vinay/applied-ai-agents/main/tools/speakernotes/install.sh | bash
```

Or download **[SpeakerNotes-macOS.zip](https://github.com/roy-vinay/applied-ai-agents/releases/download/speakernotes-latest/SpeakerNotes-macOS.zip)** (the latest build from main), double-click it, and move
**SpeakerNotes.app** to Applications. It isn't notarized yet, so the first time, right-click it and choose **Open**.

To build it yourself:

```bash
cd tools/speakernotes
swift test                        # 12 tests
./scripts/build-app.sh            # build/SpeakerNotes.app, icon included
open build/SpeakerNotes.app
```

Swift and AppKit, Swift Package Manager, no dependencies. MIT License. [Changelog](CHANGELOG.md).
