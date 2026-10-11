# FF-01 Phase 4: numbers in code, and a purpose-built judge

[← FF-01 overview](..) · [Phase 1](../phase1) · [Phase 2](../phase2) · [Phase 3](../phase3) · **Phase 4**

**Question:** Phase 3's judge, a small local model, missed most failures that come down to comparing a
customer's number with a policy limit ("your 27 kg bag is within the 23 kg limit"). Does checking those
comparisons in plain code fix that without blocking good answers? And for what code can't check, does a
purpose-built judge model (TypeSafe's Jev 1.13) do better than a general one?

> **Status: done (2026-10-11).** Headline: on held-out answers, Jev 1.13 alone caught 80% of real
> failures and wrongly blocked 6% of good answers, against 62% and 32% for the best Phase 3 setup. It cost
> about 2 cents for all 600 answers and took about a quarter of a second each. The number check never
> blocked a good answer, but on top of Jev it caught nothing extra.

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

## Results

### Test: the number that counts

The 300 Phase 3 answers to 100 held-out questions: 61 unsupported, 175 supported, 64 refused (refusals
aren't guarded and are reported in Phase 3).

| Guard | Real failures caught | Good answers wrongly blocked |
| --- | ---: | ---: |
| Phase 3 best: citation repair + Qwen 2.5 7B judge | 38/61 (62%) | 56/175 (32%) |
| Number check alone (no model) | 17/61 (28%) | 0/175 (0%) |
| Citation repair + number check (no model) | 35/61 (57%) | 25/175 (14%) |
| Citation repair + number check + Qwen judge | 43/61 (70%) | 56/175 (32%) |
| **Jev judge alone** | **49/61 (80%)** | **10/175 (6%)** |
| Number check + Jev judge | 49/61 (80%) | 10/175 (6%) |
| Citation repair + number check + Jev judge | 54/61 (89%) | 32/175 (18%) |

By answering model, Jev alone: Llama 3.2 caught 12/13, wrongly blocked 2/45. Qwen 2.5 caught 24/30,
wrongly blocked 7/63. Gemma 2 caught 13/18, wrongly blocked 1/67.

Jev cost: $0.0223 for 612 calls (12 pilot, 600 scored), about $0.00004 per answer. Median latency 0.28
seconds. Zero unreadable replies.

### Dev: the Phase 2 answers

| Guard | Caught | Wrongly blocked |
| --- | ---: | ---: |
| Phase 3 best: repair + Qwen judge | 16/19 (84%) | 84/247 (34%) |
| Number check alone | 5/19 (26%) | 2/247 (1%) |
| Jev judge alone | 14/19 (74%) | 38/247 (15%) |
| Repair + number check + Jev judge | 17/19 (89%) | 52/247 (21%) |

Both of the number check's "wrong" blocks on dev were actually mislabeled answers from Phase 2: rule-made
labels the 20% review never sampled. One told a customer she'd need a medical certificate at 30 weeks
pregnant (the policy says after 36); the other invented "30 kg total per passenger." The Phase 2 labels
are left as published; they're noted here.

### What we found

1. **A purpose-built judge beat a general one by a wide margin.** Jev 1.13 caught more real failures than
   the best Phase 3 setup (80% vs 62%) while wrongly blocking about a fifth as many good answers (6% vs
   32%), at about $0.00004 and a quarter of a second per answer. The free local judge took about 39
   seconds per answer.
2. **The number check is safe but, here, redundant.** It never blocked a good answer on test, and added to
   the Phase 3 setup it lifted catches from 62% to 70% with no extra wrong blocks. But every threshold error
   it caught, Jev caught too, even though Jev's own guidance says to keep arithmetic in code. On these
   simple one-number comparisons that advice turned out to be cautious. The check still earns a place as a
   free, explainable backstop that can't be talked out of a wrong answer.
3. **The citation rules are now the expensive part.** Adding repaired citation rules on top of Jev caught 5
   more failures (89%) but tripled wrongly blocked answers (6% to 18%). Whether that's worth it depends on
   which costs more for the business: a made-up policy reaching a customer, or a good answer escalated to a
   person.
4. **Dev and test disagreed again, in the other direction.** Jev did better on the fresh test answers
   (80% / 6%) than on the Phase 2 answers (74% / 15%). With only 19 failures in dev, one split is too small
   to trust on its own; that's the reason for keeping a held-out test.

### Limits

- **Labels came from a model.** All test labels were made by Claude (an AI model) in Phase 3, at the
  author's request, before any judge ran. No person checked them.
- **Shared wording.** Jev's criteria use the same definitions of supported and unsupported as the labeling
  guide, as did the Phase 3 judge's prompt. That's fair between the two judges, but it may flatter both.
- **The number check was built after its author had read the test answers** while labeling them, though it
  was tuned on dev only and frozen before scoring test.
- **One run, one fictional airline, three small answering models.** Jev is a new, proprietary model; its
  results here are one independent data point, not a general verdict.
- The Jev prompt ([`jev_prompt.json`](jev_prompt.json)) was fixed before any Jev call and not tuned. The
  only change after the first attempt was plumbing: OpenRouter requires its decisions endpoint for Jev.
