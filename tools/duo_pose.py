#!/usr/bin/env python3
"""Set the pose of the "iPhone Duo (HASS)" simulator through FestivalNativeApps' ``ios_sim.py``.

Why a wrapper that delegates: ``ios_sim.py pose`` drives Device Hub by UI scripting and only
knows FestivalNativeApps' own ``iPhone Duo (FST)`` (``HUB_DEVICE_NAMES``). Porting that logic
would fork a large, moving script, so this imports it, registers the HASS Duo UDID under its
Device Hub name and calls ``ios_sim.main(["pose", ...])``. The FestivalNativeApps checkout is
found through ``FENTON_FST_REPO`` (default ``~/repos/FestivalNativeApps``).

Run it inside a devcap hold; it refuses otherwise, because it drives a simulator::

    python3 tools/devcap.py run --sim <UDID> --hold 600 -- \\
        python3 tools/duo_pose.py --sim <UDID> --set unfolded

Needs the Accessibility permission and takes about a minute. See
``.agents/testing/apple/devices.md`` for the pose sequence and how to confirm it.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

POSES = ("folded", "unfolded", "half", "rotate-left", "rotate-right")
HUB_NAME = "iPhone Duo (HASS)"
REPO_ENV = "FENTON_FST_REPO"
DEFAULT_REPO = "~/repos/FestivalNativeApps"
HELD_ENV = "DEVCAP_HELD"  # set by tools/devcap.py for children of a hold
EXIT_USAGE, EXIT_NO_HOLD, EXIT_NO_DEP = 2, 3, 4


def fst_script(env: dict[str, str] | None = None) -> Path:
    """Path of FestivalNativeApps' ``tools/ios_sim.py`` (it may not exist)."""
    env = os.environ if env is None else env
    return Path(env.get(REPO_ENV) or DEFAULT_REPO).expanduser() / "tools" / "ios_sim.py"


def in_hold(env: dict[str, str] | None = None) -> bool:
    """True when this process runs under a devcap simulator hold."""
    env = os.environ if env is None else env
    return "simulator" in env.get(HELD_ENV, "").split(",")


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse ``--sim UDID --set POSE``."""
    p = argparse.ArgumentParser(description="Set the iPhone Duo (HASS) pose via Device Hub.")
    p.add_argument("--sim", required=True, help="UDID of the iPhone Duo (HASS) simulator")
    p.add_argument("--set", dest="pose", required=True, choices=POSES)
    return p.parse_args(argv)


def main(argv: list[str] | None = None, env: dict[str, str] | None = None) -> int:
    """Validate, check the hold and the dependency, then delegate to ``ios_sim.main``."""
    try:
        args = parse_args(sys.argv[1:] if argv is None else argv)
    except SystemExit as exc:
        return EXIT_USAGE if exc.code else 0
    if not in_hold(env):
        print("duo_pose: refusing to drive a simulator outside a devcap hold. Run: "
              f"python3 tools/devcap.py run --sim {args.sim} --hold 600 -- "
              f"python3 tools/duo_pose.py --sim {args.sim} --set {args.pose}", file=sys.stderr)
        return EXIT_NO_HOLD
    script = fst_script(env)
    if not script.is_file():
        print(f"duo_pose: {script} not found. Clone SFenton/FestivalNativeApps or set {REPO_ENV}.",
              file=sys.stderr)
        return EXIT_NO_DEP
    sys.path.insert(0, str(script.parent))
    import ios_sim  # type: ignore[import-not-found]
    ios_sim.HUB_DEVICE_NAMES[args.sim] = HUB_NAME
    return int(ios_sim.main(["pose", "--device", args.sim, "--set", args.pose]) or 0)


if __name__ == "__main__":
    sys.exit(main())
