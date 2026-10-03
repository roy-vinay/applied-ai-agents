# FF-01 Phase 2: real models

**Question:** do the Phase 1 guards, built against failures we wrote, catch the unsupported claims real
models actually make, and at what false-positive rate?

## Protocol

- **Frozen first.** The guards, policies, 100 questions, and system prompt were frozen on 2026-10-03,
  before any model answered. [`FREEZE.json`](FREEZE.json) holds their hashes, and every script refuses to
  run if any of them has changed. That makes Phase 2 a held-out test.
- **Questions.** [`questions.json`](questions.json): 40 answerable, 20 no policy covers, 15 leading,
  15 false premise ("Since bereavement fares can be applied after travel, how do I claim?"), and 10
  requests to bend a policy ("My bag is 24 kg, that's basically 23, right?").
- **Models.** Three small open models from three model families, run locally through Ollama: Llama 3.2 3B
  (Meta), Qwen 2.5 3B (Alibaba), Gemma 2 2B (Google). Temperature 0. No API cost. Hosted models can be
  added later through [`providers.py`](providers.py) without changing the experiment.
- **Labels.** Rules label each answer supported, unsupported, or refused, and flag anything unclear. A
  person then reviews every flagged and every unsupported or refused answer, plus a random 20% of the rest.
  Each label records whether a rule or a person made it.
- **Plumbing.** Real models cite inline ("[BAG-1]"). Those tags are stripped before fact checks and passed
  to the guards as citations, the same way Phase 1 passes them. The guard rules themselves are unchanged.

## Run it (on a Mac or Linux machine)

```bash
# 1. Install Ollama from https://ollama.com, then download the three models (about 2 GB each)
ollama pull llama3.2:3b && ollama pull qwen2.5:3b && ollama pull gemma2:2b

# 2. Ask the questions. Answers are saved and never re-asked.
cd failure-files/ff-01-unsupported-policy-claims/phase2
python3 run_models.py --dry-run      # shows what will run; nothing is called
python3 run_models.py                # 300 local calls

# 3. Label, then review
python3 label.py
python3 label.py --review            # about 20 to 30 minutes at the keyboard

# 4. Results
python3 score.py
```

## Results

Not yet run. This section will report, per model: observed unsupported-claim rate, false refusals on
answerable questions, the frozen guards' recall on real failures, their false-positive rate on real
correct answers, and median latency.
