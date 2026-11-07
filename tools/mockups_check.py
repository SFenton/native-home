#!/usr/bin/env python3
"""Check the mockup atlas: folders, READMEs, catalog.json and each mockup's config (static).

    python3 tools/mockups_check.py          # exit 1 on any problem

Checks: every mockup folder (pages/<area>/<id>, modals/<area>/<id>, components/<group>/<id>, flows/<id>, proposals/<id>) holds <id>.html and a README.md of
at most 40 lines (proposals excepted: frozen records); a Mock.mount config names source, spec, states, a11y and reviews (the runtime Mock.lint banner checks the rest); _kit/components matches
Mock.COMPONENTS; catalog.json ({items:[{id,path,mockup,sources,status}]}) lists every mockup on disk, proposals included, sets `mockup` once the file exists and names existing sources.

Lifecycle (README.md, "Lifecycle"): `status` is one of shipped, proposed, decided (needs `decision`: an existing repo path or "PR #n"), superseded (needs `supersededBy`:
a catalogued id), designed-not-wired, placeholder. An `inFlight.branch` fails when it is `main`, is the PR's own head branch (`GITHUB_HEAD_REF`, else the checked-out branch: the merging PR clears it),
is merged into the base or is gone from origin, squash merges included. The base is `origin/$GITHUB_BASE_REF` in CI; locally it is the branch's recorded `sh-base`, then the remote default, then
origin/main. Results depend on `git fetch --prune origin` (a merged, deleted or own-branch marker means the entry is stale: set `inFlight` to null and `status` to shipped). A Mock.mount `source:` list fails on a path that does not exist. Any .html under the atlas that
the catalog does not list fails (the kit gallery excepted). Stdlib only.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / ".agents" / "design" / "mockups"
DEPTH = {"pages": 2, "modals": 2, "components": 2, "flows": 1, "proposals": 1}
REQUIRED = ["source", "spec", "states", "a11y", "reviews", "devices"]
STATUSES = {"shipped", "proposed", "decided", "superseded", "designed-not-wired", "placeholder"}
UNCATALOGUED_OK = {"_kit/gallery.html"}
problems = []


def bad(msg):
    problems.append(msg)


def vcs(*args):
    """Run a read-only repository query; returns (exit code, stdout)."""
    r = subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True)
    return r.returncode, r.stdout.strip()


def mockup_dirs():
    for kind, depth in DEPTH.items():
        base = ROOT / kind
        if not base.is_dir():
            continue
        level = [base]
        for _ in range(depth):
            level = [d for p in level for d in sorted(p.iterdir()) if d.is_dir() and not d.name.startswith("_")]
        yield from level


def declared_sources(text):
    """Repo paths named in the Mock.mount `source: [ ... ]` list (strings and { path: '...' } objects)."""
    m = re.search(r"(^|[\s{,])source\s*:\s*\[", text)
    if not m:
        return []
    start = m.end() - 1
    depth, i, q = 0, start, None
    while i < len(text):
        c = text[i]
        if q:
            if c == "\\":
                i += 1
            elif c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                break
        i += 1
    return re.findall(r"""['"]((?:apple|tools|\.agents|contracts|docs)/[^'" ]+?)['"]""", text[start:i])


def check_config(html_path, kind):
    text = html_path.read_text(encoding="utf-8")
    for src in declared_sources(text):
        if not (REPO / src).exists():
            bad(f"{html_path.relative_to(ROOT)}: source `{src}` does not exist")
    if "Mock.mount(" not in text:
        if kind != "proposals":
            bad(f"{html_path.relative_to(ROOT)}: no Mock.mount(...) call")
        return
    for key in REQUIRED:
        if not re.search(r"(^|[\s{,])" + key + r"\s*:", text):
            bad(f"{html_path.relative_to(ROOT)}: config is missing `{key}:`")
    if "reviews" in text and not (re.search(r"\bhig\s*:", text) and re.search(r"\bswiftui\s*:", text)):
        bad(f"{html_path.relative_to(ROOT)}: reviews needs hig: and swiftui:")


def check_status(entry):
    status = entry.get("status", "shipped")
    if status not in STATUSES:
        bad(f"catalog.json: {entry['id']} status `{status}` is not one of {sorted(STATUSES)}")
    if status == "decided":
        decision = entry.get("decision") or ""
        if not decision:
            bad(f"catalog.json: {entry['id']} is decided but has no `decision` link")
        elif not re.match(r"PR #\d+$", decision) and not (REPO / decision).exists() and not (ROOT / decision).exists():
            bad(f"catalog.json: {entry['id']} decision `{decision}` does not exist")
    if status == "superseded" and not entry.get("supersededBy"):
        bad(f"catalog.json: {entry['id']} is superseded but has no `supersededBy`")


def base_ref():
    """The ref a PR lands into.

    `origin/$GITHUB_BASE_REF` when CI sets it and the ref exists. Otherwise the lane's base as
    `tools/hooks/mockup_hub_guard.lane_base` resolves it: `branch.<name>.sh-base`, then the remote default
    (`refs/remotes/origin/HEAD`), then `origin/main` (logic copied, the hook is untouched).
    """
    name = os.environ.get("GITHUB_BASE_REF", "").strip()
    if name and vcs("rev-parse", "--verify", "-q", f"origin/{name}")[0] == 0:
        return f"origin/{name}"
    branch = head_branch()
    if branch:
        code, out = vcs("config", "--get", f"branch.{branch}.sh-base")
        if code == 0 and out:
            return out
    code, out = vcs("symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    return out if code == 0 and out else "origin/main"


def head_branch():
    """The PR's own head branch: `$GITHUB_HEAD_REF` in CI, else the checked-out branch ("" when detached)."""
    name = os.environ.get("GITHUB_HEAD_REF", "").strip()
    if name:
        return name
    code, out = vcs("rev-parse", "--abbrev-ref", "HEAD")
    return out if code == 0 and out != "HEAD" else ""


