#!/usr/bin/env python3
"""Launching each app on its own simulator, in gallery (fixture) mode or live mode.

    launch.py gallery --side reference|candidate --agent CMD --udid UDID [--page NAME] [--publication DIR]
    launch.py live    --side reference --udid UDID --proxy-url URL
    launch.py proxy   --log FILE [--listen HOST:PORT]

**Gallery mode** relaunches the app through the bound ``agent-device``: the reference with ``--gallery-fixture`` on the named
gallery page, the candidate with ``--server-ui-preview`` (after :func:`feed_preview` copied a publication in).

**Live mode** refuses unless ``PARITY_LIVE_GO=1`` is set. It signs the reference into Home Assistant with a token launch
(``simctl launch`` with ``SIMCTL_CHILD_*`` variables) built in a bash child that sources ``tools/hass_creds.sh``; the token
exists only in that child, never in this process, its arguments, its output or a file. The reference is only ever pointed at
``--proxy-url``, the write-guard proxy, never at the real server. The candidate's read-only live preview needs a one-time
credential *file* in the simulator container, which would write the token to disk; it is refused until the owner allows that.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from parity_loop.capture import Agent  # noqa: E402
from parity_loop.common import APPS, BUNDLE_ID, CANDIDATE, REFERENCE, REPO, Runner, run  # noqa: E402

GO_VARIABLE = "PARITY_LIVE_GO"
GALLERY_ARGS = {REFERENCE: ["--gallery-fixture"], CANDIDATE: ["--server-ui-preview"]}
FIXTURE_SUBPATH = "Library/Application Support/GalleryFixture"
PREVIEW_SUBPATH = "Library/Application Support/ServerUIPreview"


class Refused(Exception):
    """A launch the harness will not make; the message says why and carries no secret."""


def require_go(env: Mapping[str, str]) -> None:
    """Live mode needs the owner's go, recorded as ``PARITY_LIVE_GO=1`` in the environment."""
    if env.get(GO_VARIABLE) != "1":
        raise Refused(f"live mode refused: {GO_VARIABLE}=1 is not set (the owner's go for read-only live captures)")


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


def launch_live(side: str, udid: str, proxy_url: Optional[str], runner: Runner = run,
                env: Optional[Mapping[str, str]] = None) -> None:
    """Token-launch the reference through the guard proxy. Refuses without the go, without a proxy, or for the candidate."""
    child = dict(os.environ if env is None else env)
    require_go(child)
    if side != REFERENCE:
        raise Refused("the candidate's live preview needs a one-time credential file, which would write the token to disk; not allowed")
    if not proxy_url:
        raise Refused("the reference may only be launched live with --proxy-url pointing at the write-guard proxy")
    child["PROXY_URL"] = proxy_url
    result = runner(["bash", "-c", live_script(udid)], child, 120.0)
    if result.code != 0:
        raise Refused(f"live launch failed (exit {result.code}); credentials or server missing, or simctl failed")


def proxy_script(log: Path, listen: str) -> str:
    """The bash that loads the upstream address from the credentials file and execs the guard proxy (nothing is printed)."""
    creds = shlex.quote(str(REPO / "tools" / "hass_creds.sh"))
    proxy = [sys.executable, str(Path(__file__).with_name("guard_proxy.py")), "--listen", listen, "--log", str(log)]
    return f"source {creds}; hass_load_creds || exit 2; hass_require_creds || exit 2; exec " + " ".join(shlex.quote(p) for p in proxy)


def run_proxy(log: Path, listen: str, env: Optional[Mapping[str, str]] = None) -> int:
    """Replace this process with the guard proxy, started with the go and the credentials file's server."""
    child = dict(os.environ if env is None else env)
    require_go(child)
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
