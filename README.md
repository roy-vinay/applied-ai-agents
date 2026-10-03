# Applied AI Agents

[![evals](https://github.com/roy-vinay/applied-ai-agents/actions/workflows/evals.yml/badge.svg)](https://github.com/roy-vinay/applied-ai-agents/actions/workflows/evals.yml)

Working AI agents for real business problems, each with the guardrails and evals that make it
trustworthy, and the product decision behind it written down.

Every project here starts the same way: a real problem, the smallest version that works, evals on the
behavior that matters, then a write-up of the trade-offs. Clone any folder, run it, and pull it apart.

## Run one now

The fastest start needs no API key and no dependencies:

```bash
git clone https://github.com/roy-vinay/applied-ai-agents
cd applied-ai-agents/production-patterns/guarded-support-agent
python demo.py               # four scenarios with the full tool trace
python -m evals.run_evals    # 12 trajectory evals, the same suite CI runs
```

## Production patterns

The parts that keep an agent safe once real users and real money are involved.

| Project | What it shows | Stack |
| --- | --- | --- |
| [Guarded support agent](production-patterns/guarded-support-agent) | Authorization in code, retries with backoff, step and token budgets, idempotent writes, PII redaction, prompt-injection screening, 12 trajectory evals, and a fault-injection benchmark, all in CI. Companion to [Building AI Agents That Survive Production](https://vinaysays.medium.com/building-ai-agents-that-survive-production-5bbb2257ba0a). | Python, no dependencies |

**What the guards prevent** under fault injection, 100 randomized trials per row, same agent with guards off vs on
([method and caveats](production-patterns/guarded-support-agent#what-the-guards-actually-prevent)):

| Outcome | How it arises | Guards off | Guards on |
| --- | --- | ---: | ---: |
| Duplicate payment after a lost response | Injected environment fault | 79/100 | 0/100 |
| Refund paid on another customer's order | Input: customer names any order | 47/100 | 0/100 |
| Refund over $50 paid without approval | Input: any eligible order | 25/100 | 0/100 |
| Payment made after an injection attempt (attack success) | Adversarial input | 68/100 | 18/100 |
| Card number shown back to the customer | Injected model failure, every trial | 100/100 | 0/100 |
| System prompt revealed | Injected model failure, every trial | 100/100 | 0/100 |
| Turn ran past 8 model calls | Injected model failure, every trial | 100/100 | 0/100 |
| Legitimate refund wrongly blocked (false positive) | Ordinary requests | 0/100 | 0/100 |

## Agents

| Project | What it does | Live | Stack |
| --- | --- | --- | --- |
| [School front desk](agents/school-front-desk) | Answers parents' policy questions with citations, escalates anything sensitive, and gives staff a console to see what's being asked. Bilingual, with LLM-judged evals. | [Demo](https://berryessa-ai-front-desk-unofficial.vercel.app) | Next.js, Claude |
| [MCP chat](agents/mcp-chat) | Terminal chat app showing the Model Context Protocol end to end: an MCP client and server over stdio, with @document mentions and /commands. | | Python, MCP |

## Failure Files

Case studies with experiments: a documented public AI incident, the failure mode behind it reproduced in a
fictional system, and mitigations measured one at a time. [All files and method](failure-files).

**[FF-01: Unsupported policy claims](failure-files/ff-01-unsupported-policy-claims)**, the failure behind
the 2024 Air Canada chatbot case. Phase 1 (fault injection, no model yet): rule-based guards caught 79% of
deliberately injected failures, with a 7% false-positive rate. The finding that matters: a cited answer is
not a grounded answer, and most failures the rules miss are wrong in meaning, not in form. Phase 2 (three
real open models, guards frozen): recall held at 74%, false positives rose to as high as 57%, and every
miss was a wrong conclusion with the right numbers. Phase 3 adds a semantic verifier.

## Decisions

The reasoning behind the builds lives in **[ai-decision-log](https://github.com/roy-vinay/ai-decision-log)**:
one-page memos on applied AI product choices, with the numbers, the decision, and what would change it.
Start with [D-002: How many evals are enough?](https://github.com/roy-vinay/ai-decision-log/blob/main/decisions/D-002-how-many-evals-are-enough.md).

## Roadmap

What's shipped, what's next, and the hypothesis behind each: [ROADMAP.md](ROADMAP.md).

## About

Built by [Vinay Roy](https://github.com/roy-vinay), VP of Product at [Burq.ai](https://burq.ai). Head Instructor for the
AI/ML executive program at UC Berkeley Executive Education for seven years, teaching 10,000+ leaders. Writing on
[Medium](https://vinaysays.medium.com) and [Substack](https://vinayroy.substack.com).

## License

MIT, unless a project folder says otherwise.