def check_in_flight(entry):
    """An inFlight branch must be an unmerged branch on origin, and never the PR's own head (cleared in the merging PR)."""
    flight = entry.get("inFlight")
    if not flight:
        return
    branch = flight.get("branch") or ""
    where = f"catalog.json: {entry['id']} inFlight.branch `{branch}`"
    if branch in ("", "main", "origin/main"):
        bad(f"{where} is main: it is shipped, so set inFlight to null and status to shipped")
        return
    if branch == head_branch():
        bad(f"{where} is this PR's own head branch: the merging PR clears it, so set inFlight to null and status to shipped")
        return
    base = base_ref()
    if vcs("rev-parse", "--verify", "-q", base)[0] != 0:
        return  # no remote to compare with (an export of the repo)
    if vcs("rev-parse", "--verify", "-q", f"origin/{branch}")[0] != 0:
        bad(f"{where} is deleted from origin (merged or abandoned): set inFlight to null and fix the status")
    elif vcs("merge-base", "--is-ancestor", f"origin/{branch}", base)[0] == 0:
        bad(f"{where} is merged into {base}: set inFlight to null and status to shipped")
    elif is_merged(branch, base):
        bad(f"{where} is already merged into {base} (squash or rebase merge): set inFlight to null and status to shipped")


def is_merged(branch, base="origin/main"):
    """Whether origin/<branch> has nothing left to land in `base`: ancestor, cherry-equal, a squash merge or a merged PR.

    The repo squash-merges and leaves merged branches on origin, so an ancestor test alone misses most merges. A squash
    merge is detected by merging the branch into `base` in memory: if the resulting tree is the base's own tree,
    the branch adds nothing. When `gh` is installed, a merged PR from the branch also counts. Results depend on the
    local view of origin, so run `git fetch --prune origin` first (the check does not fetch).
    """
    code, out = vcs("cherry", base, f"origin/{branch}")
    if code == 0 and out and all(line.startswith("-") for line in out.splitlines()):
        return True
    code, out = vcs("merge-tree", "--write-tree", base, f"origin/{branch}")
    if code == 0 and out:
        tree = out.splitlines()[0]
        if vcs("rev-parse", f"{base}^{{tree}}") == (0, tree):
            return True
    try:
        gh = subprocess.run(["gh", "pr", "list", "--head", branch, "--state", "merged", "--json", "number"],
                            capture_output=True, text=True, timeout=20, cwd=str(REPO))
        if gh.returncode == 0 and json.loads(gh.stdout or "[]"):
            return True
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    return False


