#!/usr/bin/env python3
"""Launching each app on its own simulator, in gallery (fixture) mode or live mode.

    launch.py gallery --side reference|candidate --agent CMD --udid UDID [--page NAME] [--publication DIR]
    launch.py live    --side reference|candidate --udid UDID --proxy-url URL
    launch.py proxy   --log FILE [--listen HOST:PORT]     (FILE must be git-ignored)

Every launch needs a ``tools/devcap.py`` simulator hold (``DEVCAP_HELD``). **Gallery mode** relaunches the app through the bound ``agent-device``: the reference with ``--gallery-fixture`` on the named
gallery page, the candidate with ``--server-ui-preview`` (after :func:`feed_preview` copied a publication in).

**Live mode** refuses unless ``PARITY_LIVE_GO=1`` is set. It signs the reference into Home Assistant with a token launch
(``simctl launch`` with ``SIMCTL_CHILD_*`` variables) built in a bash child that sources ``tools/hass_creds.sh``; the token
exists only in that child, never in this process, its arguments, its output or a file. The reference is only ever pointed at
``--proxy-url``, the write-guard proxy, never at the real server. The candidate is staged first (``stage.py``: the publication and
its assets fetched read-only through the proxy and written into its container), then launched with ``--server-ui-preview`` and the
token in ``SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN`` only.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from parity_loop.capture import Agent  # noqa: E402
from parity_loop.common import APPS, BUNDLE_ID, CANDIDATE, REFERENCE, REPO, Runner, run  # noqa: E402

GO_VARIABLE = "PARITY_LIVE_GO"
GALLERY_ARGS = {REFERENCE: ["--gallery-fixture"], CANDIDATE: ["--server-ui-preview"]}
HELD_VARIABLE = "DEVCAP_HELD"
#: What each live half is launched with, for the sidecar: ``(launch arguments, environment variable NAMES)``. Names only, never
#: values. The reference's server variable points at the guard proxy; the candidate gets its server from ``bootstrap.json``.
LIVE_LAUNCH = {
    REFERENCE: ([], ["FENTON_HASS_TOKEN", "FENTON_HASS_SERVER", "FENTON_SYSTEM_SETTINGS", "FENTON_SKIP_INTRO"]),
    CANDIDATE: (["--server-ui-preview"], ["FENTON_PREVIEW_HA_TOKEN", "FENTON_SYSTEM_SETTINGS", "FENTON_SKIP_INTRO"]),
}
FIXTURE_SUBPATH = "Library/Application Support/GalleryFixture"
PREVIEW_SUBPATH = "Library/Application Support/ServerUIPreview"


class Refused(Exception):
    """A launch the harness will not make; the message says why and carries no secret."""


def require_go(env: Mapping[str, str]) -> None:
    """Live mode needs the owner's go, recorded as ``PARITY_LIVE_GO=1`` in the environment."""
    if env.get(GO_VARIABLE) != "1":
        raise Refused(f"live mode refused: {GO_VARIABLE}=1 is not set (the owner's go for read-only live captures)")


def require_hold(env: Mapping[str, str]) -> None:
    """Launching an app on a simulator needs a ``tools/devcap.py`` simulator hold (``DEVCAP_HELD`` names the gates held)."""
    if "simulator" not in env.get(HELD_VARIABLE, "").split(","):
        raise Refused("launch refused: take a devcap simulator hold first (tools/devcap.py run --sim UDID ...)")


def launch_record(mode: str, side: str) -> Tuple[List[str], List[str]]:
    """The launch arguments and environment variable names a half is launched with in ``mode``, for its sidecar."""
    if mode == "live":
        args, names = LIVE_LAUNCH[side]
        return list(args), sorted(names)
    return list(GALLERY_ARGS[side]), []


def log_is_ignored(path: Path, runner: Runner = run) -> bool:
    """True when git ignores ``path`` (a proxy log must never sit where it could be committed)."""
    return runner(["git", "-C", str(REPO), "check-ignore", "-q", str(path)]).code == 0


# MARK: - Gallery mode

def container(runner: Runner, udid: str, kind: str, bundle: str = BUNDLE_ID) -> Path:
    result = runner(["xcrun", "simctl", "get_app_container", udid, bundle, kind])
    if result.code != 0 or not result.out.strip():
        raise Refused(f"no {kind} container for {bundle} on {udid}")
    return Path(result.out.strip())


