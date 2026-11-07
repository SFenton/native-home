#!/usr/bin/env python3
"""jev_ask: ask TypeSafe Jev a bounded question (stdlib only; any host).

Jev is a System One model: it takes a `state` plus named, typed questions and returns calibrated probabilities.
It never writes, plans or explains. Use it to rank or classify what a text says, then verify the answer yourself;
frontier models still plan and implement. Ported from festival-report-tracker's `fst-decide` (`decide.py`).

    jev_ask.py ask context.patterns --context '{"title": "...", "body": "..."}'    # a registered question
    jev_ask.py ask context.precedents --context-file task.json --item 190="Mockup hub guard" --item 189="Test tiers"
    jev_ask.py yesno  "Does this log show that no test case ever started?" --state-file log.txt
    jev_ask.py choose "Which page owns this behavior?" -o home="Home page" -o settings="Settings" --state "..."
    jev_ask.py score  "How severe is this regression?" -l Cosmetic -l Minor -l Major --state "..."
    jev_ask.py rank   "Is {item} relevant to fixing this?" -i status-pill="A status pill" --state-file task.txt
    jev_ask.py rank   "Does this answer how auth works?" --items-file sections.json    # item text in the state
    jev_ask.py ask research.section_relevant --items-file sections.json --param question="how does auth work?"
    jev_ask.py list | validate | sync [--check] [--only ID]
        # `sync` regenerates context.patterns (patterns registry), learning.home (.agents docs) and
        # research.release_impact (Swift sources, tools/jev_surface.py)

Questions live in `contracts/jev/questions/*.json` (`id`, `version`, `type`, `mode`, `instructions`, `criteria`,
`state`, `accept`). **Bump `version` whenever wording, criteria or state change**: Jev reads literally and the
answers and measurements are attributed to `id@version`.

Output is one JSON object. **Exit 0** = answered (use the answer when `accepted` is true). A noul question with
`accept.yes_above` / `accept.no_below` is accepted outside the band between them (`band`: yes, no or unsure; a
banded set lists its `unsure` options); without bands, accepted means confidence is at least `accept.min_confidence`,
and for a noul confidence is max(p, 1 - p), so 0.5 accepts everything: give noul questions bands. An items file
(`--items-file`, `{name: text}` or `[{id, text}]`) puts each item's text in the state under `items.<id>` and keeps the
question in the instruction; requests are chunked under the 64k/32k token limits and run on at most 8 workers, and
rank ties (the API rounds to 0.01) keep the order of the file. A shadow question is also logged to
`build/jev/shadow.jsonl` (never shown).  **exit 3** = unavailable (no key, network or API error) and callers
must treat that as "no hint" and carry on without it; exit 2 = usage error. The key is read only from a
mode-600 `~/.config/fenton-hass/typesafe.key` (wins when present and non-empty) or else the `TYPESAFE_API_KEY`
environment variable (a stale inherited variable must not beat the owner's current file); it is never printed,
logged or written to a file. The state you pass (issue and PR text, finding text) is sent to TypeSafe. Answers are cached by
model, question and state in `build/jev/cache/`; calls are logged (no state text, no key) to `build/jev/calls.jsonl`.
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import importlib.util
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

# MARK: - Configuration

ROOT = Path(__file__).resolve().parents[1]
QUESTIONS_DIR = ROOT / "contracts" / "jev" / "questions"
ENDPOINT = "https://api.typesafe.ai/v1/systemone"
#: Pinned: thresholds are tuned against one model version (the alias `jev-latest` moves). Override with JEV_MODEL.
MODEL = "jev-1.13.0"
KEY_ENV = "TYPESAFE_API_KEY"
#: Preferred source: a file only the owner can read (mode 600). The environment variable is the fallback.
KEY_FILE = "~/.config/fenton-hass/typesafe.key"
EXIT_UNAVAILABLE = 3
EXIT_USAGE = 2
TIMEOUT = 10.0
MODES = ("off", "shadow", "active")
KINDS = ("noul", "choice", "score", "noul-set")
#: Chunking for requests that put item text in the state (limits: 64k tokens for state + all questions, 32k for
#: state + the longest question; rate limits suggest 8 workers or fewer). Estimates use 3 characters per token.
CHUNK_TOKENS = 12000
CHUNK_ITEMS = 8
MAX_ITEM_CHARS = 24000
WORKERS = 8
PRICE_PER_MILLION_INPUT = 0.042
#: Real (uncached) requests made by this process: `calls`, `input_tokens`. For spend caps in measurements.
USAGE: dict[str, int] = {"calls": 0, "input_tokens": 0}
_USAGE_LOCK = threading.Lock()
NO_KEY = f"no key: put it in a mode-600 {KEY_FILE}, or set {KEY_ENV} in the process environment (never in a repo file)"

Transport = Callable[[dict[str, Any], str, float], dict[str, Any]]


def home() -> Path:
    """Where the cache and call log live (`build/jev`, or `$JEV_HOME`)."""
    return Path(os.environ.get("JEV_HOME") or ROOT / "build" / "jev")


def api_key() -> str:
    """The API key, or `""` (unavailable). Never print or log the result.

    Read from `~/.config/fenton-hass/typesafe.key` (`$JEV_KEY_FILE` overrides the path) when that is a regular,
    non-empty file readable by its owner only and owned by the current user; otherwise from `TYPESAFE_API_KEY`. The file wins so a stale
    variable inherited from a launcher (the desktop app) cannot shadow the current key. A looser file is ignored.
    """
    path = Path(os.environ.get("JEV_KEY_FILE") or KEY_FILE).expanduser()
    try:
        info = path.stat()
        if path.is_file() and not info.st_mode & 0o077 and info.st_uid == os.getuid():
            key = path.read_text(encoding="utf-8").strip()
            if key:
                return key
    except (OSError, UnicodeDecodeError):
        pass
    return os.environ.get(KEY_ENV, "").strip()


def model() -> str:
    """The model id sent with every request."""
    return os.environ.get("JEV_MODEL", "").strip() or MODEL


# MARK: - Answers

@dataclass
class Answer:
    """One API answer: `value` is the bool / option / level index; `confidence` in [0, 1]."""

    type: str
    value: Any
    confidence: float
    probabilities: dict[str, float] = field(default_factory=dict)
    score: float | None = None  # score questions: the probability-weighted level

    def as_dict(self) -> dict[str, Any]:
        return {"type": self.type, "value": self.value, "confidence": round(self.confidence, 4),
                "probabilities": {k: round(v, 4) for k, v in self.probabilities.items()},
                **({"score": round(self.score, 4)} if self.score is not None else {})}


def parse_answer(raw: dict[str, Any]) -> Answer:
    """Normalize one API answer (`noul` becomes a bool with confidence max(p, 1 - p)).

    Raises:
        ValueError: The answer has an unknown type.
    """
    kind = raw.get("type")
    if kind == "noul":
        p = float(raw["noul"])
        return Answer("noul", p >= 0.5, max(p, 1 - p), {"true": p, "false": 1 - p})
    if kind == "choice":
        probs = {str(k): float(v) for k, v in (raw.get("probabilities") or {}).items()}
        choice = str(raw["choice"])
        return Answer("choice", choice, float(raw.get("confidence", probs.get(choice, 0.0))), probs)
    if kind == "score":
        probs = {str(k): float(v) for k, v in (raw.get("probabilities") or {}).items()}
        level = max(probs, key=lambda k: probs[k]) if probs else str(round(float(raw["score"])))
        return Answer("score", int(level), float(raw.get("confidence", probs.get(level, 0.0))), probs,
                      float(raw["score"]))
    raise ValueError(f"unknown answer type {kind!r}")


# MARK: - Client

def _post(body: dict[str, Any], key: str, timeout: float) -> dict[str, Any]:
    request = urllib.request.Request(ENDPOINT, data=json.dumps(body).encode(), method="POST", headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/json", "User-Agent": "fenton-hass-jev/1"})
    with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 (fixed https endpoint)
        return json.loads(response.read())


def cache_key(questions: dict[str, Any], state: Any, model_id: str | None = None) -> str:
    """Stable hash of the model, questions and state; the cache file name and the call-log key."""
    blob = json.dumps({"m": model_id or model(), "q": questions, "s": state}, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(blob.encode()).hexdigest()


def ask(questions: dict[str, dict[str, Any]], state: Any, *, tag: str = "", transport: Transport | None = None,
        use_cache: bool = True, timeout: float = TIMEOUT, log: bool = True) -> dict[str, Answer] | None:
    """Ask `questions` (API shape: name -> {type, instructions, criteria}) about `state` in one request.

    Never raises for model or network trouble.

    Args:
        questions: The API `questions` object.
        state: The `state` (string, object or array).
        tag: Names the caller in the call log (e.g. `route.complexity@1`).
        transport: A replacement for the HTTP call (tests); receives (body, key, timeout).
        use_cache: Read and write `build/jev/cache`.
        timeout: Seconds per HTTP attempt.
        log: Append to `build/jev/calls.jsonl`.

    Returns:
        `{name: Answer}`, or None when no answer is available (no key, network or API error, malformed answer).
    """
    if not questions:
        return {}
    key = cache_key(questions, state)
    path = home() / "cache" / f"{key}.json"
    if use_cache:
        try:
            cached = json.loads(path.read_text())
            return {name: parse_answer(a) for name, a in cached["answers"].items()}
        except (OSError, ValueError, KeyError, TypeError):
            pass
    secret = api_key()
    if not secret and transport is None:
        return None
    body = {"model": model(), "state": state, "questions": questions}
    send = transport or _post
    started, raw, error = time.monotonic(), None, ""
    for attempt in range(2):
        try:
            raw = send(body, secret, timeout)
            break
        except urllib.error.HTTPError as exc:
            error = f"HTTP {exc.code}"
            if exc.code < 500 and exc.code != 429:
                break
        except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError, ValueError) as exc:
            error = type(exc).__name__
        if attempt == 0:
            time.sleep(0.5)
    answers: dict[str, Answer] | None = None
    if raw is not None:
        with _USAGE_LOCK:
            USAGE["calls"] += 1
            USAGE["input_tokens"] += int((raw.get("usage") or {}).get("input_tokens") or 0)
        try:
            answers = {name: parse_answer(raw["answers"][name]) for name in questions}
        except (KeyError, TypeError, ValueError) as exc:
            error, answers = f"bad answer: {type(exc).__name__}", None
    if log:
        _log_call(tag, key, int((time.monotonic() - started) * 1000), raw, answers, error)
    if answers is not None and use_cache:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({"answers": raw["answers"], "model": raw.get("model")}))
        except OSError:
            pass
    return answers


def _log_call(tag: str, key: str, latency_ms: int, raw: dict[str, Any] | None, answers: dict[str, Answer] | None,
              error: str) -> None:
    usage = (raw or {}).get("usage") or {}
    record = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "tag": tag, "key": key[:16],
              "latency_ms": latency_ms, "input_tokens": usage.get("input_tokens"),
              "model": (raw or {}).get("model"), "error": error or None, "answers": len(answers or {})}
    try:
        path = home() / "calls.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as handle:
            handle.write(json.dumps(record, sort_keys=True) + "\n")
    except OSError:
        pass


# MARK: - Questions

@dataclass
class Decision:
    """A question's folded answer."""

    question: "Question"
    value: Any
    confidence: float
    probabilities: dict[str, float]
    score: float | None = None
    extras: dict[str, float] = field(default_factory=dict)  # companion noul name -> P(yes)

    @property
    def unsure(self) -> list[str]:
        """Banded sets: the options between `no_below` and `yes_above` (no verdict)."""
        q = self.question
        if not q.banded or not q.is_set:
            return []
        return sorted(k for k, p in self.probabilities.items() if q.band(p) == "unsure")

    @property
    def accepted(self) -> bool:
        """Confident enough to use.

        A banded noul (`accept.yes_above` / `accept.no_below`) is accepted outside the unsure band; a banded set is
        accepted when none of its options is unsure. Otherwise the confidence is at least `accept.min_confidence`
        (for a noul that is max(p, 1 - p), so a `min_confidence` of 0.5 accepts everything: use bands instead).
        """
        q = self.question
        if q.banded:
            if q.is_set:
                return not self.unsure
            return q.band(self.probabilities.get("true", 0.5)) != "unsure"
        return self.confidence >= q.min_confidence

    def as_dict(self) -> dict[str, Any]:
        out: dict[str, Any] = {"question": self.question.tag, "value": self.value,
                               "confidence": round(self.confidence, 4), "accepted": self.accepted,
                               "mode": self.question.mode,
                               "probabilities": {k: round(v, 4) for k, v in
                                                 sorted(self.probabilities.items(), key=lambda kv: -kv[1])}}
        if self.question.banded:
            if self.question.is_set:
                out["unsure"] = self.unsure
            else:
                out["band"] = self.question.band(self.probabilities.get("true", 0.5))
        if self.extras:
            out["extras"] = {k: round(v, 4) for k, v in self.extras.items()}
        if self.score is not None:
            out["score"] = round(self.score, 3)
            lane = self.question.lane(self.score)
            if lane:
                out["lane"] = lane
        return out


