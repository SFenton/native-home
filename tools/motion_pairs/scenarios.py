"""Scenarios: the paired action sequences a recording replays on each side, and the events they should produce.

A scenario launches both apps in fixtures mode (reference ``--gallery-fixture`` on a gallery page, native ``--server-ui-preview``),
then runs ``steps``: each presses one element and waits for the motion to settle. A step that names an ``event`` makes the
analysis look for one motion burst in order. ``transitions.json`` rows point at a scenario and an event name.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Mapping, Optional

from .progress import EventConfig, Roi

REFERENCE = "reference"
NATIVE = "native"
SIDES = (REFERENCE, NATIVE)


@dataclass
class Step:
    """Press ``press`` (an agent-device selector, one string for both sides or one per side) and wait ``wait_ms``."""
    press: object
    wait_ms: int = 1600
    event: Optional[str] = None
    onset_threshold: float = 1.0
    min_frames: int = 10
    roi: Optional[Roi] = None

    def selector(self, side: str) -> str:
        return self.press[side] if isinstance(self.press, Mapping) else str(self.press)

    def config(self) -> Optional[EventConfig]:
        return EventConfig(self.event, self.onset_threshold, self.min_frames, self.roi) if self.event else None


@dataclass
class Scenario:
    """``gallery_page`` is the reference's gallery page; ``native_prepare`` the labels pressed to reach the same screen on
    native in preview mode (it opens on its tab bar); ``lead_ms`` the quiet time before the first press."""
    id: str
    title: str
    gallery_page: str
    steps: List[Step]
    native_prepare: List[str] = field(default_factory=list)
    lead_ms: int = 1000
    #: ``preview`` launches native with ``--server-ui-preview`` (the publication fixtures); ``gallery`` with ``--gallery-fixture``
    #: on the same ``gallery_page`` as the reference (a component page both apps draw from the same UIKit components).
    native_mode: str = "preview"
    #: Extra launch environment for both sides (names only; passed as ``SIMCTL_CHILD_<name>``).
    env: Dict[str, str] = field(default_factory=dict)

    def events(self) -> List[EventConfig]:
        return [c for c in (s.config() for s in self.steps) if c]

    def event_steps(self) -> List[int]:
        """The index of the step (and so of the tap in the recording's gesture telemetry) behind each event."""
        return [i for i, s in enumerate(self.steps) if s.event]

    def sequence_ms(self) -> int:
        return self.lead_ms + sum(s.wait_ms for s in self.steps)


SCENARIOS: Dict[str, Scenario] = {}


def register(scenario: Scenario) -> Scenario:
    SCENARIOS[scenario.id] = scenario
    return scenario
