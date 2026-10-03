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
| [Guarded support agent](production-patterns/guarded-support-agent) | Authorization in code, retries with backoff, step and token budgets, idempotent writes, PII redaction, prompt-injection screening, and 12 trajectory evals in CI. Companion to [Building AI Agents That Survive Production](https://vinaysays.medium.com/building-ai-agents-that-survive-production-5bbb2257ba0a). | Python, no dependencies |

## Agents

| Project | What it does | Live | Stack |
| --- | --- | --- | --- |
| [School front desk](agents/school-front-desk) | Answers parents' policy questions with citations, escalates anything sensitive, and gives staff a console to see what's being asked. Bilingual, with LLM-judged evals. | [Demo](https://berryessa-ai-front-desk-unofficial.vercel.app) | Next.js, Claude |
| [MCP chat](agents/mcp-chat) | Terminal chat app showing the Model Context Protocol end to end: an MCP client and server over stdio, with @document mentions and /commands. | | Python, MCP |

## Decisions

The reasoning behind the builds lives in **[ai-decision-log](https://github.com/roy-vinay/ai-decision-log)**:
one-page memos on applied AI product choices, with the numbers, the decision, and what would change it.
Start with [D-001: Rules, LLM, or hybrid for delivery provider selection](https://github.com/roy-vinay/ai-decision-log/blob/main/decisions/D-001-provider-selection-rules-llm-hybrid.md).

## About

Built by [Vinay Roy](https://github.com/roy-vinay), VP of Product at [Burq.ai](https://burq.ai). Head Instructor for the
AI/ML executive program at UC Berkeley Executive Education for seven years, teaching 10,000+ leaders. Writing on
[Medium](https://vinaysays.medium.com) and [Substack](https://vinayroy.substack.com).

## License

MIT, unless a project folder says otherwise.