@dataclass
class Question:
    """One registered question file (`contracts/jev/questions/<id>.json`)."""

    data: dict[str, Any]

    @property
    def id(self) -> str:
        return self.data["id"]

    @property
    def tag(self) -> str:
        return f"{self.id}@{self.data['version']}"

    @property
    def mode(self) -> str:
        return self.data.get("mode", "shadow")

    @property
    def min_confidence(self) -> float:
        return float((self.data.get("accept") or {}).get("min_confidence", 0.9))

    @property
    def yes_above(self) -> float | None:
        value = (self.data.get("accept") or {}).get("yes_above")
        return float(value) if value is not None else None

    @property
    def no_below(self) -> float | None:
        value = (self.data.get("accept") or {}).get("no_below")
        return float(value) if value is not None else None

    @property
    def banded(self) -> bool:
        """The question has p bands (`accept.yes_above` / `accept.no_below`) for its noul answers."""
        return self.yes_above is not None and self.no_below is not None

    @property
    def is_set(self) -> bool:
        return self.data["type"] == "noul-set" or bool(self.data.get("per_item"))

    def band(self, p: float) -> str:
        """`yes` at or above `yes_above`, `no` at or below `no_below`, else `unsure`."""
        if self.yes_above is not None and p >= self.yes_above:
            return "yes"
        if self.no_below is not None and p <= self.no_below:
            return "no"
        return "unsure"

    @property
    def prefix(self) -> str:
        return self.id.replace(".", "_")

    def api_questions(self, items: dict[str, str] | None = None,
                      params: dict[str, str] | None = None) -> dict[str, dict[str, Any]]:
        """The API `questions` for this question.

        `noul-set` expands to one noul per criteria option (`<id>:<option>`), `per_item` to one per item. For an
        `item_state` question the item text lives in the request state under `items.<name>` (the keys of `items`
        must be safe state keys) and the instruction reads `{item}` as that path; `params` fills other `{name}`
        placeholders (the question, claim or topic the items are judged against).
        """
        d = self.data
        if d["type"] == "noul-set":
            return {f"{self.prefix}:{opt}": {"type": "noul", "instructions": d["instructions"].replace("{option}", desc)}
                    for opt, desc in d["criteria"].items()}
        if d.get("per_item"):
            text = d["instructions"]
            for key, value in (params or {}).items():
                text = text.replace("{" + key + "}", value)
            if d.get("item_state"):
                return {f"{self.prefix}:{name}": {"type": "noul", "instructions": text.replace("{item}", f"`items.{name}`")}
                        for name in (items or {})}
            return {f"{self.prefix}:{name}": {"type": "noul", "instructions": text.replace("{item}", desc)}
                    for name, desc in (items or {}).items()}
        q: dict[str, Any] = {"type": d["type"], "instructions": d["instructions"]}
        if d.get("criteria") is not None:
            q["criteria"] = d["criteria"]
        out = {self.prefix: q}
        for name, companion in (d.get("companions") or {}).items():
            out[f"{self.prefix}__{name}"] = {"type": "noul", "instructions": companion["instructions"]}
        return out

    def state(self, context: dict[str, Any]) -> dict[str, Any]:
        """The request `state`: `state.fields` of `context`, strings cut to `max_chars`, empties skipped."""
        spec = self.data.get("state") or {}
        limit = int(spec.get("max_chars", 4000))
        out: dict[str, Any] = {}
        for key in spec.get("fields") or list(context):
            value = context.get(key)
            if value in (None, "", [], {}):
                continue
            out[key] = value[:limit] if isinstance(value, str) else value
        return out

    def lane(self, score: float) -> str | None:
        """The lane a `score` answer routes to (`lanes.thresholds` / `lanes.names`), if the question has lanes."""
        lanes = self.data.get("lanes")
        if not lanes:
            return None
        names = lanes["names"]
        for threshold, name in zip(lanes["thresholds"], names):
            if score < threshold:
                return name
        return names[len(lanes["thresholds"])]

    def combine(self, answers: dict[str, Answer]) -> Decision:
        """Fold the API answers of this question into one Decision.

        A banded set's value is the options at or above `yes_above` (the ones between the bands are `unsure`);
        an unbanded set's value is the options whose noul is at least 0.5. A banded single noul has value True,
        False, or None when unsure.
        """
        kind = self.data["type"]
        if self.is_set:
            parts = {k.split(":", 1)[1]: a for k, a in answers.items() if k.startswith(self.prefix + ":")}
            probs = {name: a.probabilities["true"] for name, a in parts.items()}
            if self.banded:
                value = sorted(name for name, p in probs.items() if self.band(p) == "yes")
                confidence = min((max(p, 1 - p) for p in probs.values()), default=0.0)
            else:
                value = sorted(name for name, a in parts.items() if a.value)
                confidence = min((a.confidence for a in parts.values()), default=0.0)
            return Decision(self, value, confidence, probs)
        a = answers[self.prefix]
        extras = {name: answers[f"{self.prefix}__{name}"].probabilities["true"]
                  for name in (self.data.get("companions") or {}) if f"{self.prefix}__{name}" in answers}
        value = a.value
        if kind == "noul" and self.banded:
            band = self.band(a.probabilities["true"])
            value = True if band == "yes" else False if band == "no" else None
        return Decision(self, value, a.confidence, a.probabilities, a.score, extras)


