#!/usr/bin/env python3
"""PreToolUse hook for Edit|Write|MultiEdit: keeps the rule surface clean at write time.

When the target is a rule-surface file (a layer of ``contracts/rules-surface.json``), the hook computes the resulting text and
counts forbidden hits, over-long lines and words over the file budget (``tools/rules_lint.py``). It judges only *new*
violations: an edit that leaves every count at or below what the file has now is allowed, so a file can be cleaned step by step.
Otherwise it exits 2 with the rule in one line, up to five hits and the home for each kind of content.

An Edit whose replacement cannot be applied to the file on disk is allowed (the tool itself will report it). The hook fails open:
a crash prints a warning and allows the write (it is a style guard, not a security one).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import rules_lint  # noqa: E402

RULE = ("Blocked: rule-surface text states what is done by default, in the present tense; it carries no date, attribution, PR or "
        "commit reference, word of change, status, or line over the word limit, and stays inside its file budget.")
KINDS = ("forbidden", "long_lines", "over_words", "over_lines")


def root_of(cwd: str) -> Path:
    """The git toplevel of ``cwd`` (``cwd`` itself when git cannot say)."""
    try:
        out = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10)
        if out.returncode == 0 and out.stdout.strip():
            return Path(os.path.realpath(out.stdout.strip()))
    except (OSError, subprocess.SubprocessError):
        pass
    return Path(os.path.realpath(cwd))


def resulting_text(tool: str, tool_input: Dict[str, Any], current: Optional[str]) -> Optional[str]:
    """The file text after the tool runs, or ``None`` when it cannot be worked out (the edit does not apply)."""
    if tool == "Write":
        return str(tool_input.get("content", ""))
    edits = tool_input.get("edits") if tool == "MultiEdit" else [tool_input]
    if current is None or not isinstance(edits, list):
        return None
    text = current
    for edit in edits:
        old, new = str(edit.get("old_string", "")), str(edit.get("new_string", ""))
        if not old or old not in text:
            return None
        text = text.replace(old, new) if edit.get("replace_all") else text.replace(old, new, 1)
    return text


def judge(contract: Dict[str, Any], layer: str, rel: str, before: str, after: str) -> List[str]:
    """Message lines when ``after`` has more violations of any kind than ``before`` (empty: allow)."""
    old = rules_lint.hit_counts(contract, layer, rel, before)
    new = rules_lint.hit_counts(contract, layer, rel, after)
    if not any(new[k] > old[k] for k in KINDS):
        return []
    previous = {(f.line, f.message) for f in rules_lint.text_findings(contract, layer, rel, before)}
    findings = rules_lint.text_findings(contract, layer, rel, after)
    fresh = [f for f in findings if (f.line, f.message) not in previous] or findings
    lines = [RULE, f"File: {rel} (layer {layer})."]
    lines += [f"  line {f.line}: {f.message}" for f in fresh[:5]]
    if len(fresh) > 5:
        lines.append(f"  ... and {len(fresh) - 5} more")
    homes = list(dict.fromkeys(f.home for f in fresh if f.home))
    lines += [f"Home for that content: {home}" for home in homes[:4]]
    lines.append("Rewrite the rule in place and delete the old wording; history lives in git, the PR and .agents/decisions/. "
                 "There is no way to ignore a line.")
    return lines


def main() -> int:
    """Read the hook payload from stdin; exit 2 with the message to block."""
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    tool = payload.get("tool_name")
    if tool not in ("Edit", "Write", "MultiEdit"):
        return 0
    tool_input = payload.get("tool_input") or {}
    path = str(tool_input.get("file_path") or "")
    if not path or not path.endswith(".md"):
        return 0
    cwd = str(payload.get("cwd") or os.getcwd())
    root = root_of(cwd)
    full = Path(os.path.realpath(path if os.path.isabs(path) else os.path.join(cwd, path)))
    try:
        rel = full.relative_to(root).as_posix()
    except ValueError:
        return 0
    contract = rules_lint.load_contract(root)
    layer = rules_lint.layer_of(contract, rel)
    if layer is None:
        return 0
    current = full.read_text(encoding="utf-8", errors="replace") if full.is_file() else None
    after = resulting_text(str(tool), tool_input, current)
    if after is None:
        return 0
    message = judge(contract, layer, rel, current or "", after)
    if message:
        print("\n".join(message), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # noqa: BLE001 - fail open on our own crash
        print(f"rules_guard: warning, the hook crashed and allowed the write ({type(error).__name__}: {error})", file=sys.stderr)
        sys.exit(0)
