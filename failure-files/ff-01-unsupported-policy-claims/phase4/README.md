# FF-01 Phase 4: numbers in code, meaning in a model

**Question:** Phase 3's judge, a small local model, missed most failures that come down to comparing a
customer's number with a policy limit ("your 27 kg bag is within the 23 kg limit"). Does checking those
comparisons in plain code fix that without blocking good answers? And for what code can't check, does a
purpose-built judge model (TypeSafe's Jev 1.13) do better than a general one?

> **Status: building.** The number check is frozen and scored. The Jev run is in progress.

## The two additions

- **Number check** ([`numbers_check.py`](numbers_check.py)). When a question gives a number a policy turns
  on (a bag's weight, a delay, hours to departure, a child's age, weeks of pregnancy, when a ticket was
  booked), the code works out what the policy gives this customer. It then reads the answer's conclusion
  with a short list of phrases, and blocks the answer if it says the opposite. If it can't parse
  something, it stays out of the way. No model, no cost, instant.
- **Jev judge** ([`jev_judge.py`](jev_judge.py), [`jev_prompt.json`](jev_prompt.json)). Jev is a structured
  decision model: it picks from fixed answers rather than writing text. It's asked one question per answer
  (SUPPORTED or UNSUPPORTED) through OpenRouter's decisions endpoint, model `typesafe/jev-1.13`. Not `typesafe/jev-router`,
  which forwards requests to other models.

## Protocol

- Same splits as Phase 3: dev is the Phase 2 answers, test is the Phase 3 answers.
- The number check was built on dev only and frozen ([`FREEZE_numbers.json`](FREEZE_numbers.json)) before
  it was scored on test. Caveat: the test answers were read during Phase 3 labeling, so treat its test
  catch rate as slightly optimistic.
- The Jev prompt is fixed before any Jev call. A 12-answer pilot checks only that the call works and what
  it costs; the prompt isn't tuned afterwards.
- **Spending is capped twice:** the OpenRouter key has a $1 limit, and the script stops at $0.90 using a
  running total kept in [`jev/spend.json`](jev). Jev 1.13 lists at $0.042 per million input tokens and
  free output; judging all 600 answers should cost about 3 cents.
