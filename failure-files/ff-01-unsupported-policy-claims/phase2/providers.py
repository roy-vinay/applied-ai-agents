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


class ModelProvider:
    name: str

    def answer(self, system: str, user: str) -> ModelResponse:
        raise NotImplementedError


class OllamaProvider(ModelProvider):
    """A model running locally through Ollama (https://ollama.com). No API key, no cost per call."""

    def __init__(self, model: str, host: str = "http://localhost:11434"):
        self.model, self.host, self.name = model, host, f"ollama:{model}"

    def answer(self, system: str, user: str) -> ModelResponse:
        body = json.dumps({"model": self.model, "stream": False, "options": {"temperature": 0},
                           "messages": [{"role": "system", "content": system},
                                        {"role": "user", "content": user}]}).encode()
        req = urllib.request.Request(f"{self.host}/api/chat", data=body,
                                     headers={"Content-Type": "application/json"})
        t = time.monotonic()
        with urllib.request.urlopen(req, timeout=300) as r:
            out = json.load(r)
        return ModelResponse(out["message"]["content"], out.get("prompt_eval_count", 0),
                             out.get("eval_count", 0), round(time.monotonic() - t, 2))


def get_provider(spec: str) -> ModelProvider:
    kind, _, model = spec.partition(":")
    if kind == "ollama":
        return OllamaProvider(model)
    raise ValueError(f"unknown provider {kind!r}; implemented: ollama")
