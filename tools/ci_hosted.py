#!/usr/bin/env python3
"""Hosted-CI mode: ``FENTON_CI_HOSTED=1`` for a GitHub-hosted runner (one job per ephemeral VM).

On the owner's Macs the shared-capacity rules (devcap holds and pools, the simulator pool, disk hygiene) keep lanes from
starving each other. A hosted runner is a single-tenant VM that is thrown away, so none of that applies there. With the
variable set:

* the scripts that call devcap (the journey runner and the coverage script) call ``ci_hosted.py devcap`` instead
  (:func:`devcap_main`: no hold, no pool, no queue); ``tools/devcap.py`` is a vendored copy and stays untouched;
* ``tools/ci_hygiene.py`` does nothing;
* ``tools/ios_uitest.sh`` takes simulators by name from the image (``FENTON_SIM_IPHONE``, ``FENTON_SIM_DUO``,
  ``FENTON_SIM_IPAD``; the defaults are :data:`DEFAULT_SIMS`), never creates a pool clone, and skips the pool preflight.

Unset, any value but ``1``, or a runner that is not GitHub-hosted (no ``RUNNER_ENVIRONMENT=github-hosted``): nothing changes. Stdlib only (macOS system Python 3.9, Linux runners).

    ci_hosted.py devcap ARGS...      the hosted stand-in for devcap.py (tools/devcap.py is a vendored copy and is not edited)
    ci_hosted.py sim-name FAMILY     print the simulator name a family uses hosted (override or default)
    ci_hosted.py active              exit 0 when hosted mode is on
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from typing import Callable, List, Mapping, Optional, Sequence

#: The switch, read from the process settings. Honoured only on a GitHub-hosted runner: GitHub sets RUNNER_ENVIRONMENT to
#: ``github-hosted`` there (``self-hosted`` on the owner's Macs), so the variable can never switch off devcap holds locally.
ENV = "FENTON_CI_HOSTED"
RUNNER_ENV = "RUNNER_ENVIRONMENT"
RUNNER_HOSTED = "github-hosted"

#: Simulators on the ``xcode-27`` image (actions/runner-images, Xcode 27.1): iPhone and iPad run iOS 27.0, the bare Duo runs 27.1.
#: Locally the Duo is the devcap clone "iPhone Duo (HASS)" and the iPhone is "iPhone 17 Pro"; neither exists on the image.
DEFAULT_SIMS = {"iphone": "iPhone 17", "duo": "iPhone Duo", "ipad": "iPad Pro 11-inch (M5)"}

#: The setting that overrides each family's simulator name.
OVERRIDES = {"iphone": "FENTON_SIM_IPHONE", "duo": "FENTON_SIM_DUO", "ipad": "FENTON_SIM_IPAD"}


def active(settings: Optional[Mapping[str, str]] = None) -> bool:
    """Whether hosted mode is on: ``FENTON_CI_HOSTED`` is exactly ``1`` and the runner is GitHub-hosted (``RUNNER_ENVIRONMENT``)."""
    source = os.environ if settings is None else settings
    return source.get(ENV) == "1" and source.get(RUNNER_ENV) == RUNNER_HOSTED


def sim_name(family: str, settings: Optional[Mapping[str, str]] = None) -> str:
    """The simulator name for ``family`` (iphone, duo, ipad): its ``FENTON_SIM_*`` override, else the image default."""
    source = os.environ if settings is None else settings
    return source.get(OVERRIDES[family]) or DEFAULT_SIMS[family]


def find_udid(name: str, listing: Optional[dict] = None) -> Optional[str]:
    """The UDID of the first available simulator named exactly ``name``, or None.

    ``listing`` is ``xcrun simctl list devices available --json`` parsed; read from simctl when omitted."""
    if listing is None:
        out = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"], capture_output=True, text=True)
        if out.returncode != 0:
            return None
        listing = json.loads(out.stdout or "{}")
    for devices in listing.get("devices", {}).values():
        for device in devices:
            if device.get("name") == name and device.get("isAvailable", True):
                return device.get("udid")
    return None


def devcap_main(argv: Sequence[str], runner: Callable[[List[str]], int] = lambda cmd: subprocess.call(cmd),
                lookup: Callable[[str], Optional[str]] = find_udid) -> int:
    """The hosted stand-in for ``devcap.py``: same command line, no capacity.

    ``run ... -- CMD`` runs CMD at once (the hold, pool and sim flags are ignored, the job timeout bounds the run);
    ``pick-sim --name N`` prints the UDID of the existing simulator named N (never creates a clone); ``status``, ``reap``
    and ``slots`` have nothing to report. Returns the command's exit status."""
    args = list(argv)
    if not args:
        print("devcap (hosted): missing command", file=sys.stderr)
        return 2
    cmd, rest = args[0], args[1:]
    if cmd == "run":
        if "--" not in rest or not rest[rest.index("--") + 1:]:
            print("devcap run: missing command after --", file=sys.stderr)
            return 2
        return runner(rest[rest.index("--") + 1:])
    if cmd == "pick-sim":
        name = rest[rest.index("--name") + 1] if "--name" in rest and rest.index("--name") + 1 < len(rest) else ""
        udid = lookup(name) if name else None
        if udid is None:
            print("devcap pick-sim: no available simulator named %r" % name, file=sys.stderr)
            return 1
        print(udid)
        return 0
    if cmd in ("status", "reap", "slots"):
        print("devcap (hosted): no capacity gates on a hosted runner")
        return 0
    print("devcap (hosted): unsupported command %r" % cmd, file=sys.stderr)
    return 2


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Command line: ``sim-name FAMILY`` or ``active``."""
    args = list(sys.argv[1:] if argv is None else argv)
    if args[:1] == ["devcap"]:
        return devcap_main(args[1:])
    if args[:1] == ["active"]:
        return 0 if active() else 1
    if len(args) == 2 and args[0] == "sim-name" and args[1] in DEFAULT_SIMS:
        print(sim_name(args[1]))
        return 0
    print("usage: ci_hosted.py devcap ARGS | sim-name iphone|duo|ipad | active", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