def validate(data: dict[str, Any]) -> list[str]:
    """Problems with one question file (empty when valid)."""
    errs = [f"missing {key}" for key in ("id", "version", "type", "instructions") if key not in data]
    if data.get("type") not in KINDS:
        errs.append(f"type must be one of {KINDS}")
    if data.get("mode", "shadow") not in MODES:
        errs.append(f"mode must be one of {MODES}")
    criteria = data.get("criteria")
    if data.get("type") in ("choice", "noul-set") and not (isinstance(criteria, dict) and len(criteria) >= 2):
        errs.append("choice and noul-set need criteria with at least two options")
    if data.get("type") == "score" and not (isinstance(criteria, list) and 2 <= len(criteria) <= 10):
        errs.append("score needs 2 to 10 criteria levels, lowest first")
    if data.get("per_item") and "{item}" not in str(data.get("instructions", "")):
        errs.append("per_item questions need an {item} placeholder")
    if data.get("item_state") and not data.get("per_item"):
        errs.append("item_state needs per_item")
    if data.get("type") == "noul-set" and "{option}" not in str(data.get("instructions", "")):
        errs.append("noul-set instructions need an {option} placeholder")
    accept = data.get("accept") or {}
    confidence = accept.get("min_confidence", 0.9)
    if not (isinstance(confidence, (int, float)) and 0.5 <= confidence <= 1):
        errs.append("accept.min_confidence must be within [0.5, 1]")
    yes, no = accept.get("yes_above"), accept.get("no_below")
    if (yes is None) != (no is None):
        errs.append("accept.yes_above and accept.no_below go together")
    elif yes is not None and not (isinstance(yes, (int, float)) and isinstance(no, (int, float)) and 0 < no < yes < 1):
        errs.append("accept bands need 0 < no_below < yes_above < 1")
    elif yes is not None and not (data.get("type") in ("noul", "noul-set") or data.get("per_item")):
        errs.append("accept bands apply to noul answers only")
    if "output" in data and not (isinstance(data["output"], str) and data["output"].strip()):
        errs.append("output must name the consumer and what the answer produces")
    companions = data.get("companions")
    if companions is not None and not (isinstance(companions, dict) and all(
            isinstance(c, dict) and c.get("instructions") for c in companions.values())):
        errs.append("companions map a name to a noul with instructions")
    if data.get("mode") == "active" and not (data.get("target") or {}).get("precision"):
        errs.append("active questions need target.precision")
    lanes = data.get("lanes")
    if lanes and len(lanes.get("names", [])) != len(lanes.get("thresholds", [])) + 1:
        errs.append("lanes needs one more name than thresholds")
    return errs


