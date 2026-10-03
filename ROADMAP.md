# Roadmap

Each item is an experiment, not a feature. It states a hypothesis, measures it, and reports the result,
including when the result is unflattering. Where it applies, every experiment measures four things:
**failure rate, false refusals, latency, and cost.**

Statuses: **Shipped** · **Building** · **Next** · **Exploring**. Only a few items are ever marked Next.

## Production patterns

| ID | Experiment | Hypothesis | Measures | Status |
| --- | --- | --- | --- | --- |
| P-01 | [Guarded tool use](production-patterns/guarded-support-agent) | Authorization in code, idempotency, budgets, and output filtering contain failures the model will eventually make | Harmful outcomes per 100 trials, guards off vs on; wrongly blocked requests | Shipped |
| P-02 | Injection defense | Combining deterministic rules with a semantic classifier reduces successful attacks without excessive false positives | Attack success rate, false positives, latency, cost | Next |
| P-03 | Agent replay | Replaying logged conversations against a candidate prompt or model catches behavioral regressions that answer-level tests miss | Regressions found, improvements found, runtime, cost | Next |
| P-04 | Structured outputs at agent boundaries | Schema-constrained output with validation and retry beats free-text parsing for tool arguments and system handoffs | Schema validity, semantic correctness, retries, latency, cost | Exploring |
| P-05 | Model routing | A router can predict when the larger model is needed, keeping most of its quality at a fraction of its cost | Quality, failure rate, cost, latency for small-only, large-only, and routed | Exploring |
| P-06 | Escalation under uncertainty in customer support | Explicit cost assumptions make the trade-off between missed and unnecessary escalations tunable | Missed escalations, unnecessary escalations, cost per conversation | Exploring |

## Failure Files

Each reproduces the **failure mode** behind a public incident in a fictional system, then tests mitigations.
See [failure-files/](failure-files) for method and sources.

| ID | Failure mode | Hypothesis | Measures | Status |
| --- | --- | --- | --- | --- |
| [FF-01](failure-files/ff-01-unsupported-policy-claims) | Unsupported policy claims | Requiring retrieved, cited policy, and validating the citation, sharply reduces invented policies | Unsupported claims, false refusals, latency, cost | Shipped (rule layers) |
| FF-01b | Unsupported policy claims: semantic check | A model-based support check catches the claims rule layers can't verify, at an acceptable cost | Unsupported claims, false refusals, latency, cost | Next |
| FF-02 | Unauthorized commitments | Enforcing offer and price limits in code prevents binding commitments that prompt-level rules miss | Out-of-policy commitments under attack prompts, false blocks | Exploring |
| FF-03 | Behavioral policy violations | A separate output policy check catches tone and brand violations the main prompt lets through | Violating replies under adversarial prompts, false blocks | Exploring |
| FF-04 | High-stakes advice outside scope | A scope guard prevents regulatory and legal advice without refusing ordinary questions | Out-of-scope advice given, legitimate questions refused | Exploring |

## Benchmarks

| ID | Experiment | Hypothesis | Measures | Status |
| --- | --- | --- | --- | --- |
| B-01 | Production-agent benchmark | The same guards change outcomes differently across models | All P and FF measures, per model | Exploring |

B-01 results will describe performance on this repository's scenarios only. They are not a general model ranking.
