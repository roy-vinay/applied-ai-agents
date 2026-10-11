# FF-01 Phase 5: how far have free models come?

[← FF-01 overview](..) · [Phase 1](../phase1) · [Phase 2](../phase2) · [Phase 3](../phase3) · [Phase 4](../phase4) · **Phase 5**

**Question:** the free judge in Phase 3 was a 2024 model (Qwen 2.5 7B). The best models are getting more
expensive to run, so how far have free models come? Do 2026 free models make better judges, and how close
do they get to Jev, the purpose-built judge from Phase 4?

> **Status: the six local judges are done; the three hosted judges are pending.** OpenRouter's free
> versions allow 50 requests a day, and each judge needs 300, so those runs are on hold.

**In short:** the best 2026 free judge, Gemma 4 12B, caught 70% of failures and wrongly blocked 7% of good
answers. That beats the 2024 free judge from Phase 3 on both numbers (44% and 21%), and comes within 10
points of Jev on failures caught, at about the same rate of good answers blocked. The catch is speed: about
80 seconds per answer on a free runner, against a quarter of a second for Jev.

## The judges

| Judge | Maker | Size | How it runs, at $0 |
| --- | --- | --- | --- |
| Gemma 4 12B | Google | 12B | Locally, free GitHub runner |
| Gemma 4 E4B | Google | about 4.5B | Locally, free GitHub runner |
| Qwen 3.5 9B | Alibaba | 9B | Locally, free GitHub runner |
| Phi-4-mini | Microsoft | 3.8B | Locally, free GitHub runner |
| Phi-4 | Microsoft | 14B | Locally, free GitHub runner |
| Ministral 3 3B | Mistral | 3B | Locally, free GitHub runner |
| Gemma 4 31B | Google | 31B | OpenRouter's free version |
| Nemotron 3 Super | NVIDIA | 120B (12B active) | OpenRouter's free version |
| Nemotron 3 Ultra | NVIDIA | 550B (55B active) | OpenRouter's free version |

Local judges must fit a free runner (no graphics card, 16 GB of memory), so about 14B parameters at most.
The three large models are too big for that, so they run through OpenRouter's free versions, which cost
nothing but limit requests per day. The plan named gpt-oss-120b and Llama 3.3 70B, but neither had a free
version on OpenRouter on October 11, 2026, so the largest free general models listed that day replace them.

## Results

All judges read the same 300 test answers (61 that state unsupported policy, 175 supported, 64 refusals).

| Judge | Model | Failures caught | Good answers wrongly blocked | With number check: caught / wrongly blocked | Median time per answer | Unreadable replies |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| qwen2.5-7b (Phase 3) | ollama:qwen2.5:7b | 27/61 (44%) | 36/175 (21%) | 54% / 21% | 39.2 s | 0 |
| jev-1.13 (Phase 4) | typesafe/jev-1.13 | 49/61 (80%) | 10/175 (6%) | 80% / 6% | 0.3 s | 0 |
| gemma4-12b | gemma4:12b | 43/61 (70%) | 12/175 (7%) | 72% / 7% | 81.1 s | 0 |
| gemma4-e4b | gemma4:e4b | 31/61 (51%) | 11/175 (6%) | 56% / 6% | 31.6 s | 0 |
| qwen3.5-9b | qwen3.5:9b | 35/61 (57%) | 13/175 (7%) | 66% / 7% | 52.6 s | 0 |
| phi4-mini | phi4-mini:3.8b | 35/61 (57%) | 86/175 (49%) | 70% / 49% | 24.9 s | 0 |
| phi4-14b | phi4:14b | 33/61 (54%) | 8/175 (5%) | 57% / 5% | 86.6 s | 0 |
| ministral3-3b | ministral-3:3b | 39/61 (64%) | 68/175 (39%) | 72% / 39% | 17.9 s | 1 |

What stands out:

- **Free judges have come a long way.** Four of the six 2026 models wrongly blocked 7% of good answers or
  less, a third of the 2024 judge's rate, and all six caught more failures.
- **Smaller isn't always worse, but the smallest ones over-block.** Phi-4-mini and Ministral 3 3B caught a
  lot by blocking a lot: 49% and 39% of good answers. Gemma 4 E4B, at a similar size, blocked only 6%.
- **Jev still leads,** catching 10 points more than the best free judge and answering about 300 times
  faster.
- **The number check helps the free judges more than it helped Jev.** It added up to 13 points of caught
  failures without blocking a single extra good answer.

Gemma 4 12B needed three attempts on the free runners: the first ran out of memory, and the second lost
6 answers to a crashed job. After a context-length limit and a retry, all 300 answers were judged, with no
crashes recorded.

## Protocol

- **Same answers, same labels.** Every judge reads the 300 Phase 3 test answers, already labeled, so
  results line up with Phases 3 and 4.
- **Same frozen instructions.** Every judge gets the exact Phase 3 prompt
  ([`../phase3/judge_prompt.txt`](../phase3/judge_prompt.txt)), with no tuning for any model, and its
  reply is turned into a verdict by the same rule ([`decide.py`](decide.py)).
  [`check_decide.py`](check_decide.py) proves that rule reproduces all 300 Phase 3 verdicts.
- **Thinking turned off** where a model supports it, so every judge answers in one pass.
- **Free only.** Hosted runs stop if OpenRouter reports any cost.
- **Reported for each judge:** failures caught, good answers wrongly blocked, both again with the Phase 4
  number check added, median time per answer, and unreadable replies (which count as blocks).