def warnings(data: dict[str, Any]) -> list[str]:
    """Advisories for one valid question file (printed by `validate`, never fatal)."""
    accept = data.get("accept") or {}
    noulish = data.get("type") in ("noul", "noul-set") or data.get("per_item")
    if noulish and accept.get("yes_above") is None and float(accept.get("min_confidence", 0.9)) <= 0.5:
        return ["noul acceptance at min_confidence 0.5 accepts every answer: add accept.yes_above / accept.no_below"]
    return []


def load_questions(directory: Path = QUESTIONS_DIR) -> dict[str, Question]:
    """Every registered question by id.

    Raises:
        ValueError: A question file is invalid.
    """
    out: dict[str, Question] = {}
    for path in sorted(directory.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        problems = validate(data)
        if problems or data.get("id") != path.stem:
            raise ValueError(f"{path.name}: " + ("; ".join(problems) or "id must equal the file name"))
        out[data["id"]] = Question(data)
    return out


def ask_question(question: Question, context: dict[str, Any], *, items: dict[str, str] | None = None,
                 transport: Transport | None = None, use_cache: bool = True, subject: str = "") -> Decision | None:
    """Ask one registered question about `context`; None when no answer is available.

    A `shadow` question's decision is appended to `build/jev/shadow.jsonl` (with `subject`, never the state text)
    so it can be measured later; the caller must not show or act on it.
    """
    api = question.api_questions(items)
    if not api:
        return None
    answers = ask(api, question.state(context), tag=question.tag, transport=transport, use_cache=use_cache)
    if answers is None:
        return None
    decision = question.combine(answers)
    if question.mode == "shadow":
        log_shadow(decision, subject)
    return decision


def log_shadow(decision: Decision, subject: str = "") -> None:
    """Append a shadow decision (question tag, subject, value, top probabilities; no state text) to `shadow.jsonl`."""
    top = sorted(decision.probabilities.items(), key=lambda kv: -kv[1])[:5]
    record = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "question": decision.question.tag,
              "subject": subject, "value": decision.value, "accepted": decision.accepted,
              "probabilities": {k: round(v, 3) for k, v in top}}
    try:
        path = home() / "shadow.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as handle:
            handle.write(json.dumps(record, sort_keys=True, default=str) + "\n")
    except OSError:
        pass


