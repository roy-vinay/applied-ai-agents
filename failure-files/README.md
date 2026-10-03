# Failure Files

Public AI incidents, turned into experiments.

Each Failure File takes a documented incident, reproduces the **failure mode** behind it in a fictional
system, adds mitigations one at a time, and measures what each one buys and costs.

## Method

1. **Source incident.** A short summary with links to reliable reporting.
2. **Failure mode.** The general class of failure, stated independently of the company involved.
3. **Fictional system.** A stand-in agent with invented data and invented policies.
4. **Test set.** Ordinary questions plus adversarial ones, so false refusals count as much as failures.
5. **Mitigations.** Added one at a time, never all at once, so each one's effect is visible.
6. **Results.** Failure rate, false refusals, latency, and cost for each step.

> **Disclaimer.** Each experiment reproduces the general failure mode described in public reporting. It does
> not reproduce, or make claims about, the organization's production architecture, prompts, models, or
> safeguards. All systems, data, and policies in this folder are fictional.

## Planned

| ID | Failure mode | Source incident |
| --- | --- | --- |
| FF-01 | Unsupported policy claims | An airline's website chatbot gave a customer incorrect information about bereavement fares, and a Canadian tribunal held the airline responsible (2024). [Law360 Canada](https://www.law360.ca/ca/articles/1804075) · [AI Incident Database](https://incidentdatabase.ai/reports/3673/) |
| FF-02 | Unauthorized commitments | Users prompted a car dealership's chatbot into "agreeing" to sell a vehicle for $1 (2023). [AI Incident Database](https://incidentdatabase.ai/entities/chevrolet-of-watsonville) |
| FF-03 | Behavioral policy violations | A parcel delivery company's chatbot was prompted into swearing and criticizing the company (2024). [AI Incident Database](https://incidentdatabase.ai/reports/3616) |
| FF-04 | High-stakes advice outside scope | A city government's business chatbot gave answers that would have broken the law (2024). [The Markup](https://themarkup.org/news/2024/03/29/nycs-ai-chatbot-tells-businesses-to-break-the-law) |

Status for each is tracked in the [roadmap](../ROADMAP.md).
