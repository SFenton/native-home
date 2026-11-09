"""One scrubber for text that leaves a session: logs, digests, handoffs, status files, archives, retro output.

Two layers, both pure apart from ``copy_redacted``:

``redact_json(obj)`` is the structural scrubber. It walks dicts and lists; a dict key that ``is_secret_key`` (the name is
normalised: camelCase and PascalCase become snake_case, ``-`` and spaces become ``_``, lower-case; it then equals
password, passwd, passphrase, pwd, pw, secret, token, api_key, apikey, key, auth, authorization, cookie, session or
session_id once ``_`` is ignored, so ``passWord`` and ``pass_word`` agree; or it ends with password, passwd, passphrase,
pwd, secret, token or apikey, or its last ``_`` part is key) has its whole value replaced by ``"[redacted]"`` whatever
its type, and every other string value goes through ``redact``. JSON is always parsed, redacted and dumped again, so the
output is valid JSON.

``redact(text)`` is the text scrubber, used for prose, logs and as the fallback when JSON does not parse. It masks,
with ``[redacted]``:

- JWTs (``eyJ….….…``, the Home Assistant token format),
- ``Bearer …`` values and ``Authorization:`` values,
- credentials in URLs (``scheme://user:pass@host``),
- ``name=VALUE`` for password, secret, token, key and auth names anywhere (not only after ``?&;``), ``name: VALUE``
  and ``"name": "VALUE"`` for the password-like names, ``--password VALUE`` / ``--token VALUE`` flags and
  ``-u USER -p VALUE``; a quoted value is masked up to its closing quote,
- PEM private-key blocks (``-----BEGIN ... PRIVATE KEY-----`` through ``END``, or to the end of the text when cut off),
- ``sk-``, ``ghp_``/``gho_``/``ghu_``/``ghs_``/``ghr_`` and ``github_pat_`` tokens,
- long hex or base64 runs (32 characters or more, with both a digit and a letter).

The text rules use the same names and accept any depth of JSON escaping (``\\\\\\"name\\\\\\":…``). A token is recognised after any character that cannot be part of a token, or directly after a JSON escape such as
``\\n``, ``\\t`` or ``\\u00e9``. A mask never consumes a closing quote, backslash, ``]`` or whitespace.

``redact_lines(text)`` applies ``redact_json`` to every line that is a JSON object or array and ``redact`` to the rest
(stream-json logs, ``.jsonl``). ``redact_file_text(text, suffix)`` picks the right one for a file.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, List, Pattern, Tuple

MASK = "[redacted]"
_VALUE = r"""[^\s"'<>&,;)\]}\\]+"""
_NOT_MASKED = r"(?!\[redacted\])"
#: A token starts here: after a non-token character, or right after a JSON escape (``\n``, ``\t``, ``é``).
_PRE = r"(?:(?<![A-Za-z0-9_-])|(?<=\\[nrtbf])|(?<=\\u[0-9A-Fa-f]{4}))"
#: The value after a credential name: a quoted value up to its closing quote, or a bare run.
#: ``Proxy-Authorization`` starts after a ``-``, which ``_PRE`` refuses; allow exactly that prefix.
_PRE_AUTH = r"(?:" + _PRE + r"|(?<=proxy-))"
_TAIL = _NOT_MASKED + r"""(?:(?P<open>\\*["'])[^"'\\\r\n]+|""" + _VALUE + ")"
#: The one list of credential key names, used by both layers. A name is compared *compact* (lower-case, ``_``/``-``/space
#: removed, so ``passWord``, ``pass_word`` and ``PASS-WORD`` are all ``password``). ``_NAME_SUFFIX`` words match a
#: compact name that ends with one (``accessToken``, ``client_secret``, ``FENTON_HASS_TOKEN``, ``db_pwd``);
#: ``_NAME_EXACT`` words match a whole compact name; ``key`` also matches as the last ``_`` part (``secret_key``,
#: ``signingKey``) but not inside a word (``monkey``). The text layer builds its regex from the same words, allowing
#: ``_`` or ``-`` between any two letters.
_NAME_SUFFIX = ("password", "passwd", "passphrase", "pwd", "secret", "token", "apikey")
_NAME_EXACT = ("pw", "key", "auth", "authorization", "cookie", "session", "sessionid")


def _loose(word: str) -> str:
    """``password`` -> ``p[_-]?a[_-]?s...``: the word with an optional ``_`` or ``-`` between any two letters."""
    return r"[_-]?".join(word)


_STRONG = (r"(?:[a-z0-9_-]*(?:" + "|".join(_loose(w) for w in _NAME_SUFFIX) + r"|[_-]key|(?-i:[a-z0-9]Key))"
           r"|pw)")
_ANY = r"(?:" + _STRONG + r"|key|auth|session(?:[_-]?id)?)"
_SEP_EQ = r"""\\*["']?[ \t]*=[ \t]*"""
_SEP_QCOLON = r"""\\*["'][ \t]*:[ \t]*"""
_SEP_COLON = r"[ \t]*:[ \t]*"
_FLAGS = r"--?(?:password|passwd|pass|token|secret|api-?key|auth-?token|access-?token)"


#: A PEM private-key block, BEGIN through END (or to the end of the text when cut off); ``.`` spans lines, CRLF included.
PEM_BLOCK = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|\Z)", re.S)


def _keep_open(match: "re.Match[str]") -> str:
    return match.group("head") + (match.group("open") or "") + MASK


