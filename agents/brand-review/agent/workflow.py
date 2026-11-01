"""Campaign lifecycle as an explicit state machine.

At any moment exactly one party holds a campaign: the marketer, a reviewer, the agent,
or the clock. Illegal moves raise instead of happening quietly, and every move is logged.
"""
from __future__ import annotations

from dataclasses import dataclass, field

STAGES = ("brief", "plan", "create", "review", "approved", "live")

# (from, to): who is allowed to make the move
TRANSITIONS = {
    ("brief", "plan"): {"agent"},
    ("plan", "create"): {"marketer"},          # the marketer approves the plan
    ("create", "create"): {"agent"},           # self-check failed, agent fixes
    ("create", "review"): {"marketer"},        # only a person sends, and only if nothing blocks
    ("review", "create"): {"reviewer"},        # change requested
    ("review", "approved"): {"reviewer"},      # last required reviewer approves
    ("approved", "live"): {"marketer"},        # publishing always waits for a person
}


class IllegalMove(Exception):
    pass


@dataclass
class Campaign:
    name: str
    stage: str = "brief"
    holder: str = "agent"
    rounds: int = 0
    log: list = field(default_factory=list)

    def move(self, to: str, actor: str, note: str = "", blocked: bool = False) -> None:
        allowed = TRANSITIONS.get((self.stage, to))
        if allowed is None:
            raise IllegalMove(f"{self.stage} -> {to} is not a valid move")
        if actor not in allowed:
            raise IllegalMove(f"{actor} cannot move {self.stage} -> {to}; needs {sorted(allowed)}")
        if to == "review" and blocked:
            raise IllegalMove("a required rule is failing; it can't be sent for review")
        if to == "review":
            self.rounds += 1
        self.log.append((self.stage, to, actor, note))
        self.stage = to
        self.holder = {"plan": "marketer", "create": "agent", "review": "reviewer",
                       "approved": "marketer", "live": "nobody"}.get(to, "agent")
