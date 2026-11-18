#!/usr/bin/env python3
"""Launching each app on its own simulator, in gallery (fixture) mode or live mode.

    launch.py gallery --side reference|candidate --agent CMD --udid UDID [--page NAME] [--publication DIR]
    launch.py live    --side reference|candidate --udid UDID --proxy-url https://127.0.0.1:PORT --proxy-cert FILE
    launch.py proxy   --log FILE [--listen HOST:PORT]     (FILE must be git-ignored; serves TLS with a throwaway certificate)
    launch.py identity --proxy-url URL --proxy-cert FILE   (prints the hash of the HA user id the token resolves to)

Every launch needs a ``tools/devcap.py`` simulator hold (``DEVCAP_HELD``). **Gallery mode** relaunches the app through the bound ``agent-device``: the reference with ``--gallery-fixture`` on the named
gallery page, the candidate with ``--server-ui-preview`` (after :func:`feed_preview` copied a publication in).

**Live mode** refuses unless ``PARITY_LIVE_GO=1`` is set. It signs the reference into Home Assistant with a token launch
(``simctl launch`` with ``SIMCTL_CHILD_*`` variables) built in a bash child that sources ``tools/hass_creds.sh``; the token
exists only in that child, never in this process, its arguments, its output or a file. **Both** halves are only ever pointed at
``--proxy-url``, the write-guard proxy, served over TLS with a throwaway certificate (``proxy`` makes it beside the log; each live
launch first adds it as a root to that simulator's trust store with ``simctl keychain add-root-cert``). The reference gets the proxy
as its server; the candidate is staged first (``stage.py``: the publication and its assets fetched read-only through the proxy and
written into its container, whose ``bootstrap.json`` names the proxy origin), then launched with ``--server-ui-preview`` and the
token in ``SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN`` only. The real server address reaches the proxy alone.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Tuple
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from parity_loop import tls  # noqa: E402
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
IDENTITY_SCRIPT = Path(__file__).with_name("identity.py")
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


#: The only variable names a surface may set beside ``FENTON_GALLERY``; the app's own decode refuses any other name.
GALLERY_PREFIX = "FENTON_GALLERY"
#: Names written by the previous :func:`set_gallery_page`, kept beside the bootstrap so the next surface starts clean.
WRITTEN_FILE = "gallery-variables.json"


def checked_variables(variables: Optional[Mapping[str, Any]]) -> Dict[str, str]:
    """A surface's ``gallery_variables`` as strings, or :class:`Refused` for a name outside ``FENTON_GALLERY*`` or a non-text value."""
    checked: Dict[str, str] = {}
    for name, value in (variables or {}).items():
        if not isinstance(name, str) or not name.startswith(GALLERY_PREFIX):
            raise Refused(f"gallery variable refused: {name!r} does not start with {GALLERY_PREFIX}")
        if not isinstance(value, str):
            raise Refused(f"gallery variable refused: {name} must be text")
        checked[name] = value
    return checked


