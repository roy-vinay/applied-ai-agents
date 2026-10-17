# Applied AI Agents

[![evals](https://github.com/roy-vinay/applied-ai-agents/actions/workflows/evals.yml/badge.svg)](https://github.com/roy-vinay/applied-ai-agents/actions/workflows/evals.yml)

Applied AI projects, with explicit safeguards, evaluations, and trade-offs.

Each project starts from a real problem, builds the smallest version that works, tests the behavior that
matters, and writes down what was traded away. Results come with their method and caveats, and claims stop
where the evidence does.

**Start here**

- **Build and evaluate agents:** [run the guarded support agent](#build-and-evaluate-agents) in under a minute, no API key needed.
- **Explore failure experiments:** [Failure Files](#explore-failure-experiments), public AI incidents reproduced and mitigations measured.
- **Try the tools:** [Tech60 and mdEditDiff](#try-the-tools), two Mac apps.
- **Read the reasoning:** [decisions and roadmap](#read-the-decisions-and-roadmap).

## Build and evaluate agents

The fastest start needs no API key and no dependencies:

```bash
git clone https://github.com/roy-vinay/applied-ai-agents
cd applied-ai-agents/production-patterns/guarded-support-agent
python demo.py               # four scenarios with the full tool trace
python -m evals.run_evals    # 12 trajectory evals, the same suite CI runs
```

### Production patterns

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

### Agents

| Project | What it does | Stack |
| --- | --- | --- |
| [MCP chat](agents/mcp-chat) | Terminal chat app showing the Model Context Protocol end to end: an MCP client and server over stdio, with @document mentions and /commands. | Python, MCP |

## Explore failure experiments

**Failure Files** take a documented public AI incident, reproduce the failure mode in a fictional system, and
measure mitigations one at a time. Every file uses the shared terms in [METHODS.md](METHODS.md).
[All files](failure-files).

**[FF-01: Can you stop a support chatbot from making up policy?](failure-files/ff-01-unsupported-policy-claims)**
The failure behind the 2024 Air Canada chatbot case, tested in four phases. Rules alone either missed too
much or blocked too many good answers; a small model built for yes/no decisions caught 80% of real
failures and wrongly blocked 6%, for about 2 cents across 600 answers.

**[FF-05: What does telling an AI agent the rules actually buy you?](failure-files/ff-05-rules-in-the-prompt)**
The lesson of the 2025 Replit database deletion, tested on a data bot. Without its rules, the larger model
handed over customer emails on every try; with them, no model broke one.

## Try the tools

Two free, open-source Mac apps. Both are early.

**[Tech60](tools/tech60)**: a tech news front page for the Mac desktop. It shows only stories with signal
(several outlets, a Techmeme pick, or the company's own post) and gives each a short summary from Apple's
on-device model. Rule-based checks withhold a summary whose numbers or names don't appear in the source, or
whose sentences don't overlap a source sentence. Those checks catch some errors, not all; the accuracy
evaluation hasn't been run yet. [Download for Mac](https://github.com/roy-vinay/applied-ai-agents/releases/download/tech60-latest/Tech60-macOS.zip)
(macOS 14 or later), or [read how it works](tools/tech60).

**[mdEditDiff](https://github.com/roy-vinay/mdeditdiff)**: an editor for people and a diff for agents. Agents
ask what changed in a shared Markdown file since they last looked and get back only the changed parts; people
get a native Mac app for reading and editing Markdown. It lives in
[its own repository](https://github.com/roy-vinay/mdeditdiff), with the app, CLI, and MCP server.

## Read the decisions and roadmap

The reasoning behind the builds lives in **[ai-decision-log](https://github.com/roy-vinay/ai-decision-log)**:
one-page memos on applied AI product choices, with the numbers, the decision, and what would change it.
Start with [D-002: How many evals are enough?](https://github.com/roy-vinay/ai-decision-log/blob/main/decisions/D-002-how-many-evals-are-enough.md).

What's shipped, what's next, and the hypothesis behind each: [ROADMAP.md](ROADMAP.md).

## About

Built by [Vinay Roy](https://github.com/roy-vinay). VP of Product at [Burq.ai](https://burq.ai), leading Product, Design and AI.

Before Burq, I was the founding product leader at an AI SaaS startup, taking it from zero to product-market fit and building multi-agent systems in production. Before that, I led a global team of about 80 across Product, Data Science and Analytics at Vista, the private aviation group behind VistaJet and XO.<br>
Earlier: marketplace growth at Zeus Living, macOS and iOS features at Apple (including Sidecar), and engineering teams at Qualcomm and NVIDIA.

For seven years I was Head Instructor for the AI/ML executive program at UC Berkeley Executive Education, teaching more than 10,000 business leaders. 3 US patents, MBA from Berkeley Haas, MS from IIT Roorkee.

San Jose, CA · [LinkedIn](https://www.linkedin.com/in/royvinay)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/roy-vinay/roy-vinay/main/dark_mode.svg">
  <img alt="ASCII portrait of Vinay Roy. VP of Product at Burq.ai; builds AI, agents, evals and decision systems." src="https://raw.githubusercontent.com/roy-vinay/roy-vinay/main/light_mode.svg" width="985">
</picture>

## License

MIT, unless a project folder says otherwise.
