# FF-01 Phase 5: how far have free models come?

[← FF-01 overview](..) · [Phase 1](../phase1) · [Phase 2](../phase2) · [Phase 3](../phase3) · [Phase 4](../phase4) · **Phase 5**

**Question:** the free judge in Phase 3 was a 2024 model (Qwen 2.5 7B). The best models are getting more
expensive to run, so how far have free models come? Do 2026 free models make better judges, and how close
do they get to Jev, the purpose-built judge from Phase 4?

> **Status: running.** Results will be added here when the runs finish.

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
