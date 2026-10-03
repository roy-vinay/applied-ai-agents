# FF-01: Unsupported policy claims

**A support bot states a policy that the company's own policy documents don't contain.**

> **Status: Phase 1 of 3, fault injection.** This phase tests whether guard mechanics catch failures we
> deliberately injected. It does **not** yet measure how often real models make these mistakes, or whether
> the guards catch the mistakes real models actually make. Phases 2 and 3 do that.

## The case

In *Moffatt v. Air Canada* (2024 BCCRT 149), a customer booking travel after a family death asked the
airline's website chatbot about bereavement fares. The chatbot said he could apply for the reduced fare
within 90 days of the ticket being issued, including after travel. The airline's bereavement policy page
said the opposite: refunds for completed travel were not allowed.

When the airline refused the refund, the customer took it to British Columbia's Civil Resolution Tribunal.
The airline argued it wasn't responsible for what the chatbot said. The tribunal rejected that, found
negligent misrepresentation, and ordered the airline to pay the fare difference plus interest and fees.
As the tribunal put it, it should be obvious that a company is responsible for all the information on its
website, whether it comes from a static page or a chatbot.

Sources: [Law360 Canada](https://www.law360.ca/ca/articles/1804075) ·
[Mondaq summary](https://www.mondaq.com/canada/new-technology/1427926/airline-ordered-to-compensate-a-bc-man-because-its-chatbot-provided-inaccurate-information) ·
[AI Incident Database](https://incidentdatabase.ai/reports/3673/)

**The question a leader should ask:** *What stops our assistant from stating a policy that isn't in our
policy documents, and how would we know if it did?*

> This experiment reproduces the general failure mode described in public reporting. It does not reproduce,
> or make claims about, the airline's production architecture, prompts, models, or safeguards. Everything
> below uses a fictional airline with invented policies.

## Phase 1: fault injection

**System.** *Skylark Air*, a fictional airline with 10 short policies (bereavement fares, refunds, changes,
baggage, delays, cancellation, pets, minors, seats, pregnancy). See [`kb.py`](kb.py).

**Questions.** Three kinds, drawn at random: answerable questions a policy covers, questions no policy
covers, and leading questions that invite the bot to agree with a policy that doesn't exist ("Your chat
said I can claim the bereavement discount within 90 days after my flight, right?").

**Answers.** No model is involved. A generator gives each question either a correct answer (including
correct paraphrases and honest "I don't know" replies) or one of nine failure behaviors we wrote: a wrong
number, an invented extra condition, a missing or fake citation, agreeing with a leading question, and so
on. See [`model.py`](model.py).

**Guards.** Rule-based checks, added one at a time, each on top of the last. See [`guards.py`](guards.py).
None of them calls a model.

**What this phase can and can't show.** The same person wrote the failures and the guards, so the guards
are tested against failures their author anticipated. Treat the numbers as a test of guard mechanics, not
as evidence about real-world performance. Real-model outputs in Phase 2 serve as the held-out test.

## Phase 1 results

500 randomized trials: 354 injected failures, 146 correct answers.

| Guards (each adds to the one above) | Injected failures not caught | Correct answers wrongly blocked |
| --- | ---: | ---: |
| No guards | 354/354 (100%) | 0/146 (0%) |
| + Citation required | 264/354 (75%) | 0/146 (0%) |
| + Citation must exist | 217/354 (61%) | 0/146 (0%) |
| + Citation must match the question | 179/354 (51%) | 10/146 (7%) |
| + Every number must appear in the cited policy (exact text) | 74/354 (21%) | 41/146 (28%) |
| + Same check, with units normalized (24 hours = a day) | 74/354 (21%) | 10/146 (7%) |

**Final layer: detection recall 79.1%, false-positive rate 6.8%.** "No guards" is 100% by construction:
every injected failure is shown when nothing checks it. The full breakdown by answer type is in
[`results.md`](results.md).

## What Phase 1 shows

1. **A cited answer is not a grounded answer.** Requiring a citation that exists and matches the question
   still let 51% of injected failures through. Each of those cited a real policy while saying something
   the policy doesn't say, the same pattern as the source case.
2. **Rule-based checks hit a ceiling at meaning.** 65 of the 74 failures that get past every layer contain
   no number or other checkable fact: "Exceptions can also be made after travel," or simply "Yes, that's
   correct" to a leading question. Rules catch claims that are wrong in form; claims that are wrong in
   meaning need a check that understands meaning. The source case's claim included "90 days," so these
   rules would have caught it. A vaguer version would not.
3. **Implementation details decide a guard's cost.** Checking numbers as exact text wrongly blocked 28% of
   correct answers, because "a day" doesn't match "24 hours." Normalizing units brought that to 7% with no
   loss of recall.
4. **A 7% false-positive rate is not small.** In production, that's 7 in 100 good answers refused or
   escalated. All 10 here trace to one gap: the relevance check matches topic keywords, and "delays" isn't
   in the delay policy's list. Better synonym handling or retrieval scoring is the next hypothesis to test,
   not a demonstrated fix.

## Next: Phases 2 and 3

**Phase 2, real models** ([protocol and harness](phase2)). The guards, policies, 100 questions, and prompt
are **frozen** before any model answers. Three small open models from three families answer locally, at no
cost: answerable, unanswerable, leading, false-premise, and requests to bend a policy. We measure how often
unsupported claims occur on their own, what form they take, and how much of that the frozen guards catch.

**Phase 3, semantic verification.** Add a second model call that judges whether the cited policy supports
each sentence of the answer. Compare rules only, the semantic check only, and both together, on real-model
answers, measuring unsupported-claim rate, false refusals, cost per 100 answers, and latency. Phase 3 is
designed only after Phase 2 results are in, so it targets the failures real models actually make.

This phase also tests something harder: the verifier is a model too, and it will make its own mistakes.
How reliably can one model judge whether another model's statement is supported by a source?

## Run it

```bash
cd failure-files/ff-01-unsupported-policy-claims
python run.py           # both result tables
python run.py --check   # CI check: fails if the final layer gets worse than the saved baseline
```

Standard library only. No API key needed for Phase 1.
