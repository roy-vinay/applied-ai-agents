# Second Chair

A live answer tool for interviews. It listens to both sides of the conversation, searches documents you already wrote, and puts a cited answer in a window only you can see, while the interview is still happening.

It sits beside you in the interview. It never speaks, it never joins the call, and nothing leaves your Mac.

**Apple silicon, macOS 26 or later.** Free. No account, no server, no cloud model, no analytics.

## What you see

1. **The question, as heard.** One line, so you can tell if it heard the question you heard.
2. **The source card, first.** A label, the passage verbatim, and its file and heading. This arrives in about a second.
3. **The sayable answer, second.** Two or three sentences in large type, built only from that passage.

| Label | Meaning |
|---|---|
| **GROUNDED** | One passage answers it. Every figure in the answer appears in the passage. |
| **SYNTHESIZED** | Made on the spot from two or three passages, all shown. |
| **NOT IN YOUR DOCS** | Your documents don't cover it. The closest passage shows if one is worth seeing. No invented answer. Answer from judgement, then fix the prep pack. |

Every model answer goes through a **grounding check**: a figure or name that isn't in the shown passages gets the answer withheld, and you see the passages alone.

## Shortcuts

| Keys | Does |
|---|---|
| ⌃⌥Space | Type a question (Ask My Docs) |
| ⌃⌥S | Show or hide the window |
| ⌃⌥A | Ask about the last exchange |
| ⌃⌥D | Dictate your paraphrase of the question (My Voice Only) |

**Invisible on screen share.** Every Second Chair window (the main window, the floating window, sheets and alerts) is excluded from screenshots, recordings and screen sharing in Zoom, Meet, Teams and the rest. People on the call see what's behind it. While an interview runs, the Dock icon and the menu bar chair are hidden too, since a full-screen share shows those. CI checks this on every build by capturing the screen both ways sharing apps do and failing if a test window shows up.

## Setup

1. Install or update with one command in Terminal:
   ```
   curl -fsSL https://raw.githubusercontent.com/roy-vinay/applied-ai-agents/main/tools/second-chair/install.sh | bash
   ```
2. Menu bar chair icon › **Folders › Add Folder…**. Add your Obsidian vault and one folder per interview prep pack. Nothing else on the Mac is read.
3. Optional, for better answers (both free, both local):
   ```
   brew install ollama && ollama serve
   ollama pull qwen3:8b          # quality path for synthesized answers
   ollama pull embeddinggemma    # embeddings for paraphrased questions
   ```
   Then **Settings › Recheck Local Models**. Without Ollama, Second Chair still works: Apple Intelligence writes grounded answers, Apple's built-in sentence embeddings catch paraphrases, and with no model at all it lifts the two most relevant sentences straight from the passage.

## How it answers

1. **Your prepared answers first.** Any question you've already written an answer to is indexed as a question:
   ```
   ## Why are you looking for a new job?
   Your answer...

   Q: What's your management style?
   A: Your answer...

   **How do you handle conflict?**
   Your answer...
   ```
   When an interview question matches one of yours (same wording, or the same meaning with embeddings on), your answer shows exactly as you wrote it, marked **Your prepared answer**. No model touches it.
2. **Otherwise, passages.** Keyword search first, meaning search when keywords are thin, the primary prep pack ranked first. A short follow-up borrows the previous question's terms.
3. **Only then a model.** Apple Intelligence on the device compresses one strong passage into speaking length; Qwen3 8B through Ollama on `127.0.0.1` builds answers from several passages. Every model answer passes the grounding check, or it's withheld.

**What you see:** matches on the left, with tabs for **Matches**, **Similar** questions and sections in your documents, and **Earlier** questions. On the right is the whole matching section as it reads in your document (headings, lists, bold), with the sentences that answer the question marked in yellow and the question's words underlined.

Formats: Markdown and text, then PDF and Word converted on the Mac. Word files keep their headings, bulleted and numbered lists, and bold. Scans and images are counted as skipped, never silently included. The index updates when folders change between sessions, never mid-interview.

## Sessions and consent

Start one from the menu bar. You pick where (remote, in person, rehearsal), how it listens, and the primary prep pack, with a checklist (headphones, Do Not Disturb, close media tabs).

There are three listening modes and only three:

| Mode | What it hears |
|---|---|
| **Announced** | You read the disclosure sentence aloud when the call starts and confirm in the app that there was no objection. Only then does capture start. Remote: You on the microphone, Them on the system audio. In person: the room through the microphone. An objection drops the session to My Voice Only. |
| **My Voice Only** | The microphone, only while you turn dictation on with ⌃⌥D to say your own paraphrase. No one else is captured. |
| **Off** | Nothing. Typing still works. |

California is an all-party consent state. **There is no stealth mode**, no standing consent, and attestation never carries over to the next session.

**Rehearsal** is just you: it detects questions in your own speech so you can practise against your prep.

**macOS has no per-app audio tap.** "Them" is the whole system audio mix through ScreenCaptureKit, which is why Screen Recording permission is requested. Notification sounds and other tabs get in, so mute them. Speaker separation stops at two channels: in a panel, it knows You and Them, not which panellist.

### After the session

A review lists every question, what was shown and its label. Tick the misses: they're written to your primary prep pack as `_second-chair misses <date>.md`, a to-do list. Fix the prep pack, not the tool. The transcript is then deleted unless you choose **Save transcript too**.

## Checking accuracy

Write a labelled question set from your real prep ([format](examples/gate-questions.json)), then **Accuracy › Check Accuracy on a Question Set…**. It reports:

| Check | Bar |
|---|---|
| Shown answers backed by their passage | at least 95% |
| Covered questions answered from the right place | at least 85% |
| "Not in your docs" exactly when it should be | at least 90% |
| Invented figures in any shown answer | zero |
| Question to source, median / slowest 10% | under 3s / under 5s |

It doesn't lock anything. Until a check passes, the top bar and the interview setup say accuracy is unchecked, so you know to glance at the source before you say a number.

## Transcription engines

- **Apple on-device speech** (default): on-device mode is required, so audio never goes to Apple's servers.
- **whisper.cpp server** (Settings): run `whisper-server -m <model> --port 8178` and each utterance is posted to `127.0.0.1` only.

## Honest limits in 0.1

- **Parakeet V3 is not wired in yet.** The PRD names it the primary engine. 0.1 uses Apple's on-device recognizer, with whisper.cpp as the swap-in. A Parakeet engine slots into the same `SpeechEngine` protocol.
- **Voice activity detection is energy based**, not Silero. It's tuned for headphones and a quiet room.
- **The sample accuracy check in CI is small and invented** (`examples/prep-pack`). It proves the pipeline and catches regressions; it proves nothing about your corpus.
- Latency targets are measured in the gate for retrieval and the source card. End-to-end latency including transcription depends on the engine and your Mac.

## Layout

```
Sources/SecondChairCore   chunking, retrieval, labels, grounding check, question detection,
                          consent gate, session review, the evaluation gate (no UI, unit tested)
Sources/SecondChairApp    overlay, folders and index, local models, listening, sessions, CLI
examples/                 a sample prep pack and gate question set
```

Part of [applied-ai-agents](../../README.md), alongside [SpeakerNotes](../speakernotes), which supplies the private floating window pattern.
