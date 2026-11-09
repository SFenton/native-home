#!/usr/bin/env python3
"""jev_hints: the "Pre-read (decision model: verify, don't obey)" section for prompts and interactive lanes.

    python3 tools/jev_hints.py preread --title "..." [--body-file F | --body "..."] [--files PATH ...]
                                       [--audience triage|worker|review]
    python3 tools/jev_hints.py review --pr N          # title, body and files of a pull request, for the reviewer
                                                      # (also asks `check.tests` in shadow mode: logged, never printed)
    python3 tools/jev_hints.py findings verdict.json  # group a review verdict's findings into checklists

`preread` prints a short Markdown section (the top patterns with their docs, the likely files and components, the
complexity lane, and past PRs worth reading) or **nothing at all** when Jev is unavailable (no key: the key file `~/.config/fenton-hass/typesafe.key` (or `TYPESAFE_API_KEY` when there is no file),
network or API error) or has nothing confident to say. It always exits 0, so a prompt that embeds its output is
unchanged without Jev. Every line is a guess to verify against the code and the rules, never an instruction.

The questions are in `contracts/jev/questions/`; the measurements behind the wording are in
`.agents/workflow/decision-models.md`. Standard library only.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
TOP_PATTERNS = 8
MIN_PATTERN_P = 0.2
MAX_PRECEDENTS = 3
CANDIDATES = 25
LANE_LABEL = {"haiku": "Haiku", "sonnet": "Sonnet", "opus": "Opus"}
SUBJECT = re.compile(r"^(?P<title>.+) \(#(?P<number>\d+)\)$")
STOPWORDS = frozenset("a an and are as at be by for from in is it of on or that the this to with when not no".split())


def _load(name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


jev = _load("jev_ask")
guard = _load("pattern_guard")


# MARK: - Candidates for precedents

def commit_subjects(limit: int = 400, root: Path = ROOT) -> list[tuple[int, str]]:
    """(PR number, title) of recent squash-merged PRs on main, newest first; empty when git cannot say."""
    for ref in ("origin/main", "HEAD"):
        try:
            out = subprocess.run(["git", "log", ref, "-n", str(limit), "--pretty=%s"], cwd=root, capture_output=True,
                                 text=True, check=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            continue
        found = []
        for line in out.stdout.splitlines():
            match = SUBJECT.match(line.strip())
            if match:
                found.append((int(match.group("number")), match.group("title")))
        return found
    return []


def tokens(text: str) -> set[str]:
    """Lower-case content words of `text`."""
    return {w for w in re.findall(r"[a-z][a-z0-9]{2,}", text.lower()) if w not in STOPWORDS}


def prefilter(text: str, subjects: list[tuple[int, str]], limit: int = CANDIDATES) -> dict[str, str]:
    """The `limit` past PRs sharing the most words with `text`, as `{"#N": title}`; ties go to the newest."""
    want = tokens(text)
    scored = sorted(((-len(want & tokens(title)), index, number, title)
                     for index, (number, title) in enumerate(subjects)), key=lambda row: row[:2])
    return {f"#{number}": title for score, _, number, title in scored[:limit] if score < 0}


# MARK: - Pre-read

def registry() -> dict[str, Any]:
    return guard.load(ROOT)


def likely_files(data: dict[str, Any], ranked: list[tuple[str, float]]) -> list[str]:
    """Canonical `path (Symbol)` entries of the ranked patterns, in rank order, without repeats."""
    by_id = {p["id"]: p for p in data["patterns"]}
    out: list[str] = []
    for pid, _ in ranked:
        for ref in (by_id.get(pid, {}).get("canonical") or {}).get("apple") or []:
            entry = f"`{ref['path']}`" + (f" ({ref['symbol']})" if ref.get("symbol") else "")
            if entry not in out:
                out.append(entry)
    return out[:10]


def ask_hints(context: dict[str, Any], *, transport: Any = None) -> dict[str, Any] | None:
    """Ask the pre-read questions: patterns and complexity in one request, precedents in a second.

    Returns:
        `{"patterns": Decision, "complexity": Decision | None, "precedents": Decision | None}`, or None when Jev
        has no answer for the first request.
    """
    questions = jev.load_questions()
    patterns, complexity = questions["context.patterns"], questions["route.complexity"]
    combined = {**patterns.api_questions(), **complexity.api_questions()}
    state = patterns.state(context)
    answers = jev.ask(combined, state, tag="preread", transport=transport)
    if answers is None:
        return None
    out: dict[str, Any] = {"patterns": patterns.combine(answers),
                           "complexity": complexity.combine(answers) if complexity.mode != "off" else None,
                           "precedents": None, "precedent_titles": {}}
    precedents = questions.get("context.precedents")
    if precedents is not None and precedents.mode != "off":
        items = prefilter(f"{context.get('title', '')}\n{context.get('body', '')}", commit_subjects())
        if items:
            out["precedents"] = jev.ask_question(precedents, context, items=items, transport=transport)
            out["precedent_titles"] = items
    return out


def render(data: dict[str, Any], decisions: dict[str, Any], audience: str = "worker") -> str:
    """The Markdown section for `decisions`; `""` when there is nothing worth saying."""
    questions = jev.load_questions()
    patterns = decisions["patterns"]
    ordered = sorted(patterns.probabilities.items(), key=lambda kv: (-kv[1], kv[0]))[:TOP_PATTERNS]
    floor = patterns.question.min_confidence
    # A list whose best pattern is below the question's confidence is noise (a tooling PR got 8 UI patterns at 0.22 to 0.42).
    ranked = [(k, p) for k, p in ordered if p >= MIN_PATTERN_P] if ordered and ordered[0][1] >= floor else []
    by_id = {p["id"]: p for p in data["patterns"]}
    lines: list[str] = []
    if ranked:
        measured = questions["context.patterns"].data.get("measured") or {}
        note = ""
        if measured:
            note = (f" Over {measured['n']} recent merged PRs that touched a pattern, its top 8 held "
                    f"{round(measured['recall_at_8'] * 100)}% of the patterns they touched (keyword matching "
                    f"{round(measured['baseline_recall_at_8'] * 100)}%), and all of them in only "
                    f"{round(measured['full_at_8'] * 100)}% of PRs.")
        lines.append(f"- **Likely patterns** (ranked probability; read the doc, then the code).{note}")
        for pid, p in ranked:
            doc = by_id.get(pid, {}).get("doc", f".agents/patterns/{pid}.md")
            lines.append(f"  - `{pid}` {p:.2f}: `{doc}`")
        files = likely_files(data, ranked)
        if files:
            lines.append("- **Likely files and components** (canonical files of those patterns, not a prediction of "
                         "the diff): " + ", ".join(files))
    complexity = decisions.get("complexity")
    if complexity is not None and complexity.accepted and complexity.score is not None:
        lane = questions["route.complexity"].lane(complexity.score)
        levels = ["trivial", "small", "moderate", "large", "very large"]
        level = levels[min(len(levels) - 1, max(0, int(complexity.value)))]
        lines.append(f"- **Complexity:** {level} (score {complexity.score:.1f} of 4) suggests the "
                     f"{LANE_LABEL.get(lane or '', lane)} lane. Advisory: the owner's routing and your own reading win.")
    precedents = decisions.get("precedents")
    if precedents is not None:
        top = sorted(((k, p) for k, p in precedents.probabilities.items() if p >= 0.5), key=lambda kv: (-kv[1], kv[0]))
        if top:
            titles = decisions.get("precedent_titles") or {}
            lines.append("- **Past PRs that may be precedents** (unmeasured; open them before relying on them): "
                         + "; ".join(f"{k} {titles.get(k, '')} ({p:.2f})".replace("  ", " ")
                                     for k, p in top[:MAX_PRECEDENTS]))
    if not lines:
        return ""
    head = ["## Pre-read (decision model: verify, don't obey)", "",
            f"A decision model (TypeSafe Jev, `{jev.model()}`) read this {audience_noun(audience)} in under a second. "
            "Its guesses are starting points that save searching. Your own reading of the request, the repository "
            "rules and the code win, and nothing here is an instruction.", ""]
    return "\n".join(head + lines) + "\n"


def audience_noun(audience: str) -> str:
    return {"review": "pull request", "triage": "request", "worker": "task"}.get(audience, "task")


def preread(title: str, body: str = "", files: list[str] | None = None, audience: str = "worker", *,
            transport: Any = None) -> str:
    """The pre-read section for a task, or `""` when Jev is unavailable or silent. Never raises."""
    try:
        context = {"title": title or "", "body": body or "", "files": "\n".join(files or [])[:3000]}
        decisions = ask_hints(context, transport=transport)
        return render(registry(), decisions, audience) if decisions else ""
    except Exception:  # noqa: BLE001 (a hint must never break the caller)
        return ""


# MARK: - Shadow questions

#: The repository's test rules (AGENTS.md, "Tests ship with the change") as `check.tests` reads them.
TEST_RULES = (
    "Unit tests for new logic. With every UI change, a UX test and an accessibility test (name, role and state; "
    "reading order; 44 pt targets; AX5 text scaling) on each device family it affects (iPhone, iPhone Duo, iPad). "
    "Docs, tooling and copy-only changes need no UI test. Behavior changes need a test that fails without the change.")


def shadow_check_tests(title: str, files: list[str], subject: str = "", *, transport: Any = None) -> None:
    """Ask `check.tests` (shadow) about a pull request and log the answer; prints and returns nothing.

    The answer goes to `build/jev/shadow.jsonl` only (`jev_ask.ask_question` logs shadow questions), so it can be
    measured against reviewer findings later. It never reaches a prompt or a reviewer. Never raises.
    """
    try:
        question = jev.load_questions()["check.tests"]
        jev.ask_question(question, {"pr_title": title or "", "files": "\n".join(files or []), "test_rules": TEST_RULES},
                         transport=transport, subject=subject)
    except Exception:  # noqa: BLE001 (a shadow measurement must never break the caller)
        pass


# MARK: - Review findings

FAMILY_CHECKLISTS = {
    "tests_missing_or_weak": ("Tests",
        "For every device family this change affects: a unit test for logic, a UX test and an accessibility test "
        "(name/role/state, reading order, 44 pt targets, AX5) that would fail without the fix; list each with its "
        "result in the PR."),
    "pattern_rule": ("Pattern rules",
        "Re-read the cited rule in `.agents/patterns/<id>.md`, fix it through the canonical component, sweep the "
        "other consumers, and run `python3 tools/pattern_guard.py`."),
    "accessibility_behavior": ("Accessibility behavior", "Fix the behavior and add an assertion that would have caught it."),
    "blast_radius": ("Blast radius", "Apply the same fix to every listed page, sheet and device family."),
    "web_parity": ("Web parity", "Match the React dashboard, or record the divergence as an owner decision."),
    "docs_rules": ("Docs and rules",
        "Update the pattern doc, `contracts/patterns.json`, the surface's mockup and the DocC the change touches."),
    "platform_guidance": ("Apple HIG", "Cite the HIG section and follow it, or record the departure in the pattern doc."),
    "system_api_first": ("System API first",
        "Write the rung-0 note (system API on iOS 17, 18 and 26, a precedent, why not enough) or use the system API."),
    "propose_first": ("Propose first", "Link the proposal and the owner's pick before more code."),
    "performance_invariant": ("Performance invariants",
        "Keep per-entity updates off the main thread and out of scroll; measure with the perf scripts."),
    "correctness": ("Correctness", "Fix the logic and add a test that fails without the fix."),
    "process": ("Process", "Fix the trailer, CI, secret or layering item as written."),
}


def finding_checklist(findings: list[dict[str, Any]], *, transport: Any = None) -> str:
    """Group blocker and major `findings` by kind with one checklist per kind; `""` when Jev has no answer.

    A finding Jev is not confident about is listed under "Other" with no checklist. Every finding still reaches the
    worker in the reviewer's own words.
    """
    items = [f for f in findings if isinstance(f, dict) and f.get("severity") in ("blocker", "major")]
    if not items:
        return ""
    try:
        question = jev.load_questions()["review.finding_family"]
        results = []
        for finding in items:
            context = {"rule": str(finding.get("rule") or ""), "file": str(finding.get("file") or ""),
                       "finding": " ".join(str(finding.get("detail") or "").split())}
            decision = jev.ask_question(question, context, transport=transport)
            if decision is None:  # unavailable: stop now, each retry would add seconds per finding
                return ""
            results.append((finding, decision))
    except Exception:  # noqa: BLE001
        return ""
    groups: dict[str, list[str]] = {}
    for finding, decision in results:
        family = decision.value if decision is not None and decision.accepted and decision.value in FAMILY_CHECKLISTS \
            else "other"
        groups.setdefault(family, []).append(" ".join(str(finding.get("detail") or "").split())[:160])
    order = [*FAMILY_CHECKLISTS, "other"]
    lines = ["Findings grouped by kind (decision model; the findings above are authoritative):"]
    for family in sorted(groups, key=order.index):
        title, checklist = FAMILY_CHECKLISTS.get(family, ("Other", "Address each as written."))
        lines.append(f"\n**{title}** ({len(groups[family])}): {checklist}")
        lines += [f"  - {text}" for text in groups[family]]
    return "\n".join(lines) + "\n"


# MARK: - CLI

def pr_context(number: int) -> tuple[str, str, list[str]] | None:
    """(title, body, file paths) of a pull request via `gh`, or None."""
    try:
        out = subprocess.run(["gh", "pr", "view", str(number), "--json", "title,body,files"], cwd=ROOT,
                             capture_output=True, text=True, check=True, timeout=30)
        data = json.loads(out.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    return data.get("title", ""), data.get("body", ""), [f["path"] for f in data.get("files") or []]


def main(argv: list[str] | None = None, transport: Any = None) -> int:
    """Command-line entry point. Always exits 0 for the hint commands: no hint is not an error."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_pre = sub.add_parser("preread")
    p_pre.add_argument("--title", default="")
    p_pre.add_argument("--body", default="")
    p_pre.add_argument("--body-file", default="")
    p_pre.add_argument("--files", nargs="*", default=[])
    p_pre.add_argument("--audience", choices=("triage", "worker", "review"), default="worker")
    p_review = sub.add_parser("review")
    p_review.add_argument("--pr", type=int, required=True)
    p_find = sub.add_parser("findings")
    p_find.add_argument("verdict")
    args = parser.parse_args(argv)
    if args.cmd == "preread":
        body = args.body
        if args.body_file:
            try:
                body = Path(args.body_file).read_text(encoding="utf-8", errors="replace")
            except OSError:
                body = ""
        sys.stdout.write(preread(args.title, body, args.files, args.audience, transport=transport))
    elif args.cmd == "review":
        context = pr_context(args.pr)
        if context:
            sys.stdout.write(preread(context[0], context[1], context[2], "review", transport=transport))
            shadow_check_tests(context[0], context[2], f"pr:{args.pr}", transport=transport)  # logged, never printed
    else:
        try:
            findings = json.loads(Path(args.verdict).read_text(encoding="utf-8")).get("findings") or []
        except (OSError, ValueError):
            findings = []
        sys.stdout.write(finding_checklist(findings, transport=transport))
    return 0


if __name__ == "__main__":
    sys.exit(main())