def main():
    on_disk = {}
    for folder in mockup_dirs():
        kind = folder.relative_to(ROOT).parts[0]
        html = folder / f"{folder.name}.html"
        if not html.exists():
            bad(f"{folder.relative_to(ROOT)}: no {folder.name}.html (folder name must equal the file stem)")
            continue
        on_disk[folder.name] = html
        readme = folder / "README.md"
        if kind == "proposals":
            pass  # owner-review proposals are frozen records (propose-first.md): no README required
        elif not readme.exists():
            bad(f"{folder.relative_to(ROOT)}: no README.md")
        elif len(readme.read_text(encoding="utf-8").splitlines()) > 40:
            bad(f"{readme.relative_to(ROOT)}: longer than 40 lines")
        check_config(html, kind)
    kit = ROOT / "_kit"
    declared = re.search(r"Mock\.COMPONENTS\s*=\s*\[(.*?)\];", (kit / "kit.js").read_text(encoding="utf-8"), re.S)
    names = set(re.findall(r"'([^']+)'", declared.group(1))) if declared else set()
    files = {p.stem for p in (kit / "components").glob("*.js")}
    for missing in sorted(names - files):
        bad(f"_kit/kit.js lists component {missing} but components/{missing}.js does not exist")
    for extra in sorted(files - names):
        bad(f"_kit/components/{extra}.js is not listed in Mock.COMPONENTS (kit.js)")
    catalog = ROOT / "catalog.json"
    if catalog.exists():
        data = json.loads(catalog.read_text(encoding="utf-8"))
        entries = data if isinstance(data, list) else data.get("items", data.get("mockups", []))
        ids = [e.get("id") for e in entries]
        for dup in {i for i in ids if ids.count(i) > 1}:
            bad(f"catalog.json: duplicate id {dup}")
        known = set(ids)
        for entry in entries:
            check_status(entry)
            check_in_flight(entry)
            if entry.get("status") == "superseded" and entry.get("supersededBy") and entry["supersededBy"] not in known:
                bad(f"catalog.json: {entry['id']} supersededBy `{entry['supersededBy']}` is not a catalogued id")
            folder = ROOT / entry.get("path", "?")
            built = entry.get("mockup")
            if built and not (ROOT / built).exists():
                bad(f"catalog.json: {entry['id']} mockup {built} does not exist")
            if not built and (folder / f"{entry['id']}.html").exists():
                bad(f"catalog.json: {entry['id']} has a mockup on disk but `mockup` is null (set it to {entry.get('path')}/{entry['id']}.html)")
            for src in entry.get("sources", []):
                if not (REPO / src).exists():
                    bad(f"catalog.json: {entry['id']} source {src} does not exist")
        for missing in sorted(n for n in on_disk if n not in known):
            bad(f"catalog.json: mockup {missing} is on disk but not listed")
        mockups = {e.get("mockup") for e in entries}
        for html in sorted(ROOT.rglob("*.html")):
            rel = html.relative_to(ROOT).as_posix()
            if rel not in mockups and rel not in UNCATALOGUED_OK and not rel.startswith("_review/"):
                bad(f"{rel}: .html file is not in catalog.json (add an entry, or delete the file)")
    print(f"mockups_check: {len(on_disk)} mockups, {len(names)} components, catalog {'present' if catalog.exists() else 'absent'}")
    for p in problems:
        print("  - " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
