# FF-01 Phase 3: a semantic check, tested on held-out answers

**Question:** Phase 2 found two problems with the rule-based guards on real models. They blocked many
correct answers because of sloppy citations, and every real failure they missed had the right numbers but
the wrong conclusion. Can citation repair fix the first, and a second model that checks meaning fix the
second, without trading one problem for the other?

> **Status: done (2026-10-10).** Headline: on held-out answers, citation repair plus a free local judge cut
> wrongly blocked answers from 52% to 32% while catching about as many real failures (62% vs 66%). Better,
> not solved. The judge looked much stronger on the data it was tuned on (84% caught) than on fresh data
> (62%), and it still missed most of the threshold errors it was built for.

## What's being compared

| Guard | What it does |
| --- | --- |
| Rules, frozen | The Phase 1 guard exactly as in Phase 2 |
| Rules + citation repair | Same idea (numbers must come from a real policy), after cleaning up how real models cite ([`repair.py`](repair.py)) |
| Judge only | A larger local model reads the question, all ten policies, and the answer, and decides whether the policies support what the answer says and concludes ([`judge.py`](judge.py), [`judge_prompt.txt`](judge_prompt.txt)) |
| Repair + judge | Block if either one blocks |

Every guard is scored on the same labels: **catch rate** (unsupported answers blocked) and **false
blocks** (supported answers blocked). Refusals are reported next to them, so no setup can look good by
making the assistant say no.

## Protocol

- **Two splits, so the result isn't graded on its own homework.**
  - *Dev:* the 300 Phase 2 answers, already labeled. The repair and the judge prompt are built and tuned
    here.
  - *Test:* 100 new questions ([`questions_test.json`](questions_test.json)), same mix as Phase 2 (40
    answerable, 20 no policy covers, 15 leading, 15 false premise, 10 requests to bend a policy), none
    repeated. The same three models answer them with the same frozen prompt.
- **Two freezes.** [`FREEZE_test.json`](FREEZE_test.json) locks the test questions, prompt, policies, and
  guards before any model answered them. `FREEZE_judge.json` will lock the judge and the repair after dev
  tuning and before the judge sees a single test answer. Scripts refuse to run if a frozen file changed.
- **Label before judging.** Test answers are labeled before the judge runs on them, so the labels can't
  lean toward the judge.
- **Judge model:** Qwen 2.5 7B, run locally, temperature 0, JSON output. It fails closed: an unreadable
  verdict counts as a block. It shares a family with one of the answering models (Qwen 2.5 3B), so results
  are also reported per answering model.
- **Free.** Everything runs on free GitHub runners through Ollama ([workflow](../../../.github/workflows/ff01-phase3.yml)).

## Choosing the judge prompt (decided before version 3 ran)

The judge is a small local model, and its behavior swung hard with wording. To avoid tuning on 19
dev failures until something looks good, the rule was fixed before the last attempt: **at most three
prompt versions; freeze the one with the highest catch rate minus false-block rate for "Repair + judge"
on dev.** Every version's prompt and dev results are kept in this folder.

## Results

### Test: the number that counts

300 fresh answers to 100 new questions, labeled before the judge saw them: 61 unsupported, 175 supported,
64 refused. The judge and the repair were frozen before this run.

| Guard | Real failures caught | Good answers wrongly blocked |
| --- | ---: | ---: |
| Rules, frozen (Phase 2) | 40/61 (66%) | 91/175 (52%) |
| Rules + citation repair | 22/61 (36%) | 25/175 (14%) |
| Judge only | 27/61 (44%) | 36/175 (21%) |
| **Repair + judge** | **38/61 (62%)** | **56/175 (32%)** |

By answering model (repair + judge): Llama 3.2 caught 10/13, wrongly blocked 9/45. Qwen 2.5 caught 17/30,
wrongly blocked 23/63. Gemma 2 caught 11/18, wrongly blocked 24/67.

Judge cost: $0. Judge latency: median 39 seconds per answer on a free CPU-only runner.

### Dev: what the same setups did on the Phase 2 answers

| Guard | Caught | Wrongly blocked |
| --- | ---: | ---: |
| Rules, frozen | 14/19 (74%) | 131/247 (53%) |
| Rules + citation repair | 10/19 (53%) | 16/247 (6%) |
| Judge only (v3) | 8/19 (42%) | 72/247 (29%) |
| Repair + judge (v3) | 16/19 (84%) | 84/247 (34%) |

The three judge prompts on dev, each combined with repair: v1 caught 95% and wrongly blocked 69%; v2
caught 58% and wrongly blocked 14%; v3 caught 84% and wrongly blocked 34%. v3 won under the rule set in
advance (catch rate minus false-block rate: 25.5, 43.7, 50.2).

### What we found

1. **Better, not solved.** The best setup kept about the same catch rate as the frozen rules (62% vs 66%)
   and cut wrongly blocked answers from about half to about a third. That's real progress, and it still
   means one good answer in three gets stopped and more than a third of real failures get through.
2. **The data you tune on flatters you.** The same frozen judge caught 84% of failures on the Phase 2
   answers and 62% on fresh ones. We picked it by a rule fixed in advance, and it still dropped by more
   than 20 points, because 19 dev failures were too few to tune on. Any guard tested only on the examples
   it was built with should be assumed to be overstated.
3. **A small judge is steered by wording, not understanding.** Three prompts for the same 7B model moved
   it from catching almost everything while blocking most good answers, to blocking little while catching
   little. Asking it to fill in fixed fields and letting code make the call worked best, but the judge's
   operating point was set by how we phrased the question.
4. **It missed the failures it was built for.** 13 of the 23 false-premise and bend-the-rule failures got
   through: "your 27 kg bag is within the 23 kg limit", "exactly 8 kg meets an under-8 kg limit", "yes,
   exactly 3 hours gets the credit". Comparing a customer's number to a policy limit is arithmetic, and a
   small model doing it in prose gets it wrong often.
5. **Citation repair is the cheap, reliable part.** It held up best from dev to test on precision (6% to
   14% wrongly blocked, against 53% for the frozen rules) and costs nothing at runtime. On its own it
   catches too little.
6. **Refusals didn't go away.** 64 of 300 test answers refused a question the policies answer, 42 of them
   from Llama 3.2. A guard can't fix an assistant that won't answer; that has to be measured separately,
   and it was.
7. **A free judge is an audit tool, not a live guard.** At about 39 seconds per answer on a CPU, it can
   review yesterday's conversations, not stand in front of a customer.

### What this points to next

Split the work by what each part is good at. Pull the customer's numbers and the policy's limits out
deterministically and compare them in code; that targets the threshold errors directly and costs nothing.
Keep the model judge for meaning (agreeing with a false claim, inventing an option), and test whether a
larger hosted judge, added through the same provider interface, closes the gap, with cost and latency
reported next to it.

### Labels and limits

- Test labels were made by Claude (an AI model), at the author's request, for all 300 answers, before the
  judge ran. Every label is marked `"source": "claude_review"` with the rule label and a one-line reason.
  Labeling rules were the same as Phase 2.
- The judge and the labeler are both models; the labels were not checked by a person.
- The judge (Qwen 2.5 7B) shares a family with one answering model (Qwen 2.5 3B). Its catch rate on Qwen's
  answers was the lowest of the three (57%), so there's no sign it favored its own family, but the sample
  is small.
- The test set produced far more failures (61) than dev (19). Its questions lean harder on arithmetic
  against limits, so dev and test are not the same difficulty.
- Small models, one run each at temperature 0, one fictional airline. Treat rates as directional.
