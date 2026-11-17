"""Recording takes on both sides, in parallel, gated on host load.

Each side has its own simulator and its own bound ``agent-device`` (the dispatching agent supplies the commands from
``device_open``; ``standalone_agent`` builds the standalone form the spike used when none was given). A take is: relaunch the
app (Reduce Motion set explicitly, the setting belongs to the simulator), reach the starting screen, ``record start
--hide-touches`` (without it the clip is re-rendered at 30 fps), run the scenario's steps, ``record stop``. A take is refused
when the 1-minute load average is at or over the limit, and discarded (class ``infra``) when the recording ran longer than the
sequence needs (the spike's 54 s run).
"""

from __future__ import annotations

import glob
import json
import os
import shlex
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Mapping, Optional

from tools.parity_loop import launch as pl_launch
from tools.parity_loop import simguard
from tools.parity_loop.capture import Agent
from tools.parity_loop.common import BUNDLE_ID, Runner, run

from .scenarios import NATIVE, REFERENCE, Scenario

LOAD_LIMIT = 40.0
#: Slack past the sequence length before a recording counts as a runaway (recorder export stalls).
OVERRUN_MS = 4000
#: Each press costs the agent a round trip on top of the scenario's own wait (measured 0.4 to 0.7 s on a quiet host).
PRESS_MS = 1500
ROOT = Path(__file__).resolve().parent.parent.parent


class LoadTooHigh(Exception):
    """The 1-minute load average is at or over the limit: no recording starts."""


def load_1min() -> float:
    return os.getloadavg()[0]


def gate_on_load(limit: float = LOAD_LIMIT, load: Callable[[], float] = load_1min, wait_s: float = 0.0,
                 sleep: Callable[[float], None] = time.sleep) -> float:
    """The 1-minute load, or :class:`LoadTooHigh` when it stays at or over ``limit`` for ``wait_s`` seconds (checked every 10 s)."""
    waited = 0.0
    value = load()
    while value >= limit and waited < wait_s:
        sleep(10)
        waited += 10
        value = load()
    if value >= limit:
        raise LoadTooHigh(f"1-minute load {value:.0f} is at or over {limit:g}")
    return value


def standalone_agent(udid: str, session: str, state_dir: Path) -> str:
    """The standalone ``agent-device`` command the spike used, for runs without a ``device_open`` command (own session, own state dir)."""
    entries = sorted(glob.glob(os.path.expanduser("~/.t3/tools/agent-device/*/node_modules/agent-device/bin/agent-device.mjs")))
    app = "/Applications/T3 Code (Beta).app/Contents/MacOS/T3 Code (Beta)"
    if not entries or not os.path.exists(app):
        raise RuntimeError("no bundled agent-device found: pass --reference-agent and --native-agent from device_open")
    return "env ELECTRON_RUN_AS_NODE=1 %s %s --platform ios --udid %s --session %s --state-dir %s" % (
        shlex.quote(app), shlex.quote(entries[-1]), udid, session, shlex.quote(str(state_dir)))


@dataclass
class Device:
    """One side's simulator, its bound agent and what the app is launched with."""
    side: str
    udid: str
    agent: Agent
    publication: Optional[Path] = None
    #: A ``bootstrap.json`` to copy into this simulator's gallery fixture folder when it has none (native gallery mode).
    gallery_bootstrap: Optional[Path] = None


@dataclass
class Take:
    side: str
    index: int
    clip: Optional[Path] = None
    ok: bool = False
    reason: str = ""
    duration_ms: float = 0.0
    load: float = 0.0


def stage_gallery_bootstrap(data_dir: Path, source: Path) -> None:
    """Copy a gallery ``bootstrap.json`` into ``data_dir`` unless the simulator already has one."""
    folder = Path(data_dir) / pl_launch.FIXTURE_SUBPATH
    target = folder / "bootstrap.json"
    if not target.is_file():
        folder.mkdir(parents=True, exist_ok=True)
        target.write_bytes(Path(source).read_bytes())


