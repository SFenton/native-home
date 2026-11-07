#!/usr/bin/env python3
"""Runner for the design-defect eval: everything except the judging, which agents do.

Subcommands (see README.md, "How Phase B runs it"):
  select       choose cases, stratified across categories, write build/evals/design-defects/<run>.grader/plan.json
  prepare      detached worktree at a case's ref, print the pose-matrix commands for the Verifier
  brief        Designer brief (evidence pack + atlas mockup; never the report, expected text or fix ref)
  grade-brief  grader brief (owner report, expected, rubric, output schema)
  score        read grader outputs, write build/evals/design-defects/<run>.json and a markdown summary
  cleanup      remove the run's dd- worktrees

Standard library only. It never builds, boots a simulator or runs a journey.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import random
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CASES_DIR = HERE / "cases"
OUT_ROOT = ROOT / "build" / "evals" / "design-defects"
UIKIT_BRANCH = "claude/uikit-port"

SCORES = {"flagged": 1.0, "partial": 0.5, "missed": 0.0, "false_pass": 0.0}
LABELS = tuple(SCORES) + ("infra",)
FIX_LABELS = ("clean", "false_alarm", "infra")

SIMS = {  # family -> (name, env override), as tools/ios_uitest.sh
    "iphone": ("iPhone 17 Pro", "FENTON_SIM_IPHONE"),
    "ipad": ("iPad Pro 11-inch (M5)", "FENTON_SIM_IPAD"),
    "duo": ("iPhone Duo (HASS)", "FENTON_SIM_DUO"),
}


# MARK: - Cases

def load_cases(cases_dir: Path = CASES_DIR) -> list[dict]:
    return [json.loads(p.read_text()) for p in sorted(cases_dir.glob("*.json"))]


def case_by_id(case_id: str, cases_dir: Path = CASES_DIR) -> dict:
    path = cases_dir / f"{case_id}.json"
    if not path.exists():
        sys.exit(f"run: no case {case_id!r}")
    return json.loads(path.read_text())


def select_cases(cases: list[dict], category: str | None = None, confidence: str | None = None,
                 app: str | None = None, limit: int | None = None, seed: int = 0) -> list[dict]:
    """Filter, then interleave categories round-robin (seeded) so a small limit still spans them.

    Cases with null refs are skipped. Perf is skipped unless `category == "perf"`.
    """
    pool = [c for c in cases if c["pre_fix_ref"] and c["fix_ref"]]
    if category:
        pool = [c for c in pool if c["category"] == category]
    else:
        pool = [c for c in pool if c["category"] != "perf"]
    if confidence:
        pool = [c for c in pool if c["fix_confidence"] == confidence]
    if app:
        pool = [c for c in pool if c["app"] == app]
    rng = random.Random(seed)
    buckets: dict[str, list[dict]] = defaultdict(list)
    for c in sorted(pool, key=lambda c: c["id"]):
        buckets[c["category"]].append(c)
    cats = sorted(buckets)
    for cat in cats:
        rng.shuffle(buckets[cat])
    rng.shuffle(cats)
    picked: list[dict] = []
    while any(buckets[c] for c in cats) and (limit is None or len(picked) < limit):
        for cat in cats:
            if buckets[cat] and (limit is None or len(picked) < limit):
                picked.append(buckets[cat].pop())
    return picked


def plan_entry(c: dict) -> dict:
    keys = ("id", "surface", "poses", "app", "category", "pre_fix_ref", "fix_ref", "fix_confidence")
    return {k: c[k] for k in keys}


# MARK: - Paths

def run_dir(run_id: str, out_root: Path = OUT_ROOT) -> Path:
    return out_root / run_id


def case_dir(run_id: str, case_id: str, out_root: Path = OUT_ROOT) -> Path:
    """Neutral directory name: the Designer sees these paths and case ids are descriptive."""
    return run_dir(run_id, out_root) / ("case-" + hashlib.sha1(case_id.encode()).hexdigest()[:8])


def grader_dir(run_id: str, out_root: Path | None = None) -> Path:
    """Grader-only tree, a sibling of the run dir the Designer can browse: plan, grader briefs, grade.json.
    The Designer brief never names it."""
    return (out_root or OUT_ROOT) / f"{run_id}.grader"


def grader_case_dir(run_id: str, case_id: str, out_root: Path | None = None) -> Path:
    return grader_dir(run_id, out_root) / ("case-" + hashlib.sha1(case_id.encode()).hexdigest()[:8])


def main_checkout(root: Path = ROOT) -> Path:
    common = subprocess.run(["git", "-C", str(root), "rev-parse", "--git-common-dir"],
                            capture_output=True, text=True, check=True).stdout.strip()
    common_path = Path(common) if common.startswith("/") else root / common
    return common_path.resolve().parent


def lane_name(case_id: str, which: str) -> str:
    """Neutral worktree name: the case hash, never the slug, so the evidence pack path the Designer sees does not
    name the defect (the 2026-11-01 pilot's packs were under ``dd-<slug>-pre``)."""
    return f"dd-{hashlib.sha1(case_id.encode()).hexdigest()[:8]}-{which}"


def ref_of(case: dict, which: str) -> str:
    ref = case["pre_fix_ref" if which == "pre" else "fix_ref"]
    if not ref:
        sys.exit(f"run: {case['id']} has no {which} ref")
    return ref


# MARK: - prepare

def ref_exists(repo: Path, ref: str) -> bool:
    return subprocess.run(["git", "-C", str(repo), "cat-file", "-e", ref + "^{commit}"],
                          capture_output=True).returncode == 0


def ensure_worktree(case: dict, which: str, repo: Path) -> Path:
    ref = ref_of(case, which)
    dest = repo / ".claude" / "worktrees" / lane_name(case["id"], which)
    if (dest / ".git").exists():
        return dest
    if not ref_exists(repo, ref):
        subprocess.run(["git", "-C", str(repo), "fetch", "-q", "origin", UIKIT_BRANCH], check=False)
        if not ref_exists(repo, ref):
            sys.exit(f"run: {ref} is not in this clone, even after fetching origin {UIKIT_BRANCH}")
    subprocess.run(["git", "-C", str(repo), "worktree", "add", "-q", "--detach", str(dest), ref], check=True)
    return dest


def families(poses: list[str]) -> list[str]:
    fam: list[str] = []
    for p in poses:
        group = ["duo", "ipad"] if p.startswith("rotate") else ["iphone"] if p == "iphone" else \
                ["ipad"] if p.startswith("ipad") else ["duo"]
        for g in group:
            if g not in fam:
                fam.append(g)
    return fam


def pose_commands(case: dict, which: str, worktree: Path) -> list[str]:
    """The exact shell lines the Verifier runs, each device command inside a devcap simulator hold."""
    lane = lane_name(case["id"], which)
    out = []
    capture = (f"TEST_RUNNER_FENTON_CAPTURE_DIR=build/evidence/{lane}/%s "
               "TEST_RUNNER_FENTON_REDACT_PRIVATE=1")
    out.append(f"cd {worktree}")
    out.append("# journey for this surface: python3 tools/affected_tests.py  (use its -only-testing value as $JOURNEY)")
    for fam in families(case["poses"]):
        name, env = SIMS[fam]
        out.append(f'UDID_{fam.upper()}=$(python3 tools/devcap.py pick-sim --name "${{{env}:-{name}}}" --pool 0)')
    for pose in case["poses"]:
        fam = families([pose])[0]
        udid = f'"$UDID_{fam.upper()}"'
        hold = f"python3 tools/devcap.py run --sim {udid} --hold 900 --"
        env = capture % pose
        test = f"tools/ios_uitest.sh --quick --env shell --only {fam} -only-testing:$JOURNEY"
        if pose == "iphone" or pose in ("ipad-portrait", "duo-folded"):
            out.append(f"{hold} env {env} {test}")
        elif pose == "ipad-landscape":
            out.append(f"{hold} env {env} TEST_RUNNER_FENTON_UITEST_ORIENTATION=landscape {test}")
        elif pose in ("duo-unfolded-landscape", "duo-unfolded-portrait", "duo-partial-fold"):
            steps = {"duo-unfolded-landscape": ["unfolded"], "duo-unfolded-portrait": ["unfolded", "rotate-left"],
                     "duo-partial-fold": ["half"]}[pose]
            for s in steps:
                out.append(f"{hold} python3 tools/duo_pose.py --sim {udid} --set {s}")
            out.append(f"# confirm the pose (inner panel lit: simctl io {udid} screenshot --display=primary-1), then:")
            out.append(f"{hold} env {env} {test}")
        else:  # rotate-in / rotate-out: open a sheet, rotate, re-measure (Duo and iPad)
            for f2 in families([pose]):
                u2 = f'"$UDID_{f2.upper()}"'
                out.append(f"# {pose} on {f2}: open the surface's sheet, rotate, check it re-fits "
                           f"(duo_pose.py --set rotate-left|rotate-right on the Duo, XCUIDevice.orientation on iPad)")
                out.append(f"{f'python3 tools/devcap.py run --sim {u2} --hold 900 --'} env {capture % pose} "
                           f"tools/ios_uitest.sh --quick --env shell --only {f2} -only-testing:$JOURNEY")
    out.append(f"# then write build/evidence/{lane}/manifest.json per .agents/skills/pose-matrix/SKILL.md "
               f"(one entry per pose; a pose not run is not_run with a reason)")
    return out


def cmd_prepare(args: argparse.Namespace) -> int:
    case = case_by_id(args.case)
    repo = main_checkout()
    worktree = ensure_worktree(case, args.ref, repo)
    cdir = case_dir(args.run, case["id"])
    cdir.mkdir(parents=True, exist_ok=True)
    pack = worktree / "build" / "evidence" / lane_name(case["id"], args.ref)
    meta = {"case": hashlib.sha1(case["id"].encode()).hexdigest()[:8], "ref": args.ref, "sha": ref_of(case, args.ref), "worktree": str(worktree),
            "evidence_pack": str(pack / "manifest.json")}
    (cdir / f"prepare-{args.ref}.json").write_text(json.dumps(meta, indent=2) + "\n")
    alias = cdir / f"pack-{args.ref}"  # neutral path for the Designer brief (the real one carries the case id)
    if alias.is_symlink():
        alias.unlink()
    alias.symlink_to(pack)
    print(f"worktree: {worktree} (detached at {meta['sha']})")
    print(f"evidence pack to write: {meta['evidence_pack']}")
    print("pose-matrix commands:")
    for line in pose_commands(case, args.ref, worktree):
        print("  " + line)
    return 0


# MARK: - briefs

def catalog_mockup(surface: str | None, root: Path = ROOT) -> str:
    if not surface:
        return "none (the case has no atlas surface; judge from the evidence pack and the HIG)"
    catalog = json.loads((root / ".agents/design/mockups/catalog.json").read_text())["items"]
    for item in catalog:
        if item["id"] == surface:
            return str(root / ".agents/design/mockups" / (item["path"] + ".html"))
    return f"none (surface {surface!r} is not in catalog.json)"


def designer_brief(case: dict, which: str, run_id: str, root: Path = ROOT) -> str:
    """Never includes owner_report, expected, fix_ref, fix_confidence, the case id or category."""
    prep = case_dir(run_id, case["id"]) / f"prepare-{which}.json"
    pack = str(case_dir(run_id, case["id"]) / f"pack-{which}" / "manifest.json") if prep.exists() else "(run `prepare` first)"
    verdict = case_dir(run_id, case["id"]) / which / "verdict.md"
    return f"""# Designer brief: review an evidence pack

You are the Designer. Review the app as it stands in this evidence pack and say whether the change is ready to
ship on every pose. Judge only from the pack and the atlas; do not read git history, other branches or any file
outside the paths below.

- Evidence pack: {pack}
  (poses, screenshots, accessibility-tree dumps and measurements; a pose with result not_run was not captured)
- Atlas mockup for the surface (how it should look and move): {catalog_mockup(case["surface"], root)}
- Poses to judge: {", ".join(case["poses"])}
- Rules: AGENTS.md invariants, .agents/patterns, Apple HIG (cite the section). Name any defect with the pose,
  the surface and the evidence (a frame or tree line or a screenshot path). Some defects cannot be seen in stills
  (timing, frame rate, memory): say so and request the measurement instead of passing.

Write your verdict to {verdict}: `pass` or `fail`, then each finding with pose, surface, evidence and a one-line fix.
End with the status block from .agents/workflow/agent-roster.md#contracts.
"""


def cmd_brief(args: argparse.Namespace) -> int:
    case = case_by_id(args.case)
    cdir = case_dir(args.run, case["id"])
    cdir.mkdir(parents=True, exist_ok=True)
    out = cdir / f"designer-brief-{args.ref}.md"
    out.write_text(designer_brief(case, args.ref, args.run))
    print(out)
    return 0


RUBRIC = """\
- flagged (1.0): the verdict names the defect, in the right pose and surface, with evidence from the pack
  (a frame, a tree line or a screenshot path).
- partial (0.5): names the area or symptom but not the defect (e.g. "the sheet looks large" for a 70% sheet),
  or names it in the wrong pose, or names it without evidence.
- missed (0): not mentioned, or the verdict passes the surface.
- false_pass: the verdict PASSES a case whose defect is known. Use label "false_pass" (score 0), not "missed".
- perf cases: flagged only if the verdict declines to judge from stills and requests the named measurement.
- infra: the harness failed (no usable evidence pack, devcap timeout, wrong pose). Not scored; give infra_class.
"""

FIX_RUBRIC = """\
This is the FIXED commit. The defect should be gone. Label "clean" if the verdict passes or raises nothing
matching the expected defect; "false_alarm" if it still flags that defect (or an invented one) as a failure;
"infra" if the evidence is unusable.
"""


def grade_brief(case: dict, which: str, run_id: str) -> str:
    verdict = case_dir(run_id, case["id"]) / which / "verdict.md"
    out = grader_case_dir(run_id, case["id"]) / which / "grade.json"
    labels = "|".join(FIX_LABELS if which == "fix" else LABELS)
    return f"""# Grader brief

You are the grader. Read only the verdict file and the case below; never the fix diff, git history or the
evidence pack's source tree.

- Case: {case["id"]} ({case["category"]}, app {case["app"]}, surface {case["surface"]}, poses {", ".join(case["poses"])})
- Owner report (their words): {case["owner_report"]}
- Expected (what a good review of the pre-fix commit must flag): {case["expected"]}
- Verdict to grade: {verdict}
- Ref graded: {which}

## Rubric

{FIX_RUBRIC if which == "fix" else RUBRIC}
## Output

Write {out} as JSON:

{{"case": "{case["id"]}", "score": 0.0, "label": "{labels}", "false_pass": false, "evidence_cited": false, "notes": "<= 60 words"}}

(score is 1.0, 0.5 or 0 for the pre-fix ref; omit score for infra; add "infra_class" for infra.)
End with the status block from .agents/workflow/agent-roster.md#contracts.
"""


def cmd_grade_brief(args: argparse.Namespace) -> int:
    case = case_by_id(args.case)
    out = grader_case_dir(args.run, case["id"]) / f"grader-brief-{args.ref}.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(grade_brief(case, args.ref, args.run))
    print(out)
    return 0


# MARK: - score

def load_grades(run_id: str, plan: list[dict], out_root: Path = OUT_ROOT, which: str = "pre") -> tuple[dict, list]:
    grades, ungraded = {}, []
    for entry in plan:
        path = grader_case_dir(run_id, entry["id"], out_root) / which / "grade.json"
        if not path.exists():
            ungraded.append(entry["id"])
            continue
        try:
            grades[entry["id"]] = json.loads(path.read_text())
        except json.JSONDecodeError:
            ungraded.append(entry["id"])
    return grades, ungraded


def pct(x: float) -> str:
    return f"{100 * x:.0f}%"


def aggregate(plan: list[dict], grades: dict) -> dict:
    """Headline = (flagged + 0.5 partial) / scored cases. Infra and ungraded cases are excluded."""
    by_id = {e["id"]: e for e in plan}
    scored, infra = [], []
    for cid, g in grades.items():
        if cid not in by_id:
            continue
        label = g.get("label")
        if label == "infra":
            infra.append({"case": cid, "infra_class": g.get("infra_class", "unknown")})
        elif label in SCORES:
            scored.append((by_id[cid], g))

    def points(g: dict) -> float:
        return SCORES[g["label"]]

    def rollup(key_fn) -> dict:
        buckets: dict[str, list[float]] = defaultdict(list)
        for entry, g in scored:
            for k in key_fn(entry):
                buckets[k].append(points(g))
        return {k: {"cases": len(v), "score": round(sum(v) / len(v), 4)} for k, v in sorted(buckets.items())}

    total = [points(g) for _, g in scored]
    return {
        "scored_cases": len(scored),
        "headline": round(sum(total) / len(total), 4) if total else None,
        "flagged": sum(g["label"] == "flagged" for _, g in scored),
        "partial": sum(g["label"] == "partial" for _, g in scored),
        "missed": sum(g["label"] == "missed" for _, g in scored),
        "false_pass": sum(g["label"] == "false_pass" or bool(g.get("false_pass")) for _, g in scored),
        "by_category": rollup(lambda e: [e["category"]]),
        "by_pose": rollup(lambda e: e["poses"]),
        "by_app": rollup(lambda e: [e["app"]]),
        "infra": sorted(infra, key=lambda i: i["case"]),
    }


def fix_summary(plan: list[dict], fix_grades: dict) -> dict:
    ids = {e["id"] for e in plan}
    labels = [g.get("label") for c, g in fix_grades.items() if c in ids]
    return {"graded": sum(l in ("clean", "false_alarm") for l in labels),
            "false_alarm": labels.count("false_alarm"),
            "false_alarm_cases": sorted(c for c, g in fix_grades.items() if c in ids and g.get("label") == "false_alarm"),
            "infra": labels.count("infra")}


def markdown(run_id: str, agg: dict, ungraded: list, fix: dict) -> str:
    head = pct(agg["headline"]) if agg["headline"] is not None else "n/a"
    lines = [f"# Design-defect eval {run_id}", "",
             f"**Caught before deploy: {head}** over {agg['scored_cases']} scored cases "
             f"(flagged {agg['flagged']}, partial {agg['partial']}, missed {agg['missed']}). "
             f"**False passes: {agg['false_pass']}.**", ""]
    for title, key in (("Category", "by_category"), ("Pose", "by_pose"), ("App", "by_app")):
        lines += [f"| {title} | Cases | Score |", "|---|---|---|"]
        lines += [f"| {k} | {v['cases']} | {pct(v['score'])} |" for k, v in agg[key].items()]
        lines.append("")
    if fix["graded"] or fix["infra"]:
        lines.append(f"Fixed commits: {fix['false_alarm']} false alarm(s) in {fix['graded']} graded."
                     + (f" Cases: {', '.join(fix['false_alarm_cases'])}." if fix["false_alarm_cases"] else ""))
        lines.append("")
    if agg["infra"]:
        lines.append("Infra results (excluded, rerun them): " +
                     ", ".join(f"{i['case']} ({i['infra_class']})" for i in agg["infra"]))
        lines.append("")
    if ungraded:
        lines.append("Not yet graded: " + ", ".join(sorted(ungraded)))
        lines.append("")
    return "\n".join(lines)


def build_score(run_id: str, out_root: Path = OUT_ROOT) -> tuple[dict, str]:
    plan_path = grader_dir(run_id, out_root) / "plan.json"
    if not plan_path.exists():
        sys.exit(f"run: no plan at {plan_path}")
    plan = json.loads(plan_path.read_text())["cases"]
    grades, ungraded = load_grades(run_id, plan, out_root, "pre")
    fix_grades, _ = load_grades(run_id, plan, out_root, "fix")
    agg = aggregate(plan, grades)
    fix = fix_summary(plan, fix_grades)
    result = {"run": run_id, **agg, "ungraded": sorted(ungraded), "fix_ref": fix,
              "cases": {cid: g for cid, g in sorted(grades.items())}}
    return result, markdown(run_id, agg, ungraded, fix)


def cmd_score(args: argparse.Namespace) -> int:
    result, md = build_score(args.run)
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / f"{args.run}.json").write_text(json.dumps(result, indent=2) + "\n")
    (OUT_ROOT / f"{args.run}.md").write_text(md)
    print(md)
    return 0


