# Methods and vocabulary

Every experiment in this repository uses the same terms, so results from different projects mean the same thing.

| Term | Meaning |
| --- | --- |
| **Injected failure** | A failure introduced on purpose: a faulty answer written into a test, a forced model behavior, or a simulated outage. Measures what a guard catches, not how often failures happen. |
| **Detection recall** | Share of injected failures a guard catches. |
| **False-positive rate** | Share of valid answers or requests a guard wrongly blocks. |
| **Observed failure rate** | Share of failures arising on their own in a run with a real model. Only reported from real-model runs. |
| **Attack success rate** | Share of adversarial attempts that cause the prohibited outcome. |

## Phases

Failure Files and production patterns move through up to three phases:

1. **Fault injection.** Controlled tests of guard mechanics against failures we wrote. Cheap, deterministic, no model.
2. **Real models.** Guards and questions are **frozen first**, then run against real model outputs as a held-out test.
3. **What remains.** Experiments designed around what Phase 2 actually found, not around the Phase 1 failures we imagined.

Each write-up states which phase its numbers come from.