def set_gallery_page(data_dir: Path, page: str) -> None:
    """Point the reference's gallery fixture at ``page`` (``variables.FENTON_GALLERY``) and clear the stale receipt."""
    folder = Path(data_dir) / FIXTURE_SUBPATH
    path = folder / "bootstrap.json"
    if not path.is_file():
        raise Refused("the reference has no gallery fixture bootstrap on this simulator")
    fixture = json.loads(path.read_text(encoding="utf-8"))
    fixture.setdefault("variables", {})["FENTON_GALLERY"] = page
    path.write_text(json.dumps(fixture, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    (folder / "receipt.json").unlink(missing_ok=True)


def feed_preview(data_dir: Path, publication: Path) -> None:
    """Copy a publication directory's bootstrap, publication and assets into the candidate's preview folder."""
    preview = Path(data_dir) / PREVIEW_SUBPATH
    (preview / "assets").mkdir(parents=True, exist_ok=True)
    for name in ("bootstrap.json", "publication.json"):
        shutil.copyfile(Path(publication) / name, preview / name)
    for asset in sorted((Path(publication) / "assets").glob("*")):
        shutil.copyfile(asset, preview / "assets" / (asset.name[:-4] if asset.name.endswith(".png") else asset.name))
    (preview / "receipt.json").unlink(missing_ok=True)


def launch_gallery(side: str, agent: Agent, udid: str, page: Optional[str] = None, runner: Runner = run) -> Dict[str, Any]:
    """Relaunch ``side`` in gallery mode; the reference first has its gallery page set."""
    if side == REFERENCE and page:
        set_gallery_page(container(runner, udid, "data"), page)
    return agent.open_app(BUNDLE_ID, GALLERY_ARGS[side], relaunch=True)


# MARK: - Live mode

def live_script(udid: str, bundle: str = BUNDLE_ID) -> str:
    """The bash that token-launches the reference. It reads ``PROXY_URL`` from its environment; the token is loaded by
    ``hass_creds.sh`` inside the child and handed to ``simctl`` as ``SIMCTL_CHILD_FENTON_HASS_TOKEN``. No secret is in this text."""
    creds = shlex.quote(str(REPO / "tools" / "hass_creds.sh"))
    return "\n".join([
        "set -euo pipefail",
        f"source {creds}",
        "hass_load_creds || exit 2",
        "hass_require_creds || exit 2",
        '[[ -n "${PROXY_URL:-}" ]] || { echo "no proxy url" >&2; exit 2; }',
        f"xcrun simctl terminate {shlex.quote(udid)} {shlex.quote(bundle)} >/dev/null 2>&1 || true",
        # The reference sees the proxy as its server: the real server address is never passed to it.
        'SIMCTL_CHILD_FENTON_HASS_TOKEN="$FENTON_HASS_TOKEN" SIMCTL_CHILD_FENTON_HASS_SERVER="$PROXY_URL" '
        "SIMCTL_CHILD_FENTON_SYSTEM_SETTINGS=none SIMCTL_CHILD_FENTON_SKIP_INTRO=1 "
        f"exec xcrun simctl launch {shlex.quote(udid)} {shlex.quote(bundle)} >/dev/null",
    ])


def candidate_live_script(udid: str, bundle: str = BUNDLE_ID) -> str:
    """The bash that stages the live publication and launches the candidate's read-only preview.

    ``stage.py`` (a child that inherits the credentials ``hass_creds.sh`` loaded) fetches the publication and assets through the
    guard proxy and writes them into the container at ``$CONTAINER_DATA``. The launch then hands the token to the preview only as
    ``SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN``; the server address reaches the app through the container's ``bootstrap.json``.
    No secret is in this text.
    """
    creds = shlex.quote(str(REPO / "tools" / "hass_creds.sh"))
    stage = " ".join(shlex.quote(p) for p in (sys.executable, str(Path(__file__).with_name("stage.py"))))
    return "\n".join([
        "set -euo pipefail",
        f"source {creds}",
        "hass_load_creds || exit 2",
        "hass_require_creds || exit 2",
        '[[ -n "${PROXY_URL:-}" && -n "${CONTAINER_DATA:-}" ]] || { echo "no proxy url or container" >&2; exit 2; }',
        f'{stage} --proxy "$PROXY_URL" --container "$CONTAINER_DATA"',
        f"xcrun simctl terminate {shlex.quote(udid)} {shlex.quote(bundle)} >/dev/null 2>&1 || true",
        'SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN="$FENTON_HASS_TOKEN" '
        "SIMCTL_CHILD_FENTON_SYSTEM_SETTINGS=none SIMCTL_CHILD_FENTON_SKIP_INTRO=1 "
        f"exec xcrun simctl launch {shlex.quote(udid)} {shlex.quote(bundle)} --server-ui-preview >/dev/null",
    ])


def launch_live(side: str, udid: str, proxy_url: Optional[str], runner: Runner = run,
                env: Optional[Mapping[str, str]] = None) -> None:
    """Launch ``side`` live. Refuses without the go or without a proxy.

    The reference is token-launched with the proxy as its server. The candidate first has its publication staged through the
    proxy (read-only), then launches in preview mode with the token in its environment only.
    """
    child = dict(os.environ if env is None else env)
    require_go(child)
    require_hold(child)
    if not proxy_url:
        raise Refused("live launches need --proxy-url pointing at the write-guard proxy")
    child["PROXY_URL"] = proxy_url
    if side == REFERENCE:
        script = live_script(udid)
    else:
        child["CONTAINER_DATA"] = str(container(runner, udid, "data"))
        script = candidate_live_script(udid)
    result = runner(["bash", "-c", script], child, 300.0)
    if result.code != 0:
        raise Refused(f"live launch failed (exit {result.code}); credentials or server missing, staging or simctl failed")


#: Credentials the proxy never needs (it forwards the client's own ``auth``); stripped from its environment before it starts.
PROXY_UNNEEDED_SECRETS = ("FENTON_HASS_TOKEN", "FENTON_HASS_PASSWORD", "FENTON_HASS_USERNAME")


def proxy_script(log: Path, listen: str, command: Optional[List[str]] = None) -> str:
    """The bash that loads the upstream address from the credentials file and execs the guard proxy (nothing is printed).

    The token, password and username are unset before the ``exec``: the long-lived proxy needs only ``FENTON_HASS_SERVER``.
    ``command`` replaces the proxy program (tests).
    """
    creds = shlex.quote(str(REPO / "tools" / "hass_creds.sh"))
    proxy = command or [sys.executable, str(Path(__file__).with_name("guard_proxy.py")), "--listen", listen, "--log", str(log)]
    return (f"source {creds}; hass_load_creds || exit 2; hass_require_creds || exit 2; unset {' '.join(PROXY_UNNEEDED_SECRETS)}; exec "
            + " ".join(shlex.quote(p) for p in proxy))


def run_proxy(log: Path, listen: str, env: Optional[Mapping[str, str]] = None, runner: Runner = run) -> int:
    """Replace this process with the guard proxy, started with the go and the credentials file's server.

    The log path must be ignored by git: even a templated log is house traffic and must not be committable.
    """
    child = {k: v for k, v in dict(os.environ if env is None else env).items() if k not in PROXY_UNNEEDED_SECRETS}
    require_go(child)
    if not log_is_ignored(log, runner):
        raise Refused("the proxy log must be in a git-ignored folder (for example build/evidence/parity-loop/<run>/)")
    os.execvpe("bash", ["bash", "-c", proxy_script(log, listen)], child)
    return 1  # not reached


# MARK: - Command line

def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="verb", required=True)
    g = sub.add_parser("gallery")
    g.add_argument("--side", choices=APPS, required=True)
    g.add_argument("--agent", required=True, help="the bound agent-device command")
    g.add_argument("--udid", required=True)
    g.add_argument("--page")
    g.add_argument("--publication", type=Path)
    lv = sub.add_parser("live")
    lv.add_argument("--side", choices=APPS, required=True)
    lv.add_argument("--udid", required=True)
    lv.add_argument("--proxy-url")
    px = sub.add_parser("proxy")
    px.add_argument("--log", type=Path, required=True)
    px.add_argument("--listen", default="127.0.0.1:0")
    args = ap.parse_args(argv)
    try:
        if args.verb == "gallery":
            require_hold(dict(os.environ))
            if args.publication and args.side == CANDIDATE:
                feed_preview(container(run, args.udid, "data"), args.publication)
            launch_gallery(args.side, Agent(args.agent), args.udid, args.page)
        elif args.verb == "live":
            launch_live(args.side, args.udid, args.proxy_url)
        else:
            return run_proxy(args.log, args.listen)
    except Refused as error:
        print(f"launch: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