def log_gate(decision: Decision, subject: str = "", printed: bool = False) -> None:
    """Append one active gate answer (`at`, `question` id@version, `subject`, `value`, `p`, `printed`) to
    `gate.jsonl` under `home()`, so the gate can be re-measured. Never the state text; failures are ignored."""
    p = decision.probabilities.get("true", decision.confidence)
    record = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "question": decision.question.tag,
              "subject": subject, "value": decision.value, "p": round(float(p), 3), "printed": printed}
    try:
        path = home() / "gate.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as handle:
            handle.write(json.dumps(record, sort_keys=True, default=str) + "\n")
    except OSError:
        pass


# MARK: - Items in the state (rerank)

def estimate_tokens(text: str) -> int:
    """A conservative token estimate (3 characters per token)."""
    return len(text) // 3 + 1


def chunk_items(items: dict[str, str], per_item_overhead: int = 0, *, max_tokens: int = CHUNK_TOKENS,
                max_items: int = CHUNK_ITEMS) -> list[dict[str, str]]:
    """Split `items` (name -> text) into request-sized chunks, keeping order.

    A chunk holds at most `max_items` items and about `max_tokens` estimated tokens of item text plus
    `per_item_overhead` tokens of questions per item; one oversized item still gets a chunk of its own.
    """
    chunks: list[dict[str, str]] = []
    current: dict[str, str] = {}
    used = 0
    for name, text in items.items():
        cost = estimate_tokens(text) + per_item_overhead
        if current and (used + cost > max_tokens or len(current) >= max_items):
            chunks.append(current)
            current, used = {}, 0
        current[name] = text
        used += cost
    if current:
        chunks.append(current)
    return chunks