def relaunch(device: Device, scenario: Scenario, reduce_motion: bool, runner: Runner = run, sleep=time.sleep) -> None:
    """Terminate and launch with Reduce Motion explicit, attach the agent, and reach the scenario's starting screen."""
    gallery = device.side == REFERENCE or scenario.native_mode == "gallery"
    env = launch_env(os.environ, reduce_motion, scenario.env)
    if device.publication and not gallery:
        problems = validate_publication(device.publication)
        if problems:
            raise Refused("; ".join(problems))
    data = pl_launch.container(runner, device.udid, "data") if gallery or device.publication else None
    if gallery:
        if device.gallery_bootstrap:
            stage_gallery_bootstrap(data, device.gallery_bootstrap)
        pl_launch.set_gallery_page(data, scenario.gallery_page)
    elif device.publication:
        pl_launch.feed_preview(data, device.publication)
    runner(["xcrun", "simctl", "terminate", device.udid, BUNDLE_ID])
    args = ["--gallery-fixture"] if gallery else ["--server-ui-preview"]
    runner(["xcrun", "simctl", "launch", device.udid, BUNDLE_ID, *args], env)
    sleep(3.5 if gallery else 4.5)
    device.agent.open_app(BUNDLE_ID, relaunch=False)
    if device.side == NATIVE and not gallery:
        for label in scenario.native_prepare:
            device.agent.call("press", f'label="{label}"')
            sleep(1.5)
    device.agent.call("wait", "stable", "800", "8000")


def record_take(device: Device, scenario: Scenario, out: Path, index: int, reduce_motion: bool = False,
                load_limit: float = LOAD_LIMIT, sleep=time.sleep, load=load_1min, load_wait_s: float = 0.0) -> Take:
    """One take on one side. Returns the take with ``ok`` False and a ``reason`` instead of raising for infra problems."""
    take = Take(device.side, index)
    try:
        take.load = gate_on_load(load_limit, load, load_wait_s, sleep)
    except LoadTooHigh as error:
        take.reason = f"load: {error}"
        return take
    relaunch(device, scenario, reduce_motion, sleep=sleep)
    started = device.agent.call("record", "start", str(out), "--hide-touches")
    if not started.get("success"):
        take.reason = f"record start failed: {str(started)[:200]}"
        return take
    sleep(scenario.lead_ms / 1000)
    for step in scenario.steps:
        device.agent.call("press", step.selector(device.side))
        sleep(step.wait_ms / 1000)
    stopped = device.agent.call("record", "stop")
    data = stopped.get("data") or {}
    take.duration_ms = float(data.get("durationMs") or 0)
    if not stopped.get("success") or not out.exists():
        take.reason = f"record stop failed: {str(stopped)[:200]}"
        return take
    if take.duration_ms > scenario.sequence_ms() + OVERRUN_MS + PRESS_MS * len(scenario.steps):
        take.reason = f"infra: recording ran {take.duration_ms / 1000:.1f} s for a {scenario.sequence_ms() / 1000:.1f} s sequence"
        return take
    take.clip, take.ok = out, True
    return take


def record_pair(devices: Dict[str, Device], scenario: Scenario, out_dir: Path, takes: int, reduce_motion: bool = False,
                load_limit: float = LOAD_LIMIT, retries: int = 1, load_wait_s: float = 900.0,
                env: Optional[Mapping[str, str]] = None) -> Dict[str, List[Take]]:
    """The simulator guard first (nothing is touched when it refuses), then ``takes`` takes per side. The two sides record at the same time (one simulator each; two can record at once), and each
    side's takes run in turn. A refused or discarded take is retried up to ``retries`` times."""
    guard_simulators([d.udid for d in devices.values()], os.environ if env is None else env)
    results: Dict[str, List[Take]] = {side: [] for side in devices}
    out_dir.mkdir(parents=True, exist_ok=True)

    def worker(side: str) -> None:
        for n in range(takes):
            for attempt in range(retries + 1):
                take = record_take(devices[side], scenario, out_dir / f"{side}-{n + 1}-try{attempt + 1}.mp4", n + 1, reduce_motion, load_limit,
                                   load_wait_s=load_wait_s)
                results[side].append(take)
                if take.ok:
                    break
                time.sleep(20 if take.reason.startswith("load") else 2)

    threads = [threading.Thread(target=worker, args=(side,)) for side in devices]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    for device in devices.values():
        device.agent.call("close")  # release the device claim so the next session (or lane) can take it
    return results


#: Launch variables the tool may pass (as ``SIMCTL_CHILD_<name>``). Nothing else reaches the app: an inherited ``SIMCTL_CHILD_`` variable
#: (a preview token, a server address) is dropped, and a scenario asking for another name is refused.
ALLOWED_LAUNCH_ENV = frozenset({"FENTON_SYSTEM_SETTINGS", "FENTON_UK_EXTRAS"})
LOOPBACK_HOSTS = frozenset({"127.0.0.1", "localhost", "::1"})


class Refused(Exception):
    """A run the tool will not start; the message says why and carries no secret."""


def guard_simulators(udids: List[str], env: Mapping[str, str]) -> None:
    """The one shared guard (``tools/parity_loop/simguard.py``): refuse a protected simulator and any simulator this process holds no
    ``device-<UDID>`` gate for. Called before any install, launch, container write or recording; there is no second guard here."""
    simguard.guard(udids, env)