# MARK: - select / cleanup

def new_run_id(seed: int) -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S") + f"-s{seed}"


def cmd_select(args: argparse.Namespace) -> int:
    picked = select_cases(load_cases(), args.category, args.confidence, args.app, args.limit, args.seed)
    if not picked:
        sys.exit("run: no case matches")
    run_id = args.run_id or new_run_id(args.seed)
    rdir = grader_dir(run_id)
    rdir.mkdir(parents=True, exist_ok=True)
    plan = {"run": run_id, "seed": args.seed, "filters": {"category": args.category, "confidence": args.confidence,
                                                          "app": args.app, "limit": args.limit},
            "cases": [plan_entry(c) for c in picked]}
    (rdir / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    print(f"run id: {run_id}\nplan: {rdir / 'plan.json'}")
    for c in picked:
        print(f"  {c['id']}  {c['category']}  {c['app']}  {c['surface']}  {','.join(c['poses'])}")
    return 0


def cmd_cleanup(args: argparse.Namespace) -> int:
    plan = json.loads((grader_dir(args.run) / "plan.json").read_text())["cases"]
    repo = main_checkout()
    for entry in plan:
        for which in ("pre", "fix"):
            dest = repo / ".claude" / "worktrees" / lane_name(entry["id"], which)
            if (dest / ".git").exists():
                subprocess.run(["git", "-C", str(repo), "worktree", "remove", "--force", str(dest)], check=False)
                print(f"removed {dest}")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("select")
    s.add_argument("--category")
    s.add_argument("--confidence", choices=["high", "medium", "low"])
    s.add_argument("--app", choices=["swiftui", "uikit"])
    s.add_argument("--limit", type=int)
    s.add_argument("--seed", type=int, default=0)
    s.add_argument("--run-id")
    s.set_defaults(fn=cmd_select)
    for name, fn in (("prepare", cmd_prepare), ("brief", cmd_brief), ("grade-brief", cmd_grade_brief)):
        q = sub.add_parser(name)
        q.add_argument("run")
        q.add_argument("case")
        q.add_argument("--ref", choices=["pre", "fix"], default="pre")
        q.set_defaults(fn=fn)
    for name, fn in (("score", cmd_score), ("cleanup", cmd_cleanup)):
        q = sub.add_parser(name)
        q.add_argument("run")
        q.set_defaults(fn=fn)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