#: (pattern, replacement). Order matters: the specific shapes go before the generic long-run rule.
RULES: List[Tuple[Pattern[str], Any]] = [
    (PEM_BLOCK, MASK),
    (re.compile(r"eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]*"), MASK),
    (re.compile(r"(?i)(" + _PRE_AUTH + r"authorization\\*[\"']?[ \t]*[:=][ \t]*\\*[\"']?(?:(?:bearer|token|basic)[ \t]+)?)"
                + _NOT_MASKED + _VALUE), r"\1" + MASK),
    (re.compile(r"(?i)(" + _PRE + r"bearer\s+)(?!\[redacted\])[A-Za-z0-9._~+/=-]+"), r"\1" + MASK),
    (re.compile(r"(?i)(" + _PRE + r"(?:set-)?cookie[ \t]*[:=][ \t]*)" + _NOT_MASKED + r"""[^\r\n"'\\]+"""), r"\1" + MASK),
    (re.compile(r"(?i)((?<![A-Za-z0-9+.-])[a-z][a-z0-9+.-]*://)[^\s/@\"'<>]+@"), r"\1" + MASK + "@"),
    (re.compile(r"(?i)(?P<head>" + _PRE + r"(?:" + _ANY + r"(?:" + _SEP_EQ + "|" + _SEP_QCOLON + r")|" + _STRONG
                + r"(?:" + _SEP_COLON + r")))" + _TAIL), _keep_open),
    (re.compile(r"(?i)(?P<head>" + _PRE + _FLAGS + r"\s+)(?!-)" + _TAIL), _keep_open),
    (re.compile(r"(?i)(?P<head>" + _PRE + r"(?:-u|-U|--user(?:name)?)(?:\s+|=)\S+\s+-p\s*)(?!-)" + _TAIL), _keep_open),
    (re.compile(_PRE + r"gh[pousr]_[A-Za-z0-9_]{16,}"), MASK),
    (re.compile(_PRE + r"github_pat_[A-Za-z0-9_]{16,}"), MASK),
    (re.compile(_PRE + r"sk-[A-Za-z0-9_-]{16,}"), MASK),
]
LONG_RUN = re.compile(r"(?<![A-Za-z0-9+/_=-])(?P<esc>\\[nrtbf]|\\u[0-9A-Fa-f]{4})?"
                      r"(?P<run>[A-Za-z0-9+/_-]{32,}={0,2})(?![A-Za-z0-9+/_=-])")

def _mask_run(match: "re.Match[str]") -> str:
    run = match.group("run")
    esc = match.group("esc") or ""
    if re.search(r"[0-9]", run) and re.search(r"[A-Za-z]", run) and "/" not in run.strip("/"):
        return esc + MASK
    return match.group(0)


def redact(text: str) -> str:
    """``text`` with every credential shape above masked."""
    for pattern, replacement in RULES:
        text = pattern.sub(replacement, text)
    return LONG_RUN.sub(_mask_run, text)


def normalize_key(key: str) -> str:
    """``accessToken`` / ``AccessToken`` / ``access-token`` / ``Access Token`` -> ``access_token``."""
    key = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", key)
    key = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", key)
    return re.sub(r"[-\s]+", "_", key).lower()


def is_secret_key(key: Any) -> bool:
    """True when a JSON object key names a credential (see ``_NAME_EXACT`` and ``_NAME_SUFFIX``)."""
    if not isinstance(key, str):
        return False
    name = normalize_key(key)
    compact = name.replace("_", "")
    return (compact in _NAME_EXACT or compact.endswith(_NAME_SUFFIX) or name.rsplit("_", 1)[-1] == "key"
            or name.endswith("_key"))


def redact_json(obj: Any) -> Any:
    """A redacted copy of parsed JSON: secret-named keys masked whole, every other string text-scrubbed."""
    if isinstance(obj, dict):
        return {k: (MASK if is_secret_key(k) else redact_json(v)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [redact_json(v) for v in obj]
    if isinstance(obj, str):
        return redact(obj)
    return obj


def redact_lines(text: str) -> str:
    """Redact line by line: a line that parses as a JSON object or array structurally, any other line as text."""
    text = PEM_BLOCK.sub(MASK, text)  # a PEM block spans lines (LF or CRLF), unterminated ones to the end: mask before the per-line pass
    out: List[str] = []
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped[:1] in ("{", "["):
            try:
                parsed = json.loads(stripped)
                clean = redact_json(parsed)
                out.append(line if clean == parsed else json.dumps(clean, ensure_ascii=False))  # untouched stays as written
                continue
            except ValueError:
                pass
        out.append(redact(line))
    return "\n".join(out)


def redact_file_text(text: str, suffix: str = "") -> str:
    """The redacted text of a file with extension ``suffix``: ``.json`` is parsed and dumped again; everything else
    (``.jsonl``, logs, markdown) goes through ``redact_lines``. A ``.json`` file that does not parse falls back to it."""
    if suffix.lower() == ".json":
        try:
            return json.dumps(redact_json(json.loads(text)), indent=2, ensure_ascii=False) + "\n"
        except ValueError:
            pass
    return redact_lines(text)


def copy_redacted(src: Path, dest: Path) -> None:
    """Write a redacted copy of the text file ``src`` to ``dest`` (parents created)."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(redact_file_text(src.read_text(encoding="utf-8", errors="replace"), src.suffix), encoding="utf-8")
