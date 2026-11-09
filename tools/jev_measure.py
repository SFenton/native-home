#!/usr/bin/env python3
"""Measure the Jev hints against history (`.agents/workflow/decision-models.md` records the results).

    python3 tools/jev_measure.py recall [--prs 50] [--prs-file FILE] [--json OUT]
    python3 tools/jev_measure.py complexity [--prs 50] [--prs-file FILE] [--json OUT]
    python3 tools/jev_measure.py sections [--labels FILE] [--max-usd 0.5] [--json OUT]

`recall`: for each of the last N merged PRs whose files touch at least one pattern, rank the patterns by
`context.patterns` from the PR title and body (paths and pattern-doc names are stripped so the text reads like a
request) and compare with a keyword baseline over the registry's `keywords`. Ground truth is the set of patterns
whose canonical or owned files, or whose doc, the PR changed (`pattern_guard.py changed`). A second variant adds
the changed file names to the Jev state (the review-time input).

`complexity`: Spearman rank correlation between the `route.complexity` score and the PR's size (lines changed, and
files changed).

`sections`: hand-labeled (question, repository doc) pairs for `research.section_relevant`
(`tools/tests/fixtures/jev_section_labels.json`: a section is relevant when it contains one of the pair's phrases).
Compares the hit rate (a relevant section in the top 1 and the top 3) and the mean reciprocal rank of
`tools/jev_sections.py` against BM25 alone over the same sections, and reports the spend (`--max-usd` stops the run).

Needs the key file `~/.config/fenton-hass/typesafe.key` (or `TYPESAFE_API_KEY` when there is no file) (exit 3 without a key) and `gh` (or `--prs-file` with `gh pr list --state merged --json
number,title,body,files,additions,deletions` output). Standard library only.
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
KS = (1, 3, 5, 8)


def _load(name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


guard = _load("pattern_guard")
jev = _load("jev_ask")


# MARK: - Ground truth and text

def truth(data: dict[str, Any], files: list[str]) -> set[str]:
    """Patterns whose canonical or owned files, or whose doc, `files` touch."""
    found: set[str] = set()
    for f in files:
        found.update(pid for pid, role in guard.owners(data, f) if role in ("canonical", "owns"))
        match = re.fullmatch(r"\.agents/patterns/([a-z0-9-]+)\.md", f)
        if match and match.group(1) != "README":
            found.add(match.group(1))
    return found


def sanitize(text: str, ids: set[str]) -> str:
    """The PR text as a request would read: no checklist lines, trailers, paths or pattern doc names."""
    kept = []
    for line in (text or "").splitlines():
        if re.match(r"\s*- \[[ xX]\]", line) or line.startswith(("Co-Authored-By", "Release-Note", "🤖")):
            continue
        kept.append(line)
    out = "\n".join(kept)
    out = re.sub(r"\S+/\S+\.\w+", " ", out)
    out = re.sub(r"\b(" + "|".join(re.escape(i) for i in sorted(ids, key=len, reverse=True)) + r")\.md\b", " ", out)
    return out.strip()[:3000]


# MARK: - Rankings and metrics

def keyword_rank(data: dict[str, Any], text: str) -> list[str]:
    """Patterns ranked by how many of their keywords (and id words) appear in `text`; ties by id."""
    lowered = text.lower()
    scored = []
    for p in data["patterns"]:
        terms = {k.lower() for k in p.get("keywords") or []} | {p["id"].replace("-", " ")}
        hits = sum(1 for t in terms if re.search(r"(?<![a-z0-9])" + re.escape(t) + r"(?![a-z0-9])", lowered))
        scored.append((-hits, p["id"]))
    return [pid for _, pid in sorted(scored)]


def recall_at(ranked: list[str], expected: set[str], k: int) -> float:
    """Fraction of `expected` found in the first `k` of `ranked`."""
    return len(expected & set(ranked[:k])) / len(expected) if expected else 0.0


def summarize(rows: list[tuple[list[str], set[str]]]) -> dict[str, Any]:
    """Mean recall@k, hit@k (any true pattern) and full@k (all of them) over (ranked, truth) rows."""
    out: dict[str, Any] = {"n": len(rows)}
    for k in KS:
        out[f"recall@{k}"] = round(sum(recall_at(r, t, k) for r, t in rows) / len(rows), 3) if rows else 0.0
    out["hit@8"] = round(sum(bool(t & set(r[:8])) for r, t in rows) / len(rows), 3) if rows else 0.0
    out["full@8"] = round(sum(t <= set(r[:8]) for r, t in rows) / len(rows), 3) if rows else 0.0
    return out


def spearman(xs: list[float], ys: list[float]) -> float:
    """Spearman rank correlation (average ranks for ties); 0.0 with fewer than 3 points or no spread."""
    def ranks(values: list[float]) -> list[float]:
        order = sorted(range(len(values)), key=lambda i: values[i])
        out = [0.0] * len(values)
        i = 0
        while i < len(order):
            j = i
            while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
                j += 1
            for idx in order[i:j + 1]:
                out[idx] = (i + j) / 2 + 1
            i = j + 1
        return out
    if len(xs) < 3:
        return 0.0
    rx, ry = ranks(xs), ranks(ys)
    mx, my = sum(rx) / len(rx), sum(ry) / len(ry)
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    den = (sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry)) ** 0.5
    return round(num / den, 3) if den else 0.0


# MARK: - Runs

def fetch_prs(limit: int, path: str = "") -> list[dict[str, Any]]:
    """The last `limit` merged PRs (newest first) from `path` or `gh`."""
    if path:
        prs = json.loads(Path(path).read_text(encoding="utf-8"))
    else:
        out = subprocess.run(["gh", "pr", "list", "--state", "merged", "--limit", str(limit), "--json",
                              "number,title,body,files,additions,deletions"], cwd=ROOT, capture_output=True,
                             text=True, check=True)
        prs = json.loads(out.stdout)
    return prs[:limit]


def jev_rank(question: Any, context: dict[str, Any]) -> list[str] | None:
    decision = jev.ask_question(question, context)
    if decision is None:
        return None
    return [k for k, _ in sorted(decision.probabilities.items(), key=lambda kv: (-kv[1], kv[0]))]


def run_recall(prs: list[dict[str, Any]]) -> dict[str, Any]:
    data = guard.load()
    ids = {p["id"] for p in data["patterns"]}
    question = jev.load_questions()["context.patterns"]
    rows: dict[str, list[tuple[list[str], set[str]]]] = {"keyword": [], "jev": [], "jev+files": []}
    skipped = 0
    for pr in prs:
        files = [f["path"] for f in pr.get("files") or []]
        expected = truth(data, files)
        if not expected:
            skipped += 1
            continue
        text = sanitize(pr.get("body") or "", ids)
        title = sanitize(pr.get("title") or "", ids)
        base = {"title": title, "body": text}
        ranked = jev_rank(question, base)
        with_files = jev_rank(question, {**base, "files": "\n".join(files)[:3000]})
        if ranked is None or with_files is None:
            return {"error": jev.NO_KEY if not jev.api_key() else "no answer from the API"}
        rows["keyword"].append((keyword_rank(data, f"{title}\n{text}"), expected))
        rows["jev"].append((ranked, expected))
        rows["jev+files"].append((with_files, expected))
    focused = {k: summarize([(r, e) for r, e in v if len(e) <= 3]) for k, v in rows.items()}
    return {"prs": len(prs), "without_pattern_files": skipped, "variants": {k: summarize(v) for k, v in rows.items()},
            "focused_prs_up_to_3_true_patterns": focused,
            "mean_true_patterns": round(sum(len(t) for _, t in rows["jev"]) / max(1, len(rows["jev"])), 2),
            "keyword_blind": sum(1 for r, t in rows["keyword"] if not (t & set(r[:8]))),
            "model": jev.model()}


def run_complexity(prs: list[dict[str, Any]]) -> dict[str, Any]:
    data = guard.load()
    ids = {p["id"] for p in data["patterns"]}
    question = jev.load_questions()["route.complexity"]
    scores, lines, files = [], [], []
    lanes: dict[str, int] = {}
    for pr in prs:
        context = {"title": sanitize(pr.get("title") or "", ids), "body": sanitize(pr.get("body") or "", ids)}
        decision = jev.ask_question(question, context)
        if decision is None:
            return {"error": jev.NO_KEY if not jev.api_key() else "no answer from the API"}
        scores.append(decision.score or 0.0)
        lines.append(float((pr.get("additions") or 0) + (pr.get("deletions") or 0)))
        files.append(float(len(pr.get("files") or [])))
        lane = question.lane(decision.score or 0.0) or "?"
        lanes[lane] = lanes.get(lane, 0) + 1
    return {"prs": len(prs), "spearman_lines": spearman(scores, lines), "spearman_files": spearman(scores, files),
            "lanes": lanes, "model": jev.model()}


LABELS = HERE / "tests" / "fixtures" / "jev_section_labels.json"


def first_hit(order: list[str], relevant: set[str]) -> int | None:
    """1-based rank of the first relevant id in `order`, or None."""
    return next((n for n, key in enumerate(order, 1) if key in relevant), None)


def summarize_ranks(ranks: list[int | None]) -> dict[str, float]:
    """Hit@1, hit@3 and mean reciprocal rank of first-hit ranks (None = never)."""
    n = max(1, len(ranks))
    return {"hit@1": round(sum(1 for r in ranks if r == 1) / n, 3),
            "hit@3": round(sum(1 for r in ranks if r is not None and r <= 3) / n, 3),
            "mrr": round(sum(1 / r for r in ranks if r) / n, 3)}


def run_sections(labels_path: Path = LABELS, max_usd: float = 0.5, transport: Any = None) -> dict[str, Any]:
    """Jev rerank against BM25 on the hand-labeled pairs; stops once the input tokens cost `max_usd`."""
    sec = _load("jev_sections")
    usage = sec.jev  # the module jev_sections asks through: its USAGE counts the requests
    labels = json.loads(labels_path.read_text(encoding="utf-8"))["pairs"]
    start_tokens = usage.USAGE["input_tokens"]
    start_calls = usage.USAGE["calls"]
    jev_ranks: list[int | None] = []
    bm_ranks: list[int | None] = []
    misses = []
    for pair in labels:
        spent = (usage.USAGE["input_tokens"] - start_tokens) * usage.PRICE_PER_MILLION_INPUT / 1e6
        if spent >= max_usd:
            break
        path = ROOT / pair["file"]
        text = path.read_text(encoding="utf-8")
        parts = sec.split_sections(text, sec.detect_kind(pair["file"], text))
        relevant = {s.id for s in parts if any(phrase in s.text for phrase in pair["any_of"])}
        scores = sec.bm25_scores(pair["question"], [f"{s.title}\n{s.title}\n{s.text}" for s in parts])
        bm_order = [s.id for s in sorted(parts, key=lambda s: (-scores[s.index], s.index))]
        result = sec.find_sections(text, pair["question"], name=pair["file"], top=len(parts), transport=transport)
        if result["ranker"] != "jev":
            return {"error": jev.NO_KEY if not jev.api_key() else "no answer from the API"}
        asked = [row["id"] for row in result["top"]][:result["asked"]]
        jev_order = asked + [key for key in bm_order if key not in asked]  # not shortlisted: after, in BM25 order
        jev_ranks.append(first_hit(jev_order, relevant))
        bm_ranks.append(first_hit(bm_order, relevant))
        if not jev_ranks[-1] or jev_ranks[-1] > 3:
            misses.append({"question": pair["question"], "file": pair["file"], "jev_rank": jev_ranks[-1],
                           "bm25_rank": bm_ranks[-1]})
    tokens = usage.USAGE["input_tokens"] - start_tokens
    return {"pairs": len(jev_ranks), "jev": summarize_ranks(jev_ranks), "bm25": summarize_ranks(bm_ranks),
            "jev_misses_top3": misses, "requests": usage.USAGE["calls"] - start_calls, "input_tokens": tokens,
            "spend_usd": round(tokens * usage.PRICE_PER_MILLION_INPUT / 1e6, 4), "model": jev.model()}


def main(argv: list[str] | None = None) -> int:
    """Command-line entry point."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cmd", choices=("recall", "complexity", "sections"))
    parser.add_argument("--labels", default=str(LABELS))
    parser.add_argument("--max-usd", type=float, default=0.5)
    parser.add_argument("--prs", type=int, default=50)
    parser.add_argument("--prs-file", default="")
    parser.add_argument("--json", default="", help="also write the result here")
    args = parser.parse_args(argv)
    if not jev.api_key():
        print(f"jev_measure: {jev.NO_KEY}", file=sys.stderr)
        return jev.EXIT_UNAVAILABLE
    if args.cmd == "sections":
        result = run_sections(Path(args.labels), args.max_usd)
    else:
        prs = fetch_prs(args.prs, args.prs_file)
        result = run_recall(prs) if args.cmd == "recall" else run_complexity(prs)
    text = json.dumps(result, indent=2)
    print(text)
    if args.json:
        Path(args.json).write_text(text + "\n", encoding="utf-8")
    return jev.EXIT_UNAVAILABLE if "error" in result else 0


if __name__ == "__main__":
    sys.exit(main())
