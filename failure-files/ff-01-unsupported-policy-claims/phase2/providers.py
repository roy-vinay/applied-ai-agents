"""Model providers behind one interface, so the experiment doesn't care which model answered.

Only local Ollama is implemented so far. Add hosted providers by implementing ModelProvider.
"""
from __future__ import annotations

import json
import time
import urllib.request
from dataclasses import dataclass


@dataclass
class ModelResponse:
    text: str
    input_tokens: int
    output_tokens: int
    latency_s: float
    truncated: bool = False


class ModelProvider:
    name: str

    def answer(self, system: str, user: str) -> ModelResponse:
        raise NotImplementedError


class OllamaProvider(ModelProvider):
    """A model running locally through Ollama (https://ollama.com). No API key, no cost per call."""

    MAX_TOKENS = 400  # same cap for every model; answers cut off by it are flagged as truncated

    def __init__(self, model: str, host: str = "http://localhost:11434"):
        self.model, self.host, self.name = model, host, f"ollama:{model}"

    def answer(self, system: str, user: str) -> ModelResponse:
        body = json.dumps({"model": self.model, "stream": False, "options": {"temperature": 0, "num_predict": self.MAX_TOKENS},
                           "messages": [{"role": "system", "content": system},
                                        {"role": "user", "content": user}]}).encode()
        req = urllib.request.Request(f"{self.host}/api/chat", data=body,
                                     headers={"Content-Type": "application/json"})
        last = None
        for attempt in range(3):
            t = time.monotonic()
            try:
                with urllib.request.urlopen(req, timeout=240) as r:
                    out = json.load(r)
                return ModelResponse(out["message"]["content"], out.get("prompt_eval_count", 0),
                                     out.get("eval_count", 0), round(time.monotonic() - t, 2),
                                     out.get("done_reason") == "length")
            except Exception as e:  # timeouts and dropped connections: wait and retry
                last = e
                time.sleep(5 * (attempt + 1))
        raise RuntimeError(f"{self.name} failed after 3 attempts: {last}")


def get_provider(spec: str) -> ModelProvider:
    kind, _, model = spec.partition(":")
    if kind == "ollama":
        return OllamaProvider(model)
    raise ValueError(f"unknown provider {kind!r}; implemented: ollama")
