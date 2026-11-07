#!/usr/bin/env python3
"""House-data lint: find house data and secret-shaped strings in tracked files (plan step 11).

The aim is a repository that can go public with no house data and no secrets. The scan reads every tracked text file
(`git ls-files`) and flags:

- ``entity``: a Home Assistant ``domain.object_id`` literal that is not a ``demo_`` id, a generic or test id, or on the allowlist;
- ``ipv4``: a private (RFC 1918 or CGNAT) address; ``ipv6``: a unique-local IPv6 address (the fc and fd ranges, so Tailscale's own prefix too); ``tailnet``: a ``*.ts.net`` host; ``localhost``: a ``*.local`` host other
  than ``example.local``;
- ``vin``: a 17-character VIN-shaped string; ``hex``: a 32- or 40-digit hex string that is not a git object of this
  repository, an action pin (``@<sha>``) or an allowlisted non-secret;
- ``reponame``: the private request repository's name (assembled in code so this file does not carry it);
- ``denylist``: a term from the owner's local denylist (``~/.config/fenton-hass/house_denylist.txt``, one term per line, ``#``
  comments; or the file ``HOUSE_SCAN_DENYLIST`` names; failing that ``~/hass-agents/house_denylist.txt``, which agents can write). The list is house data, never committed; with no file the rule is skipped.

``contracts/house_scan.json`` holds the allowlist and the **debt**: path prefixes whose existing hits are tolerated, each with a
reason and the tracked ledger check that clears it. A hit outside every debt prefix fails the check.

Output is counts and ``path:line rule`` only; a matched value is never printed.

    python3 tools/house_scan.py            # check: exit 1 on a hit outside the debt
    python3 tools/house_scan.py report     # counts per rule and per debt entry (also lists hits outside the debt)
    python3 tools/house_scan.py baseline   # hit counts by top-level path prefix, to write debt entries from
    python3 tools/house_scan.py denylist [--root DIR] [--required-from CONFIG]   # local denylist only: exit 1 on a hit, 3 when missing and required [--base-ref REF | --base-root DIR]
    ... [--config FILE]    # judge --root by this allowlist (the trusted base's), not the tree's own [--mode text|denylist|all] [--min-terms N]

Standard library only. Documentation: .agents/workflow/ci.md (repo checks).
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, NamedTuple, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "contracts" / "house_scan.json"
#: Where the local denylist lives when ``HOUSE_SCAN_DENYLIST`` is unset.
DENYLIST_DEFAULT = Path.home() / ".config" / "fenton-hass" / "house_denylist.txt"
#: The second default, for agents: they cannot write under the first folder (hooks protect it). First existing file wins.
DENYLIST_AGENT_DEFAULT = Path.home() / "hass-agents" / "house_denylist.txt"
MAX_BYTES = 1_000_000
#: Property lists, vector images and privacy manifests are text; only the denylist rule reads them (a term hides there), the other rules keep
#: skipping them so the recorded baselines hold.
TEXT_LIKE_SUFFIXES = frozenset({".plist", ".svg", ".xcprivacy"})
#: ``mode="all"`` (the go-public gate) reads every file whatever its suffix, to this size.
ALL_MODE_MAX_BYTES = 50_000_000
BINARY_SUFFIXES = frozenset({".png", ".jpg", ".jpeg", ".gif", ".heic", ".pdf", ".ttf", ".otf", ".mp4", ".mov", ".zip", ".icns",
                             ".car", ".a", ".xcprivacy", ".plist", ".ipa", ".woff", ".woff2", ".webp", ".svg"})
#: Source files where an id is only a house literal inside a string (elsewhere it is property access).
CODE_SUFFIXES = frozenset({".swift", ".py", ".sh", ".js", ".ts"})
#: Line-comment marker per code suffix: an id in a comment counts too (a comment is prose, so the whole comment is scanned).
COMMENT_MARK = {".swift": r"(?<!:)//", ".js": r"(?<!:)//", ".ts": r"(?<!:)//", ".py": "#", ".sh": "#"}

#: Home Assistant entity domains. ``domain.object_id`` is a house literal only for these.
DOMAINS = frozenset("""alarm_control_panel automation binary_sensor button calendar camera climate conversation counter cover
device_tracker event fan group humidifier image input_boolean input_button input_datetime input_number input_select input_text
lawn_mower light lock media_player notify number person remote scene schedule script select sensor siren stt sun switch text
timer todo tts update vacuum valve water_heater weather zone""".split())

# MARK: - Rules

_PRIVATE_IP = re.compile(
    r"(?<![\w.])(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}"
    r"|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3})(?![\w.]*\w)")
_IPV6_ULA = re.compile(r"(?<![\w:])f[cd][0-9a-f]{2}(?::[0-9a-f]{0,4}){2,}", re.I)
_TAILNET = re.compile(r"(?<![\w.-])[\w-]+(?:\.[\w-]+)*\.ts\.net\b", re.I)
_LOCAL_HOST = re.compile(r"(?<![\w.-])((?:[A-Za-z0-9][A-Za-z0-9-]*\.)*[A-Za-z0-9][A-Za-z0-9-]*)\.local(?![\w(-]|\.\w)", re.I)
_INTERPOLATION = re.compile(r"\{[^{}\n]*\}")
_VIN = re.compile(r"(?<![0-9A-Za-z])[A-HJ-NPR-Z0-9]{17}(?![0-9A-Za-z])", re.I)
_HEX = re.compile(r"(?<![0-9A-Za-z@])(?:[0-9a-f]{40}|[0-9a-f]{32})(?![0-9A-Za-z])", re.I)
_ENTITY = re.compile(r"(?<![\w.])(" + "|".join(sorted(DOMAINS, key=len, reverse=True)) + r")\.([a-z0-9][a-z0-9_]*)\b"
                     r"(?!\.(?:md|json|swift|py|sh|yml|yaml|txt|png|html|plist)\b)")
_STRING = re.compile(r"\"(?:[^\"\\\n]|\\.)*\"|'(?:[^'\\\n]|\\.)*'|`[^`\n]*`")
#: The private request repository's name, assembled so the tool's own source does not carry it.
REPO_NAME = re.compile("fenton-hass-" + "requests", re.I)
#: Escapes that spell a character in source text: ``\\uXXXX`` (JSON, JavaScript, Python), ``\\u{X...}`` (Swift), ``\\xHH``
#: (Python, JavaScript) and the numeric HTML references ``&#46;`` and ``&#x2e;``. A copy of the line with them decoded is scanned
#: too, so an escaped dot cannot hide an id.
_ESCAPES = re.compile(r"\\u\{([0-9a-fA-F]{1,8})\}|\\u([0-9a-fA-F]{4})|\\x([0-9a-fA-F]{2})|&#[xX]([0-9a-fA-F]{1,6});|&#(\d{1,7});")
#: The one file whose own ``allow`` section may spell ids with escapes: they are allowlist entries, which the base scan
#: must not read as ids (see ``contracts/house_scan.json``).
CONFIG_REL = "contracts/house_scan.json"


#: Object ids that are really member or method names in prose and code (``zone.id``, ``counter.values()``).
GENERIC_MEMBERS = ("id", "name", "values", "keys", "items", "count", "first", "last", "value", "state", "title", "text", "strip",
                   "com", "org", "io", "net", "png", "jpg", "pdf", "json", "plist", "md", "swift", "py", "sh", "yml", "yaml", "txt", "html")


class Hit(NamedTuple):
    """One finding: where, and which rule. The matched text is deliberately not kept."""

    path: str
    line: int
    rule: str


class Config(NamedTuple):
    """The parsed ``contracts/house_scan.json``."""

    object_id_prefixes: Tuple[str, ...]
    object_id_words: Tuple[str, ...]
    object_ids: Set[str]
    hosts: Set[str]
    hex_values: Set[str]
    hex_paths: Tuple[str, ...]
    skip_prefixes: Tuple[str, ...]
    debt: List[dict]
    generic: Tuple[str, ...] = ()
    #: Whole service names (``light.turn_on``): the object id must equal one, never merely contain it.
    services: Tuple[str, ...] = ()
    #: Exact addresses (``allow.addresses``) that are not house data, such as the generic ones a private-range test needs. Never a range.
    addresses: Tuple[str, ...] = ()


def parse_addresses(entries: Sequence[object], denylist: Sequence[re.Pattern] = ()) -> Tuple[str, ...]:
    """The ``allow.addresses`` entries as normalized exact addresses.

    Raises:
        ValueError: an entry is not a single IPv4 or IPv6 address (a range, a prefix or a word), or matches a term of the private
            local ``denylist`` (the owner keeps their own network's prefix there, so it can never be allowed here)."""
    out: List[str] = []
    for entry in entries:
        try:
            address = str(ipaddress.ip_address(str(entry).strip()))
        except ValueError:
            raise ValueError(f"allow.addresses entry is not a single address: {entry!r}") from None
        if any(pattern.search(address) for pattern in denylist):
            raise ValueError("allow.addresses lists an address that matches the private denylist")
        out.append(address)
    return tuple(out)


def address_is_allowed(text: str, cfg: "Config") -> bool:
    """Is ``text`` (a match of the ipv4 or ipv6 rule) exactly one of the allowed addresses? A neighbour of one is not."""
    try:
        return str(ipaddress.ip_address(text)) in cfg.addresses
    except ValueError:
        return False


def load_config(path: Path = CONFIG_PATH) -> Config:
    """Read the allowlist and debt file; a missing file is an empty configuration."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    allow = data.get("allow", {})
    return Config(
        tuple(allow.get("object_id_prefixes", ["demo_"])),
        tuple(allow.get("object_id_words", ["test", "example", "fixture", "sample", "placeholder"])),
        set(allow.get("object_ids", [])),
        {h.lower() for h in allow.get("hosts", ["example.local"])},
        {h.lower() for h in allow.get("hex", [])},
        tuple(allow.get("hex_paths", [])),
        tuple(allow.get("skip_prefixes", [])),
        list(data.get("debt", [])),
        tuple(allow.get("generic_members", GENERIC_MEMBERS)),
        tuple(allow.get("services", ["turn_on", "turn_off", "toggle", "add_item", "remove_item", "update_item", "install"])),
        parse_addresses(allow.get("addresses", []), load_denylist() if allow.get("addresses") else ()),
    )


def denylist_source(env: Optional[Dict[str, str]] = None) -> Tuple[Path, str]:
    """``(path, label)`` of the term list in use: ``env`` (``HOUSE_SCAN_DENYLIST``), ``config`` (the config folder's list) or
    ``agents`` (``~/hass-agents/house_denylist.txt``). The label is safe to print; the path never needs to be."""
    env = os.environ if env is None else env
    override = env.get("HOUSE_SCAN_DENYLIST")
    if override:
        return Path(override), "env"
    if DENYLIST_DEFAULT.is_file():
        return DENYLIST_DEFAULT, "config"
    if DENYLIST_AGENT_DEFAULT.is_file():
        return DENYLIST_AGENT_DEFAULT, "agents"
    return DENYLIST_DEFAULT, "config"


def load_denylist(env: Optional[Dict[str, str]] = None) -> List[re.Pattern]:
    """Compile the owner's local term list (case-insensitive, whole-word); empty when no file exists."""
    path, _label = denylist_source(env)
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
        mode = path.stat().st_mode & 0o777
    except OSError:
        return []
    if mode & 0o077:
        print(f"house_scan: warning: denylist {path} has mode {mode:03o}, expected 600", file=sys.stderr)
    terms = [t.strip() for t in lines if t.strip() and not t.strip().startswith("#")]
    return [re.compile(r"(?<![0-9A-Za-z])" + re.escape(t) + r"(?![0-9A-Za-z])", re.I) for t in terms]


def entity_is_allowed(domain: str, object_id: str, cfg: Config) -> bool:
    """Is ``domain.object_id`` a demo, generic or test id (or listed)? Allow words match whole ``_`` tokens, never substrings."""
    full = f"{domain}.{object_id}"
    if full in cfg.object_ids or object_id.startswith(cfg.object_id_prefixes) or object_id in cfg.generic or object_id in cfg.services:
        return True
    padded = f"_{object_id}_"
    return any(f"_{word}_" in padded for word in cfg.object_id_words)


def entity_zones(line: str, suffix: str) -> List[str]:
    """The parts of ``line`` where an entity-id match counts. Prose and data files: the whole line. Code: string literals (with
    ``{...}`` interpolations blanked, so ``f"{counter.values()}"`` is not an id) and the line comment, where prose names ids."""
    if suffix not in CODE_SUFFIXES:
        return [line]
    zones = [_INTERPOLATION.sub(lambda m: " " * len(m.group(0)), m.group(0)) for m in _STRING.finditer(line)]
    mark = re.search(COMMENT_MARK[suffix], line)
    if mark:
        zones.append(line[mark.start():])
    return zones


def decode_escapes(line: str) -> str:
    """``line`` with the escapes of :data:`_ESCAPES` replaced by their characters (an out-of-range code point is left as written)."""
    def one(m: "re.Match[str]") -> str:
        for group, base in ((1, 16), (2, 16), (3, 16), (4, 16), (5, 10)):
            digits = m.group(group)
            if digits is not None:
                code = int(digits, base)
                return chr(code) if code <= 0x10FFFF else m.group(0)
        return m.group(0)
    return _ESCAPES.sub(one, line)


def _line_hits(path: str, number: int, line: str, suffix: str, cfg: Config, denylist: Sequence[re.Pattern], known: Set[str],
               whole_line: bool = False) -> List[Hit]:
    """Every finding on one line. ``whole_line`` reads the entire line as prose (the decoded copy: an escaped quote may have moved
    the string boundaries, so the zones of the raw line no longer say where an id counts)."""
    hits: List[Hit] = []
    if not denylist and "." not in line and ":" not in line and len(line) < 17:
        return hits  # nothing below can match a line this short without a dot, a colon or 17 characters
    for zone in ([line] if whole_line else entity_zones(line, suffix)):
        for m in _ENTITY.finditer(zone):
            if zone[m.end():m.end() + 1] == "(":
                continue  # a method call such as ``counter.values()``
            if not entity_is_allowed(m.group(1), m.group(2), cfg):
                hits.append(Hit(path, number, "entity"))
    hits.extend(Hit(path, number, "ipv4") for m in _PRIVATE_IP.finditer(line) if not address_is_allowed(m.group(0), cfg))
    hits.extend(Hit(path, number, "ipv6") for m in _IPV6_ULA.finditer(line) if not address_is_allowed(m.group(0), cfg))
    lowered = line.lower()
    if ".ts.net" in lowered:
        hits.extend(Hit(path, number, "tailnet") for _ in _TAILNET.finditer(line))
    if ".local" in lowered:
        hits.extend(Hit(path, number, "localhost") for m in _LOCAL_HOST.finditer(line)
                    if f"{m.group(1)}.local".lower() not in cfg.hosts)
    for m in _VIN.finditer(line):
        token = m.group(0)
        if token != token.upper() and token != token.lower():
            continue  # mixed case is base64 or a hash, not a VIN (a VIN is all upper, or all lower inside a lowercase id)
        if sum(c.isdigit() for c in token) >= 3 and sum(c.isalpha() for c in token) >= 3:
            hits.append(Hit(path, number, "vin"))
    for m in _HEX.finditer(line):
        token = m.group(0).lower()
        if len(set(token)) <= 4 or path.startswith(cfg.hex_paths):
            continue  # a placeholder such as forty of one digit, or a path whose hex strings are known non-secrets
        if token not in cfg.hex_values and token not in known:
            hits.append(Hit(path, number, "hex"))
    if "requests" in lowered:
        hits.extend(Hit(path, number, "reponame") for _ in REPO_NAME.finditer(line))
    for pattern in denylist:
        hits.extend(Hit(path, number, "denylist") for _ in pattern.finditer(line))
    return hits


def scan_text(path: str, text: str, cfg: Config, denylist: Sequence[re.Pattern] = (), git_objects: Optional[Set[str]] = None) -> List[Hit]:
    """Every finding in one file's text. ``git_objects`` are hex strings known to be commits or objects of this repository.

    Each line is scanned as written and, when it holds an escape (see :func:`decode_escapes`), again decoded; the hits are the
    union, a rule counting the larger of the two scans on that line. The raw scan is kept because decoding can move string
    boundaries (an escaped quote), so it must never replace it. In ``contracts/house_scan.json`` the ``allow`` section is
    not decoded: its entries are written with escapes so the scan, judging the file by the base allowlist, does not read them as ids."""
    hits: List[Hit] = []
    suffix = Path(path).suffix
    known = git_objects or set()
    in_allow = False
    for number, line in enumerate(text.splitlines(), 1):
        if path == CONFIG_REL:
            if line.startswith('  "allow"'):
                in_allow = True
            elif in_allow and line.startswith("  }"):
                in_allow = False
        raw = _line_hits(path, number, line, suffix, cfg, denylist, known)
        decoded = decode_escapes(line) if not in_allow else line
        if decoded == line:
            hits.extend(raw)
            continue
        counts_raw = Counter(h.rule for h in raw)
        extra = _line_hits(path, number, decoded, suffix, cfg, denylist, known, whole_line=True)
        counts_dec = Counter(h.rule for h in extra)
        hits.extend(raw)
        for rule, n in counts_dec.items():
            hits.extend(Hit(path, number, rule) for _ in range(max(0, n - counts_raw.get(rule, 0))))
    return hits


# MARK: - Repository walk

def tracked_files(root: Path = ROOT) -> List[str]:
    """Tracked paths from ``git ls-files`` (the working tree, so uncommitted edits are scanned too)."""
    if not (root / ".git").exists():  # a snapshot or an extracted archive: every file below it
        return sorted(str(p.relative_to(root)) for p in root.rglob("*") if p.is_file() and ".git" not in p.relative_to(root).parts)
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=True).stdout
    return [p for p in out.decode("utf-8", "replace").split("\0") if p]


def git_known(root: Path, candidates: Set[str]) -> Set[str]:
    """Which candidate hex strings name an object in this repository (commits quoted in docs are not secrets)."""
    if not candidates or not (root / ".git").exists():
        return set()
    ordered = sorted(candidates)
    proc = subprocess.run(["git", "-C", str(root), "cat-file", "--batch-check"], input="\n".join(ordered) + "\n",
                          capture_output=True, text=True)
    return {c for c, row in zip(ordered, proc.stdout.splitlines()) if not row.endswith("missing")}


def readable(root: Path, rel: str, cfg: Config, mode: str = "text") -> Optional[str]:
    """The file's text, or None for binary, huge, skipped, missing or non-UTF-8 files.

    ``mode``: ``text`` (the default), ``denylist`` (also reads :data:`TEXT_LIKE_SUFFIXES`) or ``all`` (every suffix, ``skip_prefixes``
    ignored, to :data:`ALL_MODE_MAX_BYTES`, bytes that are not UTF-8 decoded lossily: nothing is skipped as binary)."""
    suffix = Path(rel).suffix.lower()
    path = root / rel
    if mode == "all":
        try:
            if not path.is_file() or path.is_symlink() or path.stat().st_size > ALL_MODE_MAX_BYTES:
                return None
            data = path.read_bytes()
        except OSError:
            return None
        text = data.decode("utf-8", "replace")
        if data[:2] in (b"\xff\xfe", b"\xfe\xff") or b"\x00" in data[:4096]:  # UTF-16 text: scan its decode too
            for codec in ("utf-16", "utf-16-le", "utf-16-be"):
                try:
                    text += "\n" + data.decode(codec)
                except UnicodeDecodeError:
                    continue
        return text
    if (suffix in BINARY_SUFFIXES and not (mode == "denylist" and suffix in TEXT_LIKE_SUFFIXES)) or rel.startswith(cfg.skip_prefixes):
        return None
    try:
        if not path.is_file() or path.stat().st_size > MAX_BYTES:
            return None
        return path.read_bytes().decode("utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def oversize_files(root: Path, limit: Optional[int] = None) -> List[str]:
    """Tracked regular files larger than ``limit`` bytes: ``readable(mode="all")`` cannot scan them, so the go-public gate refuses them."""
    limit = ALL_MODE_MAX_BYTES if limit is None else limit
    found = []
    for rel in tracked_files(root):
        path = root / rel
        try:
            if path.is_file() and not path.is_symlink() and path.stat().st_size > limit:
                found.append(rel)
        except OSError:
            found.append(rel)
    return found


def scan_repo(root: Path = ROOT, cfg: Optional[Config] = None, denylist: Optional[Sequence[re.Pattern]] = None,
              mode: str = "text") -> List[Hit]:
    """Scan every tracked text file under ``root`` with ``cfg`` (default: the tree's own ``contracts/house_scan.json``; callers that
    judge somebody else's tree pass the trusted base's). ``mode`` is :func:`readable`'s."""
    cfg = cfg or load_config(root / "contracts" / "house_scan.json")
    denylist = load_denylist() if denylist is None else denylist
    texts = {}
    for rel in tracked_files(root):
        text = readable(root, rel, cfg, mode)
        if text is not None:
            texts[rel] = text
    candidates = {m.group(0).lower() for t in texts.values() for m in _HEX.finditer(t)}
    known = git_known(root, candidates)
    hits: List[Hit] = []
    for rel, text in texts.items():
        hits.extend(scan_text(rel, text, cfg, denylist, known))
    return hits


# MARK: - Debt

def debt_entry(path: str, debt: Sequence[dict]) -> Optional[dict]:
    """The debt entry whose ``path`` prefix covers ``path`` (longest prefix wins)."""
    best = None
    for entry in debt:
        prefix = str(entry.get("path", ""))
        if prefix and (path == prefix or path.startswith(prefix.rstrip("/") + "/") or (prefix.endswith("/") and path.startswith(prefix))):
            if best is None or len(prefix) > len(str(best["path"])):
                best = entry
    return best


def validate_debt(debt: Sequence[dict]) -> List[str]:
    """Every debt entry needs a path, a reason and a ledger check id; returns the problems."""
    problems = []
    for i, entry in enumerate(debt):
        for key in ("path", "reason", "check"):
            if not str(entry.get(key, "")).strip():
                problems.append(f"debt[{i}] has no {key}")
    return problems


def ratchet(covered: Dict[str, Counter], debt: Sequence[dict]) -> Tuple[List[str], List[str]]:
    """Compare each debt entry's hit counts with its ``baseline``, a ``{rule: count}`` ceiling. Returns (problems, notes): a rule's
    count above its baseline is a problem (new house data in a debt area, and a swap of one kind of hit for another fails
    too); a count below is a note to lower the baseline. An entry with no ``baseline`` mapping of integers is a problem, so
    the ceiling cannot be skipped."""
    problems: List[str] = []
    notes: List[str] = []
    for entry in debt:
        path = str(entry.get("path", ""))
        base = entry.get("baseline")
        if not isinstance(base, dict) or not all(isinstance(n, int) and not isinstance(n, bool) for n in base.values()):
            problems.append(f"debt {path} has no per-rule baseline mapping")
            continue
        counts = covered.get(path, Counter())
        for rule in sorted(set(base) | set(counts)):
            have, ceiling = counts.get(rule, 0), base.get(rule, 0)
            if have > ceiling:
                problems.append(f"debt {path} grew: {rule} {have} hits, baseline {ceiling} (new house data in a debt area)")
            elif have < ceiling:
                notes.append(f"debt {path} {rule} is down to {have} (baseline {ceiling}): lower the baseline in contracts/house_scan.json")
    return problems, notes


def split_hits(hits: Sequence[Hit], debt: Sequence[dict]) -> Tuple[Dict[str, Counter], List[Hit]]:
    """Hits grouped by the debt entry that covers them, and the hits that no entry covers."""
    covered: Dict[str, Counter] = {}
    new: List[Hit] = []
    for hit in hits:
        entry = debt_entry(hit.path, debt)
        if entry is None:
            new.append(hit)
        else:
            covered.setdefault(str(entry["path"]), Counter())[hit.rule] += 1
    return covered, new


def baseline(hits: Sequence[Hit], depth: int = 2) -> Dict[str, Counter]:
    """Hit counts per rule by path prefix of ``depth`` components (to write debt entries from)."""
    table: Dict[str, Counter] = {}
    for hit in hits:
        key = "/".join(hit.path.split("/")[:depth])
        table.setdefault(key, Counter())[hit.rule] += 1
    return table


# MARK: - Command line

def render(hits: Sequence[Hit], cfg: Config, denylist_active: bool, show_all: bool) -> Tuple[List[str], int]:
    """Report lines and the exit code (1 when a hit lies outside the debt, a rule outgrows its baseline or a debt entry is
    malformed). Local denylist hits are the owner's own list: counted and located apart, never against the CI baselines."""
    denied = [h for h in hits if h.rule == "denylist"]
    hits = [h for h in hits if h.rule != "denylist"]
    covered, new = split_hits(hits, cfg.debt)
    lines = [f"house_scan: {len(hits)} hit(s); {len(hits) - len(new)} in recorded debt, {len(new)} new "
             f"(local denylist {'on' if denylist_active else 'off'})"]
    if denylist_active:
        lines.append(f"  local denylist: {len(denied)} hit(s), not counted against the baselines")
        if show_all:
            lines.extend(f"    {h.path}:{h.line} denylist" for h in denied)
    for path, counter in sorted(covered.items()):
        entry = next(e for e in cfg.debt if e["path"] == path)
        detail = ", ".join(f"{r}={n}" for r, n in sorted(counter.items()))
        lines.append(f"  debt {path}: {sum(counter.values())} ({detail}) -> {entry['check']}")
    problems = validate_debt(cfg.debt)
    grew, notes = ratchet(covered, cfg.debt)
    problems = problems + grew
    lines.extend(f"  config: {p}" for p in problems)
    lines.extend(f"  note: {n}" for n in notes)
    if new:
        lines.append("  new hits outside the debt (path:line rule):")
        shown = new if show_all else new[:200]
        lines.extend(f"    {h.path}:{h.line} {h.rule}" for h in shown)
        if len(shown) < len(new):
            lines.append(f"    ... {len(new) - len(shown)} more")
    return lines, 1 if (new or problems) else 0


#: Exit code of the ``denylist`` command when the list is not loaded and the caller requires it.
EXIT_NOT_LOADED = 3


def denylist_required(config_path: Path) -> bool:
    """The ``denylist_required`` key of a triage config (default false; unreadable means false)."""
    try:
        return json.loads(config_path.read_text(encoding="utf-8")).get("denylist_required") is True
    except (OSError, ValueError, AttributeError):
        return False


def archive_to(root: Path, ref: str, target: Path) -> bool:
    """Extract ``ref`` of the git repository at ``root`` into ``target``; False when git cannot (an unknown ref)."""
    proc = subprocess.run(["git", "-C", str(root), "archive", "--format=tar", ref], capture_output=True)
    if proc.returncode:
        return False
    return subprocess.run(["tar", "-x", "-C", str(target)], input=proc.stdout).returncode == 0


def new_hits(hits: Sequence[Hit], base_hits: Sequence[Hit]) -> List[Hit]:
    """The hits a change adds: per path, the head's count beyond the base's (the last ones in the file, since lines shift)."""
    base_count = Counter(h.path for h in base_hits)
    by_path: Dict[str, List[Hit]] = {}
    for hit in hits:
        by_path.setdefault(hit.path, []).append(hit)
    added: List[Hit] = []
    for path, found in by_path.items():
        extra = len(found) - base_count.get(path, 0)
        if extra > 0:
            added.extend(sorted(found, key=lambda h: h.line)[-extra:])
    return sorted(added, key=lambda h: (h.path, h.line))


def denylist_command(root: Path, required: bool, base_root: Optional[Path] = None, base_ref: Optional[str] = None,
                     config: Optional[Path] = None, mode: str = "denylist", min_terms: int = 0) -> int:
    """Scan ``root`` for the local denylist only and print counts and ``path:line`` (never a term). Exit 0 clean, 1 on a hit,
    ``EXIT_NOT_LOADED`` when the list is missing and ``required``; a missing list that is optional only warns.

    Every denylist hit counts, whether or not its path is recorded debt in ``contracts/house_scan.json``. With ``base_root`` (or
    ``base_ref`` of the git repository at ``root``) only the hits the change adds against that base count, so debt that is still
    being scrubbed does not block every change; a base that cannot be read counts every hit as new.

    ``config`` is the allowlist file to judge ``root`` by: pass the trusted base's, never the tree under review (its own
    ``skip_prefixes`` could hide its hits); both trees are scanned with it. ``mode`` is :func:`readable`'s (``denylist`` reads
    plists and SVGs too; the go-public gate uses ``all``). ``min_terms`` refuses (``EXIT_NOT_LOADED``) a list shorter than that.
    """
    import tempfile
    denylist = load_denylist()
    if not denylist:
        print("house_scan: denylist not loaded" + (" (required)" if required else " (optional, continuing)"))
        return EXIT_NOT_LOADED if required else 0
    _path, source = denylist_source()
    print(f"house_scan: denylist source {source}, {len(denylist)} term(s)")
    if len(denylist) < min_terms:
        print(f"house_scan: denylist has {len(denylist)} term(s), fewer than the {min_terms} required")
        return EXIT_NOT_LOADED
    label = ""
    with tempfile.TemporaryDirectory() as tmp:
        if base_ref and base_root is None:
            base_root = Path(tmp) if archive_to(root, base_ref, Path(tmp)) else None
            if base_root is None:
                print(f"house_scan: base {base_ref} unreadable, counting every hit as new")
        # With a base the change is judged by the base's config (layer 1 never trusts the tree it scans); with none, by its own.
        path = config or ((base_root / "contracts" / "house_scan.json") if base_root is not None else root / "contracts" / "house_scan.json")
        cfg = load_config(path)
        hits = [h for h in scan_repo(root, cfg, denylist, mode) if h.rule == "denylist"]
        if base_root is not None:
            base_hits = [h for h in scan_repo(base_root, cfg, denylist, mode) if h.rule == "denylist"]
            hits = new_hits(hits, base_hits)
            label = " new"
    print(f"house_scan: denylist loaded, {len(hits)}{label} hit(s)")
    for hit in hits[:50]:
        print(f"  {hit.path}:{hit.line} denylist")
    big = oversize_files(root) if mode == "all" else []
    if big:  # a file the scan cannot read is not a clean file
        print(f"house_scan: {len(big)} file(s) over {ALL_MODE_MAX_BYTES // 1_000_000} MB cannot be scanned (refusing)")
        for rel in big[:20]:
            print(f"  {rel} oversize")
    return 1 if hits or big else 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="house_scan.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("command", nargs="?", default="check", choices=("check", "report", "baseline", "denylist"))
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("--required", choices=("true", "false"), help="denylist: refuse when the list is missing")
    parser.add_argument("--required-from", help="denylist: read the denylist_required key of this triage config")
    parser.add_argument("--base-root", help="denylist: count only the hits added against the tree in this directory")
    parser.add_argument("--base-ref", help="denylist: count only the hits added against this ref of the git repository at --root")
    parser.add_argument("--config", help="allowlist and debt file to judge --root by (default: the tree's own); pass the trusted base's "
                                         "when --root is a change under review")
    parser.add_argument("--mode", choices=("text", "denylist", "all"), default="denylist", help="denylist: which files are read (all: every suffix)")
    parser.add_argument("--min-terms", type=int, default=0, help="denylist: refuse a term list shorter than this")
    args = parser.parse_args(argv)
    root = Path(args.root)
    config = Path(args.config) if args.config else None
    if args.command == "denylist":
        required = args.required == "true" or (args.required is None and bool(args.required_from) and denylist_required(Path(args.required_from)))
        return denylist_command(root, required, Path(args.base_root) if args.base_root else None, args.base_ref, config, args.mode,
                                args.min_terms)
    cfg = load_config(config or root / "contracts" / "house_scan.json")
    denylist = load_denylist()
    hits = scan_repo(root, cfg, denylist)
    if args.command == "baseline":
        for key, counter in sorted(baseline(hits).items()):
            print(f"{key}: {sum(counter.values())} (" + ", ".join(f"{r}={n}" for r, n in sorted(counter.items())) + ")")
        return 0
    lines, code = render(hits, cfg, bool(denylist), args.command == "report")
    print("\n".join(lines))
    return code if args.command == "check" else 0


if __name__ == "__main__":
    sys.exit(main())
