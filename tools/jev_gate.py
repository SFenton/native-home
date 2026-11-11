#!/usr/bin/env python3
"""jev_gate: the post-research gate hints (raise-only) for a researched plan.

    python3 tools/jev_gate.py --plan-file F [--title T] [--subject TASK]

Asks the registered gate questions about the plan: design.user_visible, decision.needs_owner and, only for a visible
plan and once its question file exists, design.target_decided. It prints the raise-only lines:

    Jev: reads as visible (p=0.82): send it to the Designer      # design.user_visible, p >= 0.6
    Jev: the owner's pick looks needed (p=0.91): L2              # decision.needs_owner, p >= 0.5

and then one route hint from the answers (the orchestrator decides; it never lowers a level by itself):

    Jev route (hint, the orchestrator decides): Designer options and mockups (L2 design)
    Jev: no route hint (unsure)                                  # a needed answer is missing or in its band

For a plan that is not read as invisible it then prints the app-UI gate (owner, 2026-11-03): `design.matches_request` when the
plan has an `Owner's request:` section, else `design.app_wide`, ending in a machine-readable line
`gate: autonomous|park basis=request|agent answer=yes|no|unsure|unavailable`, with ` route=session|pr` appended to a `park` line (owner,
2026-11-10: a headless session, the markers `merge_guard.headless()` reads, routes to the pull request; an interactive one decides in the
session; see `.agents/workflow/agent-roster.md#questions`). Unavailable Jev or a missing question file
parks (fail safe); the gate lines are printed even with no key. This plan-time gate trusts the plan's `Owner's request:` section as written; the landing gate (`tools/lane_land.py`) is where a
quote must match a prompt the owner typed (`tools/hooks/owner_prompt_log.py`, last 14 days, 20+ characters) and where mockup edits
that draw the same are not app UI (`rendered_ui_paths`, owner decisions 2026-11-04). Quote the owner's words in that section.
The raise-only lines only raise. No key or an API error prints **nothing**, and silence never skips the Designer or
lowers a level. It exits 0 when it ran, so a hint never stops work; a `--plan-file` that is missing or empty prints
`jev_gate: cannot read <path>` to stderr and exits 2. Each answer is logged (no plan text) to `build/jev/gate.jsonl`.
Every line is a guess to verify, never an instruction (`.agents/workflow/jev.md`,
`.agents/workflow/agent-roster.md`). Standard library only.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent


def _load(name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


jev = _load("jev_ask")


def registered_session() -> bool:
    """Is this process inside a T3-launched triage session (``tools/hooks/triage_session.py``)? A failed lookup counts as one."""
    hooks = str(HERE / "hooks")
    sys.path.insert(0, hooks)
    try:
        import triage_session
        return bool(triage_session.registered())
    except Exception:  # noqa: BLE001
        return True
    finally:
        sys.path.remove(hooks)


def route(markers: "dict[str, str] | None" = None) -> str:
    """Where a parked question goes: ``pr`` for a headless session, ``session`` for an interactive one.

    Headless is what ``tools/hooks/merge_guard.py`` ``headless()`` reads (``FENTON_HEADLESS=1``), the runner's ``HASS_TRIAGE_ISSUE``,
    or a registered triage session. A registry lookup that fails answers ``pr`` (the behaviour before this field: finish
    ``needs_decision``)."""
    if markers is None:
        markers = {k: os.environ.get(k, "") for k in ("FENTON_HEADLESS", "HASS_TRIAGE_ISSUE")}
    if markers.get("FENTON_HEADLESS") == "1" or markers.get("HASS_TRIAGE_ISSUE"):
        return "pr"
    return "pr" if registered_session() else "session"


def _verdict(decision: Any) -> bool | None:
    """True or False when the decision is accepted as a yes or a no, None when unavailable or in the unsure band."""
    if decision is None or not decision.accepted or not isinstance(decision.value, bool):
        return None
    return decision.value


def _p_yes(decision: Any) -> float:
    return float(decision.probabilities.get("true", decision.confidence))


def _ask(question_id: str, context: dict, subject: str, questions: dict) -> tuple[bool | None, float | None]:
    """Ask one question, log the answer to gate.jsonl; returns (accepted yes/no or None, P(yes) or None when Jev
    gave no answer at all)."""
    decision = jev.ask_question(questions[question_id], context, subject=subject)
    if decision is None:
        return None, None
    verdict = _verdict(decision)
    jev.log_gate(decision, subject, printed=verdict is True)
    return verdict, _p_yes(decision)


def _safe_ask(question_id: str, context: dict, subject: str, questions: dict) -> tuple[bool | None, float | None]:
    try:
        return _ask(question_id, context, subject, questions)
    except Exception:  # noqa: BLE001 (a hint never stops work)
        return None, None


#: Route hints by (visible, already chosen, pick). `None` in a slot means that answer is not needed for the row.
ROUTES = {
    (False, None, False): "Coder (L0)",
    (False, None, True): "decision note, then Coder (L2 policy)",
    (True, True, False): "Designer spec within the existing pattern, then Coder (L1)",
    (True, True, True): "decision note for the remaining choice plus a Designer spec",
    (True, False, None): "Designer options and mockups (L2 design)",
}


def route_hint(visible: bool | None, chosen: bool | None, pick: bool | None) -> str:
    """The next-step hint from the table, or the unsure line when a needed answer is missing."""
    if visible is False:
        key = (False, None, pick)
    elif visible is True and chosen is False:
        key = (True, False, None)
    elif visible is True:
        key = (True, chosen, pick)
    else:
        key = None
    route = ROUTES.get(key) if key else None
    if route is None:
        return "Jev: no route hint (unsure)"
    return f"Jev route (hint, the orchestrator decides): {route}"


REQUEST_RE = re.compile(r"^[ \t>*_-]*Owner'?s request\*{0,2}:\*{0,2}[ \t]*(.*)$", re.I | re.M)


def owner_request(plan: str) -> str | None:
    """The text of the plan's ``Owner's request:`` section (that line and the lines after it up to a blank line), or
    None when the plan has none, which makes the work agent-initiated."""
    match = REQUEST_RE.search(plan)
    if not match:
        return None
    rest = plan[match.end():].split("\n\n", 1)[0] if not match.group(1).strip() else ""
    text = (match.group(1) + "\n" + rest).strip()
    return text or None


def gate(plan: str, subject: str, questions: dict) -> tuple[str, list[str]]:
    """The app-UI gate (owner, 2026-11-03): ``(outcome, lines)``, outcome ``autonomous`` or ``park``.

    Request-driven work (the plan carries an ``Owner's request:`` section): ``design.matches_request`` with the owner's
    words and the plan. An accepted yes is autonomous; no or unsure parks for the owner. Agent-initiated work: ``design.app_wide``
    on the plan. An accepted no is autonomous (a change local to a screen); yes or unsure parks. Jev unavailable or a question
    file missing parks (fail safe). The last line is machine-readable: ``gate: <outcome> basis=<request|agent> answer=<..>``, plus ``route=<session|pr>`` on a park."""
    request = owner_request(plan)
    qid = "design.matches_request" if request is not None else "design.app_wide"
    basis = "request" if request is not None else "agent"
    answer, p_yes = None, None
    if qid in questions:
        context = {"pair": f"Request: {request}\nChange: {plan}"} if request is not None else {"change": plan}
        answer, p_yes = _safe_ask(qid, context, subject, questions)
    word = "unavailable" if qid not in questions or p_yes is None else ("yes" if answer is True else "no" if answer is False else "unsure")
    if request is not None:
        outcome = "autonomous" if answer is True else "park"
        reason = ("matches the owner's request" if outcome == "autonomous" else
                  "Jev cannot confirm it matches the owner's request: the owner decides")
    else:
        outcome = "autonomous" if answer is False else "park"
        reason = ("local to a screen" if outcome == "autonomous" else
                  "app-wide or unsure, and no owner asked for it: the owner decides")
    line = f"gate: {outcome} basis={basis} answer={word}" + (f" route={route()}" if outcome == "park" else "")
    return outcome, [f"Jev gate ({qid}={word}): {reason}", line]


def hints(plan: str, title: str = "", subject: str = "") -> list[str]:
    """The hint lines for `plan`: the raise-only lines, then a route hint; empty when Jev is unavailable."""
    return _run(plan, title, subject)[0]


def _run(plan: str, title: str = "", subject: str = "") -> tuple[list[str], bool | None, dict | None]:
    """``(lines, visible, questions)``; the questions are None when they could not be loaded."""
    try:
        questions = jev.load_questions()
    except Exception:  # noqa: BLE001
        return [], None, None
    lines: list[str] = []
    visible, p_visible = _safe_ask("design.user_visible", {"title": title, "body": plan, "files": ""}, subject, questions)
    if visible is True:
        lines.append(f"Jev: reads as visible (p={p_visible:.2f}): send it to the Designer")
    pick, p_pick = _safe_ask("decision.needs_owner", {"plan": plan}, subject, questions)
    if pick is True:
        lines.append(f"Jev: the owner's pick looks needed (p={p_pick:.2f}): L2")
    chosen = None
    if visible is True and "design.target_decided" in questions:  # the question file arrives later
        chosen, _ = _safe_ask("design.target_decided", {"plan": plan}, subject, questions)
    if p_visible is None and p_pick is None:
        return lines, visible, questions  # Jev unavailable: silence, as before
    lines.append(route_hint(visible, chosen, pick))
    return lines, visible, questions


def all_lines(plan: str, title: str = "", subject: str = "") -> list[str]:
    """The hints plus the app-UI gate lines (omitted when Jev says the plan is not visible)."""
    lines, visible, questions = _run(plan, title, subject)
    if visible is False:
        return lines
    return lines + gate(plan, subject, questions or {})[1]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Raise-only Jev hints for a researched plan.")
    parser.add_argument("--plan-file", required=True)
    parser.add_argument("--title", default="")
    parser.add_argument("--subject", default="")
    args = parser.parse_args(argv)
    try:
        plan = Path(args.plan_file).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        plan = ""
    if not plan.strip():
        print(f"jev_gate: cannot read {args.plan_file}", file=sys.stderr)
        return 2
    try:
        for line in all_lines(plan, args.title, args.subject):
            print(line)
    except Exception:  # noqa: BLE001 (no Jev: the raise-only hints are silent, but the gate fails safe)
        basis = "request" if owner_request(plan) is not None else "agent"
        print(f"gate: park basis={basis} answer=unavailable route={route()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