def ask_items(specs: list[tuple[Question, dict[str, str]]], items: dict[str, str], *, shared: dict[str, Any] | None = None,
              tag: str = "", transport: Transport | None = None, use_cache: bool = True,
              max_tokens: int = CHUNK_TOKENS, max_items: int = CHUNK_ITEMS, workers: int = WORKERS,
              ) -> dict[str, Answer] | None:
    """Ask `item_state` questions over `items` with the item text in the state (not the questions).

    Every question in `specs` (a `(Question, params)` pair) is asked about every item in the same request (the
    skill's rule 2); the items are split into chunks under the limits and the chunks run in parallel (at most
    `workers`). An item name never reaches the model: items go in as `i0`, `i1`, ... under `state.items`.

    Args:
        specs: `item_state` questions with the values of their non-item placeholders.
        items: Item name -> text, in document order.
        shared: Extra state fields sent with every chunk (for example the thing the items are judged against).

    Returns:
        `{"<question prefix>:<item name>": Answer}` in item order, or None when any chunk has no answer.
    """
    if not items or not specs:
        return {}
    keys = {f"i{n}": name for n, name in enumerate(items)}
    texts = {key: items[name][:MAX_ITEM_CHARS] for key, name in keys.items()}
    overhead = sum(estimate_tokens(q.api_questions({"i0": ""}, params).get(f"{q.prefix}:i0", {}).get("instructions", ""))
                   + 20 for q, params in specs)
    chunks = chunk_items(texts, overhead, max_tokens=max_tokens, max_items=max_items)

    def run(chunk: dict[str, str]) -> dict[str, Answer] | None:
        api: dict[str, dict[str, Any]] = {}
        for question, params in specs:
            api.update(question.api_questions({key: "" for key in chunk}, params))
        return ask(api, {**(shared or {}), "items": chunk}, tag=tag, transport=transport, use_cache=use_cache)

    if len(chunks) > 1:
        with ThreadPoolExecutor(max_workers=max(1, min(workers, len(chunks)))) as pool:
            results = list(pool.map(run, chunks))
    else:
        results = [run(chunks[0])]
    if any(r is None for r in results):
        return None
    merged: dict[str, Answer] = {}
    for question, _ in specs:
        for key, name in keys.items():
            for result in results:
                answer = result.get(f"{question.prefix}:{key}")  # type: ignore[union-attr]
                if answer is not None:
                    merged[f"{question.prefix}:{name}"] = answer
    return merged


def rank_order(scores: dict[str, float], order: list[str] | None = None) -> list[tuple[str, float]]:
    """Names by descending p; ties (the API rounds to 0.01, so ties are common) keep `order` (default: insertion order)."""
    position = {name: n for n, name in enumerate(order or list(scores))}
    return sorted(scores.items(), key=lambda kv: (-round(kv[1], 2), position.get(kv[0], len(position)), kv[0]))


def ask_item_question(question: Question, items: dict[str, str], *, params: dict[str, str] | None = None,
                      shared: dict[str, Any] | None = None, transport: Transport | None = None,
                      use_cache: bool = True, subject: str = "", **limits: Any) -> Decision | None:
    """Ask one registered `item_state` question over `items`; None when no answer is available."""
    answers = ask_items([(question, params or {})], items, shared=shared, tag=question.tag, transport=transport,
                        use_cache=use_cache, **limits)
    if answers is None:
        return None
    decision = question.combine(answers)
    if question.mode == "shadow":
        log_shadow(decision, subject)
    return decision


# MARK: - Sync (context.patterns from the pattern registry)

def pattern_criteria(registry: dict[str, Any]) -> dict[str, str]:
    """One criterion per current pattern: `Title: summary (components: A, B)`, from `contracts/patterns.json`."""
    out: dict[str, str] = {}
    for p in registry.get("patterns") or []:
        if p.get("status") == "superseded":
            continue
        symbols = [r["symbol"] for r in (p.get("canonical") or {}).get("apple") or [] if r.get("symbol")]
        text = f"{p['title']}: {p['summary']}"
        text = text[:340].rstrip() + ("..." if len(text) > 340 else "")
        out[p["id"]] = text + (f" (components: {', '.join(symbols)})" if symbols else "")
    return out


def _front_matter_description(text: str) -> str:
    match = re.search(r"^description:\s*(.+)$", text.split("---", 2)[1] if text.startswith("---") else "", re.MULTILINE)
    return match.group(1).strip().strip("\"'") if match else ""


def doc_summary(path: Path, root: Path) -> tuple[str, str]:
    """(repo-relative path, `Title: what (read when: ...)`) of one `.agents` doc, from its title and `> **What:**` line."""
    text = path.read_text(encoding="utf-8", errors="replace")
    title = next((line[2:].strip() for line in text.splitlines() if line.startswith("# ")), path.stem)
    match = re.search(r"\*\*What:\*\*\s*(.+?)(?:\s*\*\*Read when:\*\*\s*(.+))?$", text[:1500], re.MULTILINE)
    if match:
        what = match.group(1).strip()
        when = (match.group(2) or "").strip()
        summary = f"{title}: {what}" + (f" (read when: {when})" if when else "")
    else:
        summary = f"{title}: {_front_matter_description(text)}".rstrip(": ")
    summary = " ".join(summary.split())
    return str(path.relative_to(root)), summary[:300].rstrip() + ("..." if len(summary) > 300 else "")


def learning_criteria(root: Path = ROOT) -> dict[str, str]:
    """One criterion per durable doc a learning can live in: `AGENTS.md` and `.agents/**/*.md` (no archive, no mockups).

    Mockups and the archive are not homes for rules; `none` stands for "no existing document fits".
    """
    paths = [root / "AGENTS.md"] if (root / "AGENTS.md").is_file() else []
    base = root / ".agents"
    paths += sorted(p for p in base.rglob("*.md") if not {"archive", "mockups"} & set(p.relative_to(base).parts))
    out = dict(doc_summary(p, root) for p in paths)
    out["none"] = "No existing document fits: the learning needs a new document, or is a one-off that should not be recorded"
    return out


