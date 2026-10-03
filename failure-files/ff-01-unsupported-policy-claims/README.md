# FF-01: Unsupported policy claims

**A support bot states a policy that the company's own policy documents don't contain.**

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

## The experiment

**System.** *Skylark Air*, a fictional airline with 10 short policies (bereavement fares, refunds, changes,
baggage, delays, cancellation, pets, minors, seats, pregnancy). See [`kb.py`](kb.py).

**Questions.** Three kinds, drawn at random: answerable questions a policy covers, questions no policy
covers, and leading questions that invite the bot to agree with a policy that doesn't exist ("Your chat
said I can claim the bereavement discount within 90 days after my flight, right?").

**Answers.** A simulated model gives each question either a correct answer (including correct paraphrases
and honest "I don't know" replies) or one of nine documented failure behaviors: a wrong number, an
invented extra condition, a missing or fake citation, agreeing with a leading question, and so on. See
[`model.py`](model.py). Because the failures are injected deliberately, the results measure **what each
guard stops and what it wrongly blocks**, not how often a real model makes each mistake.

**Guards.** Added one at a time, each on top of the last. See [`guards.py`](guards.py).

## Results

500 randomized trials: 354 faulty answers, 146 correct ones.

| Guards (each adds to the one above) | Unsupported claims shown to the customer | Correct answers wrongly blocked | Median check time |
| --- | ---: | ---: | ---: |
| No guards | 354/354 (100%) | 0/146 (0%) | 0 µs |
| + Citation required | 264/354 (75%) | 0/146 (0%) | 0 µs |
| + Citation must exist | 217/354 (61%) | 0/146 (0%) | 0 µs |
| + Citation must match the question | 179/354 (51%) | 10/146 (7%) | 2 µs |
| + Every number must appear in the cited policy (exact text) | 74/354 (21%) | 41/146 (28%) | 11 µs |
| + Same check, with units normalized (24 hours = a day) | 74/354 (21%) | 10/146 (7%) | 22 µs |

None of the layers calls a model, so the added cost per answer is zero and the added latency is microseconds.
The full breakdown by answer type is in [`results.md`](results.md).

## What we learned

1. **Citations are necessary, not sufficient.** Requiring a real, relevant citation cut unsupported claims
   from 100% to 51%. The other half cited a genuine policy while saying something that policy doesn't say,
   which is exactly the pattern in the source case.
2. **Checking numbers against the cited policy is the biggest single lever.** It took leaks from 51% to 21%.
   The source case's claim ("within 90 days") would have been caught here, because "90 days" appears nowhere
   in the bereavement policy.
3. **How a guard is implemented decides its cost.** The exact-text version blocked 28% of correct answers,
   because "a day" doesn't match "24 hours." Normalizing units brought that to 7% with no loss of protection.
4. **Rules can't check meaning.** 65 of the 74 claims that still get through contain no number to verify:
   "Exceptions can also be made after travel," or simply "Yes, that's correct" to a leading question. A
   vaguer version of the source case would pass every rule here.
5. **The remaining false blocks come from one gap.** The relevance check matches topic keywords, and "delays"
   isn't in the delay policy's list. Synonym handling, or retrieval scoring, would fix it.

## Next

Add a **semantic support check**: a second model call that asks whether the cited policy actually supports
each sentence of the answer. Then measure what it catches of the remaining 74, what it wrongly blocks, and
what it adds in latency and cost, first on these simulated answers, then on answers from real models.

## Run it

```bash
cd failure-files/ff-01-unsupported-policy-claims
python run.py           # both result tables
python run.py --check   # CI check: fails if the final layer gets worse than the saved baseline
```

Standard library only. No API key needed.