def launch_env(base: Mapping[str, str], reduce_motion: bool, scenario_env: Mapping[str, str]) -> Dict[str, str]:
    """The environment of a ``simctl launch``: the host's own variables, no inherited ``SIMCTL_CHILD_*``, then exactly the allowlisted
    names the tool sets (Reduce Motion always, explicit)."""
    refused = sorted(set(scenario_env) - ALLOWED_LAUNCH_ENV)
    if refused:
        raise Refused("launch variable(s) not on the allowlist: " + ", ".join(refused))
    env = {k: v for k, v in base.items() if not k.startswith("SIMCTL_CHILD_")}
    env["SIMCTL_CHILD_FENTON_SYSTEM_SETTINGS"] = "reduceMotion" if reduce_motion else "none"
    for name, value in scenario_env.items():
        env["SIMCTL_CHILD_" + name] = value
    return env


def fixture_problems(bootstrap: Mapping[str, object]) -> List[str]:
    """Why a preview ``bootstrap.json`` is not fixtures only: a ``live`` block (what ``stage.py`` writes for a live preview), a ``server``
    or ``origin`` key, or an ``endpoint`` that is not a loopback address."""
    from urllib.parse import urlsplit
    problems = []
    for key in ("live", "server", "origin"):
        if key in bootstrap:
            problems.append(f"bootstrap.json carries a {key!r} block: a publication for a live server is refused (fixtures only)")
    endpoint = bootstrap.get("endpoint")
    if endpoint is not None and (urlsplit(str(endpoint)).hostname or "") not in LOOPBACK_HOSTS:
        problems.append(f"bootstrap.json endpoint {endpoint!r} is not a loopback address (fixtures only)")
    return problems


def validate_publication(path: Path) -> List[str]:
    """Problems with a native preview publication directory (the one ``feed_preview`` copies from): the files it needs and its assets."""
    path = Path(path)
    problems = [f"{path / name} is missing" for name in ("bootstrap.json", "publication.json") if not (path / name).is_file()]
    if not (path / "assets").is_dir():
        problems.append(f"{path / 'assets'} is missing")
    boot = path / "bootstrap.json"
    if boot.is_file():
        try:
            problems += fixture_problems(json.loads(boot.read_text(encoding="utf-8")))
        except ValueError:
            problems.append(f"{boot} is not valid JSON")
    return problems


def dry_run(scenario: Scenario, publication: Optional[Path], gallery_bootstrap: Optional[Path], out_dir: Path,
            udids: Dict[str, str], commands: Dict[str, str], simulators: Optional[str] = None) -> Dict[str, object]:
    """Resolve everything a recording needs without touching a device: the scenario's per-side selectors, the publication and
    bootstrap files, the swift tools, the output folder, the bound agent commands and (given ``simulators``, the text of
    ``simctl list devices``) that each UDID exists. ``problems`` is empty when a run can start."""
    from . import video
    problems: List[str] = []
    if scenario.native_mode == "preview":
        if publication is None:
            problems.append("native preview needs --publication")
        else:
            problems += validate_publication(publication)
    if gallery_bootstrap is not None and not Path(gallery_bootstrap).is_file():
        problems.append(f"{gallery_bootstrap} is missing")
    if scenario.native_mode == "gallery" and gallery_bootstrap is None:
        problems.append("native gallery mode needs --gallery-bootstrap")
    for name in ("clip_gray", "clip_pts", "clip_frames"):
        try:
            video.tool(name)
        except Exception as error:  # a swiftc failure is a problem to report, not to raise
            problems.append(f"{name}: {error}")
    problems += [f"{side} simulator {udid} is protected: a run would be refused" for side, udid in udids.items() if simguard.is_protected(udid)]
    if simulators is not None:
        problems += [f"{side} simulator {udid} is not in simctl list" for side, udid in udids.items() if udid not in simulators]
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        problems.append(f"{out_dir}: {error}")
    steps = [{"side": side, "press": [step.selector(side) for step in scenario.steps],
              "events": [step.event for step in scenario.steps if step.event]} for side in udids]
    return {"scenario": scenario.id, "nativeMode": scenario.native_mode, "page": scenario.gallery_page, "sequenceMs": scenario.sequence_ms(),
            "overrunLimitMs": scenario.sequence_ms() + OVERRUN_MS + PRESS_MS * len(scenario.steps), "udids": udids, "agents": commands,
            "steps": steps, "events": [e.name for e in scenario.events()], "problems": problems}