def release_criteria(root: Path = ROOT) -> dict[str, str]:
    """The `research.release_impact` surface list, generated from the Swift sources (`tools/jev_surface.py`)."""
    spec = importlib.util.spec_from_file_location("jev_surface", Path(__file__).resolve().parent / "jev_surface.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["jev_surface"] = module
    spec.loader.exec_module(module)
    return module.criteria(root)


def generated_criteria(root: Path = ROOT) -> dict[str, Callable[[], dict[str, str]]]:
    """Question id -> a function that builds its criteria from the repository."""
    def patterns() -> dict[str, str]:
        return pattern_criteria(json.loads((root / "contracts" / "patterns.json").read_text(encoding="utf-8")))
    return {"context.patterns": patterns, "learning.home": lambda: learning_criteria(root),
            "research.release_impact": lambda: release_criteria(root)}


def sync(check: bool = False, root: Path = ROOT, only: list[str] | None = None) -> int:
    """Regenerate the generated questions' criteria. With `check`, exit 1 when any is stale.

    `context.patterns` comes from `contracts/patterns.json`, `learning.home` from the `.agents` docs and
    `research.release_impact` from the Swift sources (`tools/jev_surface.py`). A question file that does not exist is
    skipped. `only` limits the run to those ids.
    """
    stale: list[str] = []
    for qid, build in generated_criteria(root).items():
        path = root / "contracts" / "jev" / "questions" / f"{qid}.json"
        if (only is not None and qid not in only) or not path.is_file():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        fresh = build()
        if data.get("criteria") == fresh:
            print(f"{qid} criteria are up to date")
            continue
        if check:
            print(f"{qid} is stale: run `python3 tools/jev_ask.py sync`, bump its `version`, and commit")
            stale.append(qid)
            continue
        data["criteria"] = fresh
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"{qid}: {len(fresh)} criteria written; bump `version` if the wording changed")
    return 1 if stale else 0


# MARK: - CLI

def read_state(text: str, file: str) -> Any:
    """The CLI state: `file` (`-` = stdin) or `text`; JSON when it parses as an object or array."""
    if file:
        body = sys.stdin.read() if file == "-" else Path(file).read_text(encoding="utf-8", errors="replace")
    else:
        body = text or ""
    body = body[-60000:]
    if body.lstrip().startswith(("{", "[")):
        try:
            return json.loads(body)
        except ValueError:
            pass
    return body


def pairs(values: list[str] | None) -> dict[str, str]:
    """`name=description` options to a dict (a bare `name` describes itself)."""
    out: dict[str, str] = {}
    for value in values or []:
        name, _, desc = value.partition("=")
        out[name.strip()] = (desc or name).strip()
    return out


def read_items(path: str) -> dict[str, str]:
    """An items file: `{"name": "text"}` or `[{"id" | "name": ..., "text": ...}]`, in file order.

    Raises:
        ValueError: The file is not one of those shapes, or an item has no text.
    """
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if isinstance(data, list):
        data = {str(row.get("id", row.get("name", n))): row.get("text") for n, row in enumerate(data)
                if isinstance(row, dict)}
    if not isinstance(data, dict) or not data:
        raise ValueError("expected a non-empty object or array of {id, text}")
    out = {str(k): v for k, v in data.items()}
    if not all(isinstance(v, str) and v.strip() for v in out.values()):
        raise ValueError("every item needs non-empty text")
    return out


def emit(result: dict[str, Any], code: int = 0) -> int:
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    return code


def unavailable() -> int:
    """The shared "no answer" result: exit 3, callers carry on without a hint."""
    reason = NO_KEY if not api_key() else "no answer from the API (network or API error)"
    print(f"jev_ask: {reason}", file=sys.stderr)
    return emit({"error": reason, "unavailable": True, "decide_yourself": True}, EXIT_UNAVAILABLE)