def set_gallery_page(data_dir: Path, page: str, variables: Optional[Mapping[str, Any]] = None) -> None:
    """Point the reference's gallery fixture at ``page`` (``variables.FENTON_GALLERY``) and clear the stale receipt.

    ``variables`` (a surface's ``gallery_variables``, names starting ``FENTON_GALLERY``) are written beside it. Variables the
    previous call wrote are removed first, so one surface's room or space never leaks into the next.
    """
    extra = checked_variables(variables)
    folder = Path(data_dir) / FIXTURE_SUBPATH
    path = folder / "bootstrap.json"
    if not path.is_file():
        raise Refused("the reference has no gallery fixture bootstrap on this simulator")
    fixture = json.loads(path.read_text(encoding="utf-8"))
    held = fixture.setdefault("variables", {})
    written = folder / WRITTEN_FILE
    try:
        for stale in json.loads(written.read_text(encoding="utf-8")):
            held.pop(stale, None)
    except (OSError, ValueError, TypeError):
        pass
    held["FENTON_GALLERY"] = page
    held.update(extra)
    path.write_text(json.dumps(fixture, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    written.write_text(json.dumps(sorted(extra)), encoding="utf-8")
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


def launch_gallery(side: str, agent: Agent, udid: str, page: Optional[str] = None, runner: Runner = run,
                   variables: Optional[Mapping[str, Any]] = None) -> Dict[str, Any]:
    """Relaunch ``side`` in gallery mode; the reference first has its gallery page (and ``variables``) set."""
    if side == REFERENCE and page:
        set_gallery_page(container(runner, udid, "data"), page, variables)
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
    guard proxy (TLS, trusting ``$PROXY_CERT``) and writes them into the container at ``$CONTAINER_DATA``. The launch then hands the
    token to the preview only as ``SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN``; the **proxy** origin reaches the app through the
    container's ``bootstrap.json``, never the real server's. No secret is in this text.
    """
    creds = shlex.quote(str(REPO / "tools" / "hass_creds.sh"))
    stage = " ".join(shlex.quote(p) for p in (sys.executable, str(Path(__file__).with_name("stage.py"))))
    return "\n".join([
        "set -euo pipefail",
        f"source {creds}",
        "hass_load_creds || exit 2",
        "hass_require_creds || exit 2",
        '[[ -n "${PROXY_URL:-}" && -n "${PROXY_CHAIN:-}" && -n "${CONTAINER_DATA:-}" ]] || { echo "no proxy url, certificate or container" >&2; exit 2; }',
        f'{stage} --proxy "$PROXY_URL" --chain "$PROXY_CHAIN" --container "$CONTAINER_DATA" ${{STAGE_PUBLICATION:+--publication "$STAGE_PUBLICATION"}}',
        f"xcrun simctl terminate {shlex.quote(udid)} {shlex.quote(bundle)} >/dev/null 2>&1 || true",
        'SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN="$FENTON_HASS_TOKEN" '
        "SIMCTL_CHILD_FENTON_SYSTEM_SETTINGS=none SIMCTL_CHILD_FENTON_SKIP_INTRO=1 "
        f"exec xcrun simctl launch {shlex.quote(udid)} {shlex.quote(bundle)} --server-ui-preview >/dev/null",
    ])


def require_tls_proxy(proxy_url: Optional[str], proxy_cert: Optional[Path]) -> None:
    """Both halves go through the proxy over TLS: refuse a missing proxy, a plain ``http`` one or a missing certificate."""
    if not proxy_url:
        raise Refused("live launches need --proxy-url pointing at the write-guard proxy")
    parts = urlsplit(proxy_url)
    if parts.scheme != "https" or not parts.hostname or parts.path not in ("", "/"):
        raise Refused("the proxy url must be the https origin of the TLS write-guard proxy")
    if not proxy_cert or not Path(proxy_cert).is_file():
        raise Refused("live launches need --proxy-cert, the certificate the proxy made beside its log")


def trust_certificate(udid: str, certfile: Path, runner: Runner = run) -> None:
    """Add the proxy's throwaway certificate to simulator ``udid``'s trust store as a root.

    Needs a simulator hold. The root stays until the simulator is erased, so it is added for the run's certificate only (a new run
    makes a new certificate). Some runtimes read the store at boot: if the app still refuses the proxy, reboot that simulator once.
    """
    result = runner(["xcrun", "simctl", "keychain", udid, "add-root-cert", str(certfile)])
    if result.code != 0:
        raise Refused(f"could not trust the proxy certificate on {udid} (exit {result.code})")


def launch_live(side: str, udid: str, proxy_url: Optional[str], runner: Runner = run,
                env: Optional[Mapping[str, str]] = None, proxy_cert: Optional[Path] = None,
                publication: Optional[Path] = None) -> None:
    """Launch ``side`` live. ``publication`` (candidate only) stages that local envelope instead of the live one (``stage.py --publication``). Refuses without the go, a hold, or the TLS proxy and its certificate.

    The simulator first trusts the proxy's certificate. The reference is token-launched with the proxy as its server. The candidate
    has its publication staged through the proxy (read-only; the proxy origin is written into its bootstrap), then launches in
    preview mode with the token in its environment only.
    """
    child = dict(os.environ if env is None else env)
    require_go(child)
    require_hold(child)
    if publication and side == REFERENCE:
        raise Refused("--publication stages the candidate only; the reference reads the live layout")
    require_tls_proxy(proxy_url, proxy_cert)
    trust_certificate(udid, Path(str(proxy_cert)), runner)
    child["PROXY_URL"] = str(proxy_url)
    child["PROXY_CHAIN"] = str(Path(str(proxy_cert)).with_name(tls.CHAIN_NAME))  # the leaf the helpers pin, beside the CA to trust
    child.pop("STAGE_PUBLICATION", None)  # never inherited: a stale draft must not stand in for the live publication
    if side == REFERENCE:
        script = live_script(udid)
    else:
        child["CONTAINER_DATA"] = str(container(runner, udid, "data"))
        if publication:
            if not Path(publication).is_file():
                raise Refused("--publication names no file")
            child["STAGE_PUBLICATION"] = str(publication)
        script = candidate_live_script(udid)
    result = runner(["bash", "-c", script], child, 300.0)
    if result.code != 0:
        raise Refused(f"live launch failed (exit {result.code}); credentials or server missing, staging or simctl failed")


def identity_script(side: str = REFERENCE) -> str:
    """The bash that resolves one half's HA user through the proxy. It reads ``PROXY_URL`` and ``PROXY_CERT`` from its environment,
    loads the token in a child (``hass_creds.sh``) and, for the candidate, takes the token variable the preview is launched with
    (``FENTON_PREVIEW_HA_TOKEN``, else the credentials' own), so each half is asked as its own session. Prints one line: the user
    id's hash. No secret is in this text."""
    creds = shlex.quote(str(REPO / "tools" / "hass_creds.sh"))
    program = " ".join(shlex.quote(p) for p in (sys.executable, str(IDENTITY_SCRIPT)))
    return "\n".join([
        "set -euo pipefail",
        f"source {creds}",
        "hass_load_creds || exit 2",
        "hass_require_creds || exit 2",
        *(['export FENTON_HASS_TOKEN="${FENTON_PREVIEW_HA_TOKEN:-$FENTON_HASS_TOKEN}"'] if side == CANDIDATE else []),
        '[[ -n "${PROXY_URL:-}" && -n "${PROXY_CHAIN:-}" ]] || { echo "no proxy url or certificate chain" >&2; exit 2; }',
        f'exec {program} --proxy "$PROXY_URL" --chain "$PROXY_CHAIN"',
    ])


def resolve_identity(proxy_url: Optional[str], proxy_cert: Optional[Path], runner: Runner = run,
                     env: Optional[Mapping[str, str]] = None, side: str = REFERENCE) -> str:
    """The hash of the HA user id ``side``'s session token resolves to (``auth/current_user`` through the proxy), for its sidecars.

    Only the hash comes back: the child prints nothing else, and the name never leaves ``identity.py``.
    """
    child = dict(os.environ if env is None else env)
    require_go(child)
    require_tls_proxy(proxy_url, proxy_cert)
    child["PROXY_URL"] = str(proxy_url)
    child["PROXY_CHAIN"] = str(Path(str(proxy_cert)).with_name(tls.CHAIN_NAME))
    result = runner(["bash", "-c", identity_script(side)], child, 60.0)
    digest = result.out.strip()
    if result.code != 0 or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise Refused(f"could not resolve the session's user through the proxy (exit {result.code})")
    return digest


#: Credentials the proxy never needs (it forwards the client's own ``auth``); stripped from its environment before it starts.
PROXY_UNNEEDED_SECRETS = ("FENTON_HASS_TOKEN", "FENTON_HASS_PASSWORD", "FENTON_HASS_USERNAME")


def proxy_script(log: Path, listen: str, command: Optional[List[str]] = None,
                 certfile: Optional[Path] = None, keyfile: Optional[Path] = None) -> str:
    """The bash that loads the upstream address from the credentials file and execs the guard proxy (nothing is printed).

    The token, password and username are unset before the ``exec``: the long-lived proxy needs only ``FENTON_HASS_SERVER``.
    ``command`` replaces the proxy program (tests). With ``certfile`` and ``keyfile`` the proxy serves TLS.
    """
    creds = shlex.quote(str(REPO / "tools" / "hass_creds.sh"))
    proxy = command or [sys.executable, str(Path(__file__).with_name("guard_proxy.py")), "--listen", listen, "--log", str(log)]
    if not command and certfile and keyfile:
        proxy += ["--certfile", str(certfile), "--keyfile", str(keyfile)]
    return (f"source {creds}; hass_load_creds || exit 2; hass_require_creds || exit 2; unset {' '.join(PROXY_UNNEEDED_SECRETS)}; exec "
            + " ".join(shlex.quote(p) for p in proxy))


def run_proxy(log: Path, listen: str, env: Optional[Mapping[str, str]] = None, runner: Runner = run) -> int:
    """Run the guard proxy as a child, started with the go and the credentials file's server, serving TLS.

    The log path must be ignored by git: even a templated log is house traffic and must not be committable. A throwaway
    name-constrained CA and leaf are made beside the log (so in the same ignored folder); the CA path is printed (it is the
    ``--proxy-cert`` the launches trust) and the leaf key is deleted when the proxy exits.
    """
    child = {k: v for k, v in dict(os.environ if env is None else env).items() if k not in PROXY_UNNEEDED_SECRETS}
    require_go(child)
    if not log_is_ignored(log, runner):
        raise Refused("the proxy log must be in a git-ignored folder (for example build/evidence/parity-loop/<run>/)")
    bundle = tls.make_certificate(Path(log).parent, runner)
    print(f"proxy certificate: {bundle.ca}", flush=True)
    return supervise(["bash", "-c", proxy_script(log, listen, certfile=bundle.chain, keyfile=bundle.key)], child, bundle)


def supervise(argv: List[str], env: Mapping[str, str], bundle: tls.Bundle) -> int:
    """Run the proxy as a child and delete its private key when it exits, however it ends (a signal stops the child first)."""
    process = subprocess.Popen(argv, env=dict(env))
    previous = {s: signal.signal(s, lambda *_: process.terminate()) for s in (signal.SIGTERM, signal.SIGINT)}
    try:
        return process.wait()
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)
        tls.remove_key(bundle)


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
    lv.add_argument("--proxy-cert", type=Path, help="the certificate the proxy printed at start")
    lv.add_argument("--publication", type=Path, help="candidate only: stage this local envelope (a draft) instead of the live one")
    idn = sub.add_parser("identity")
    idn.add_argument("--side", choices=APPS, default=REFERENCE)
    idn.add_argument("--proxy-url", required=True)
    idn.add_argument("--proxy-cert", type=Path, required=True)
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
            launch_live(args.side, args.udid, args.proxy_url, proxy_cert=args.proxy_cert, publication=args.publication)
        elif args.verb == "identity":
            print(resolve_identity(args.proxy_url, args.proxy_cert, side=args.side))
        else:
            return run_proxy(args.log, args.listen)
    except (Refused, tls.CertificateError) as error:
        print(f"launch: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
