# FF-01 Phase 3: a semantic check, tested on held-out answers

**Question:** Phase 2 found two problems with the rule-based guards on real models. They blocked many
correct answers because of sloppy citations, and every real failure they missed had the right numbers but
the wrong conclusion. Can citation repair fix the first, and a second model that checks meaning fix the
second, without trading one problem for the other?

> **Status: building.** Test questions frozen 2026-10-10. Results will be added here when the runs finish.

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

## Dev notes so far

Citation repair on the Phase 2 answers: false blocks went from 131 of 247 correct answers to 16 (53% to
6%, back near Phase 1's 7%), while catches went from 14 of 19 to 10. Rules can check numbers; they can't
tell "not 50%" from "yes, 50%". The judge has to cover that.