def main(argv: list[str] | None = None, transport: Transport | None = None) -> int:
    """Command-line entry point."""
    parser = argparse.ArgumentParser(prog="jev_ask", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name in ("ask", "yesno", "choose", "score", "rank"):
        p = sub.add_parser(name)
        p.add_argument("question")
        p.add_argument("--state", default="")
        p.add_argument("--state-file", default="")
        p.add_argument("--threshold", type=float, default=None)
        p.add_argument("--no-cache", action="store_true")
        if name == "ask":
            p.add_argument("--context", default="", help="JSON object of context fields")
            p.add_argument("--context-file", default="")
            p.add_argument("--item", action="append", help="name=description (per_item questions)")
            p.add_argument("--param", action="append", help="name=value for a {name} placeholder (item_state questions)")
        if name == "yesno":
            p.add_argument("--true", dest="when_true", default="")
            p.add_argument("--false", dest="when_false", default="")
        if name == "choose":
            p.add_argument("-o", "--option", action="append", required=True, help="name=description")
        if name == "score":
            p.add_argument("-l", "--level", action="append", required=True, help="lowest first")
        if name in ("ask", "rank"):
            p.add_argument("--items-file", default="", help="JSON: {name: text} or [{id, text}]; item text goes in the state")
        if name == "rank":
            p.add_argument("-i", "--item", action="append", help="name=description (goes in the question; or use --items-file)")
    sub.add_parser("list")
    sub.add_parser("validate")
    p_sync = sub.add_parser("sync")
    p_sync.add_argument("--check", action="store_true")
    p_sync.add_argument("--only", action="append", help="limit to this question id (repeatable)")
    args = parser.parse_args(argv)

    if args.cmd == "sync":
        return sync(args.check, only=args.only)
    if args.cmd in ("list", "validate"):
        try:
            registered = load_questions()
        except (OSError, ValueError) as exc:
            print(f"jev_ask: {exc}", file=sys.stderr)
            return 1
        if args.cmd == "list":
            for q in registered.values():
                print(f"{q.tag}\t{q.data['type']}\t{q.mode}\t{q.data.get('description', '')}")
        else:
            for q in registered.values():
                for note in warnings(q.data):
                    print(f"warning: {q.id}: {note}", file=sys.stderr)
            print(f"{len(registered)} question(s) valid")
        return 0

    use_cache = not args.no_cache
    started = time.monotonic()
    if args.cmd == "ask":
        try:
            question = load_questions()[args.question]
        except (KeyError, OSError, ValueError) as exc:
            return emit({"error": f"unknown or invalid question {args.question!r}: {exc}"}, EXIT_USAGE)
        try:
            context = json.loads(Path(args.context_file).read_text(encoding="utf-8")) if args.context_file \
                else json.loads(args.context or "{}")
        except (OSError, ValueError) as exc:
            return emit({"error": f"bad context: {exc}"}, EXIT_USAGE)
        if not isinstance(context, dict):
            return emit({"error": "context must be a JSON object"}, EXIT_USAGE)
        if args.items_file:
            try:
                texts = read_items(args.items_file)
            except (OSError, ValueError) as exc:
                return emit({"error": f"bad items file: {exc}"}, EXIT_USAGE)
            if not question.data.get("item_state"):
                return emit({"error": f"{question.id} does not take items in the state (item_state)"}, EXIT_USAGE)
            decision = ask_item_question(question, texts, params=pairs(args.param), shared=question.state(context),
                                         transport=transport, use_cache=use_cache)
        else:
            decision = ask_question(question, context, items=pairs(args.item), transport=transport, use_cache=use_cache)
        if decision is None:
            return unavailable()
        result = decision.as_dict()
        if args.threshold is not None:
            result["accepted"] = decision.confidence >= args.threshold
        result["ms"] = int((time.monotonic() - started) * 1000)
        return emit(result)

    state = read_state(args.state, args.state_file)
    if args.cmd == "rank" and args.items_file:
        try:
            texts = read_items(args.items_file)
        except (OSError, ValueError) as exc:
            return emit({"error": f"bad items file: {exc}"}, EXIT_USAGE)
        adhoc = Question({"id": "adhoc.rank", "version": 1, "type": "noul", "per_item": True, "item_state": True,
                          "instructions": args.question if "{item}" in args.question else f"Regarding {{item}}: {args.question}"})
        answers = ask_items([(adhoc, {})], texts, shared={"context": state} if state else None, tag="adhoc.rank",
                            transport=transport, use_cache=use_cache)
        if answers is None:
            return unavailable()
        scores = {k.split(":", 1)[1]: a.probabilities["true"] for k, a in answers.items()}
        return emit({"ranked": [{"item": k, "p": round(p, 3)} for k, p in rank_order(scores, list(texts))],
                     "ms": int((time.monotonic() - started) * 1000)})
    if args.cmd == "yesno":
        q: dict[str, Any] = {"type": "noul", "instructions": args.question}
        if args.when_true or args.when_false:
            q["criteria"] = {"true": args.when_true or "yes", "false": args.when_false or "no"}
        questions = {"answer": q}
    elif args.cmd == "choose":
        questions = {"answer": {"type": "choice", "instructions": args.question, "criteria": pairs(args.option)}}
    elif args.cmd == "score":
        questions = {"answer": {"type": "score", "instructions": args.question, "criteria": args.level}}
    else:
        if not args.item:
            return emit({"error": "rank needs -i name=description or --items-file"}, EXIT_USAGE)
        questions = {f"item:{name}": {"type": "noul", "instructions": args.question.replace("{item}", desc)}
                     for name, desc in pairs(args.item).items()}
    answers = ask(questions, state, tag=f"adhoc.{args.cmd}", transport=transport, use_cache=use_cache)
    if answers is None:
        return unavailable()
    ms = int((time.monotonic() - started) * 1000)
    if args.cmd == "rank":
        scores = {k.split(":", 1)[1]: a.probabilities["true"] for k, a in answers.items()}
        return emit({"ranked": [{"item": k, "p": round(p, 3)} for k, p in rank_order(scores, list(pairs(args.item)))],
                     "ms": ms})
    a = answers["answer"]
    threshold = args.threshold if args.threshold is not None else 0.85
    result = {"answer": a.value, "confidence": round(a.confidence, 3), "accepted": a.confidence >= threshold, "ms": ms}
    if a.type == "noul":
        result["p_true"] = round(a.probabilities["true"], 3)
    else:
        result["probabilities"] = {k: round(v, 3) for k, v in a.probabilities.items()}
        if a.score is not None:
            result["score"] = round(a.score, 3)
    return emit(result)


if __name__ == "__main__":
    sys.exit(main())
