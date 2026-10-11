# FF-01 Phase 1: planted mistakes

[← FF-01 overview](..) · **Phase 1** · [Phase 2](../phase2) · [Phase 3](../phase3) · [Phase 4](../phase4)

**Question:** before trusting a guard with real chatbots, does it catch the mistakes we already know about?
Here we write the wrong answers ourselves, feed them to the guard, and count what it catches and what good
answers it wrongly blocks.

## Setup

**The airline.** *Skylark Air*, a fictional airline with 10 short policies (bereavement fares, refunds,
changes, baggage, delays, cancellation, pets, minors, seats, pregnancy). See [`kb.py`](../kb.py).

**Questions.** Three kinds, drawn at random: questions a policy answers, questions no policy covers, and
leading questions that invite the bot to agree with a policy that doesn't exist ("Your chat said I can
claim the bereavement discount within 90 days after my flight, right?").

**Answers.** No AI model is involved. A generator gives each question either a correct answer (including
correct paraphrases and honest "I don't know" replies) or one of nine planted mistakes: a wrong number, an
invented extra condition, a missing or fake citation, agreeing with a leading question, and so on. See
[`model.py`](../model.py).

**The guard.** Rule-based checks, added one at a time, each on top of the last. See
[`guards.py`](../guards.py). None of them calls a model.

**What this phase can and can't show.** The same person wrote the mistakes and the guard, so the guard is
tested against mistakes its author expected. Treat the numbers as a test of how the checks work, not as
evidence about real chatbots. That's what Phase 2 is for.

## Results

500 randomized trials: 354 planted mistakes, 146 correct answers.

| Guard (each layer adds to the one above) | Failures caught | Good answers wrongly blocked |
| --- | ---: | ---: |
| No guard | 0/354 (0%) | 0/146 (0%) |
| + A citation is required | 90/354 (25%) | 0/146 (0%) |
| + The cited policy must exist | 137/354 (39%) | 0/146 (0%) |
| + The cited policy must match the question's topic | 175/354 (49%) | 10/146 (7%) |
| + Every number must appear in the cited policy (exact text) | 280/354 (79%) | 41/146 (28%) |
| **+ Same check, with units normalized (24 hours = a day)** | **280/354 (79%)** | **10/146 (7%)** |

The full breakdown by answer type is in [`results.md`](../results.md).

## What Phase 1 shows

1. **A cited answer is not a correct answer.** Requiring a citation that exists and matches the question
   still let half the planted mistakes through. Each of those cited a real policy while saying something
   the policy doesn't say, the same pattern as the Air Canada case.
2. **Rules hit a ceiling at meaning.** 65 of the 74 mistakes that got past every layer contain no number
   or other checkable fact: "Exceptions can also be made after travel," or simply "Yes, that's correct" to
   a leading question. Rules catch claims that are wrong in form; claims that are wrong in meaning need a
   check that understands meaning. The Air Canada claim included "90 days," so these rules would have
   caught it. A vaguer version would not.
3. **Small implementation details decide a guard's cost.** Checking numbers as exact text wrongly blocked
   28% of good answers, because "a day" doesn't match "24 hours." Normalizing units brought that to 7% with
   no loss in catches.
4. **7% wrongly blocked is not small.** In production, that's 7 in every 100 good answers refused or sent
   to a person. All 10 here trace to one gap: the topic check matches keywords, and "delays" isn't in the
   delay policy's list.

## Run it

```bash
cd failure-files/ff-01-unsupported-policy-claims
python run.py           # both result tables
python run.py --check   # CI check: fails if the final layer gets worse than the saved baseline
```

Standard library only. No API key needed.
