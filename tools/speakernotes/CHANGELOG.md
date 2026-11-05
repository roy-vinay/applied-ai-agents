# Changelog

## 0.5.0

- **Scroll as I Speak** (the waveform button, or **⌃⌥V**): the notes scroll as you talk, with the words you've said dimmed and your current line kept near the top. Apple's on-device speech recognition listens to your microphone only, never the call, and nothing is saved or sent. Code, not the recognizer, decides where you are: small steps forward move at once, bigger jumps need two readings to agree, going back needs a long near-exact match, and filler words or ad-libs never move it. Scrolling by hand pauses it for a few seconds; it never changes slides on its own.
- **Question parking lot** (the tray button, or **⌃⌥P** from any app): park an audience question you promise to come back to, in one line, tagged with the slide. With Scroll as I Speak on, it's prefilled with what you just said, so repeating the question aloud captures it. Return sends you back to your slides. On the last slide you get a reminder; check questions off, or copy the list for the follow-up email.

## 0.4.0

- **Moving the notes moves your slides too.** While following is on (Follow My Slides or Move with My Slide Keys), the ⌃⌥ arrow hotkeys, the arrow keys in the notes, the ‹ › buttons and the slide list also move your presentation. Keynote and PowerPoint go to the exact slide; other apps (Google Slides in a browser, a PDF viewer) get → or ← once per slide. Turn it off with **Slides > Moving the Notes Moves My Slides**. Sending keys to another app needs Accessibility permission.
- **Much faster following of other apps.** SpeakerNotes looks four times a second, skips reading when nothing changed, reads big text quickly first and carefully only when needed, and moves at once on a near-exact title. A slide change now shows in the notes in well under a second instead of several seconds. Keynote and PowerPoint are checked four times a second too.

## 0.3.1

- **Following other apps is much stricter.** It now reads only the slide's title, not every word on screen, and moves only when nearly all of a notes title's words are in it. One shared word is never enough, and jumping more than three slides needs a near-exact title. Text recognition's one-letter misreads are tolerated.
- **Move with My Slide Keys explains itself.** When Accessibility permission is missing, the menu says so and SpeakerNotes opens the right Settings page. It starts working as soon as permission is given, without reopening.
- **Updates reset stale permissions.** The installer clears Accessibility, Screen Recording and Automation for SpeakerNotes when it updates, because macOS quietly stops honoring permissions given to an earlier unsigned build. macOS asks again the first time each is needed.

## 0.3.0

- **Follow My Slides** (the ⟳ button or **⌃⌥F**): the notes move with your presentation on their own.
  - **Keynote and PowerPoint:** exact. SpeakerNotes asks the app which slide is showing, even during a full-screen slideshow. Numbered headings in your notes (`## 7. Pricing`) are matched by number.
  - **Google Slides, Canva, PDFs and other apps:** SpeakerNotes reads the slide's title with Apple's on-device text recognition and moves to the notes slide with that title, only when the match is clear and two readings agree. On macOS 26 with Apple Intelligence, titles that don't match word for word are matched by meaning.
  - Moving by hand pauses following for a few seconds. Call apps like Zoom are ignored.
- **Import Notes from Keynote or PowerPoint** (File menu, or the welcome screen): turns the open deck's presenter notes into a notes file, one numbered heading per slide, and starts following.
- macOS asks once for Automation (Keynote, PowerPoint) and Screen Recording (other apps) when you first use these.

## 0.2.1

- SpeakerNotes now lives in [applied-ai-agents](https://github.com/roy-vinay/applied-ai-agents/tree/main/tools/speakernotes), next to Tech60. The install command, **Check for Updates** and downloads point there. Your notes and settings are kept.

## 0.2.0

- **New look:** a dark, translucent window with no title bar clutter. The header has a slide picker (click **2 / 12** to jump to any slide) and buttons for text, emphasis, opening and editing. The footer has previous and next, a progress bar you can click to jump, and the teleprompter controls.
- **Easy to open notes:** when nothing is open, the window offers **Open Notes…**, **Write Notes** and your recent files. **File > Open Recent** and the Dock icon's menu list them too.
- **Always easy to launch:** SpeakerNotes now has a Dock icon and a full menu bar. Clicking the Dock icon always brings the notes back, **SpeakerNotes > Open at Login** starts it with your Mac, and it reopens on the same file and slide. If a display is unplugged mid-talk, the window moves back onto a screen you can see (**View > Reset Window Position** does it by hand).
- **Text settings (Aa):** size, typeface (System, Rounded, Serif, Mono) and line spacing.
- **Emphasis:** highlight, bold, color or underline any phrase everywhere it appears. Select text and right-click, write `==text==` in your notes, or describe it in the Emphasize panel. Emphasis is saved per file and never changes the file itself.
- **Instructions with on-device AI:** on macOS 26 with Apple Intelligence, type something like "highlight the parts of an agent" and Apple's on-device model finds them on every slide. Your notes never leave your Mac. On other Macs, the panel highlights the exact phrase you type.
- Small messages confirm changes ("Saved", "Text 24 pt"), and click-through shows an amber border so you always know it's on.

## 0.1.0

- **Floating notes window** that stays on top of every app, including full-screen slides. Move it and resize it anywhere; it remembers where you left it.
- **Stays out of your screen share and recordings** where macOS allows it. Turn this off from the menu bar if you want viewers to see it.
- **Never steals focus:** click your slides behind it to change them. The notes stay put.
- **Per-slide notes:** separate slides with a line of `---` (or use `#` and `##` headings). **⌃⌥→** and **⌃⌥←** move between them from any app.
- **Move with My Slide Keys** (optional): when you press → or ← in your slides, the notes follow. Needs Accessibility permission.
- **Teleprompter:** **⌃⌥Space** starts or stops auto-scroll, **⌃⌥↑** and **⌃⌥↓** change the speed.
- **Click-through:** **⌃⌥T** lets clicks pass through the window to what's under it.
- **Markdown files:** open with **⌘O**, drop a file on the window, or use Open With in Finder. Headings, bullets, numbered lists, bold, italic and code are shown clearly. The notes reload when you edit the file in another app.
- **Edit in place:** **⌘E** switches between editing and presenting; edits save back to the file.
- Text size (**⌘+ / ⌘−**) and see-through (**⌘] / ⌘[**).
