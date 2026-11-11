#!/usr/bin/env python3
"""Build the S+H Mockups hub: the whole mockup atlas as one multi-page Artifact.

    python3 tools/mockups_hub.py              # build into build/mockups-hub/ and print the publish plan
    python3 tools/mockups_hub.py --batches    # print the Artifact `files` lists (JSON), one per publish call
    python3 tools/mockups_hub.py --inline     # as above, but every mockup is one self-contained file (no shared kit)
    python3 tools/mockups_hub.py --mark-published   # after the Artifact publish succeeded
    python3 tools/mockups_hub.py --allow-older      # build even though the published hub came from a newer commit

Every build prints "built from <branch>@<sha7>, N pages" and records that pair in build/mockups-hub.built.json
(--mark-published copies it to build/mockups-hub.published.json, beside the old mtime stamps the Stop hook reads).
A build whose head does not contain the published hub's commit would replace a hub built from a newer commit or
another branch, so it exits 1 unless --allow-older is given.

A build writes build/mockups-hub.built; --mark-published writes build/mockups-hub.published. The Stop hook
tools/hooks/mockup_hub_guard.py blocks a session that changed mockups unless both are newer than the change.
The hub shows current surfaces first (pages, modals, components, flows, proposals awaiting the owner, kit) and puts
decided and superseded proposals in a collapsed "Why" section.

Input is `.agents/design/mockups/` (`catalog.json` plus the proposals and the kit gallery). Output is
`index.html` (the hub) and `a/<same path as in the repo>` for every mockup and the files it loads
(kit, helpers, screenshots). Copies of the HTML get a small "back to hub" pill added; repo files are never changed.
The Artifact tool takes at most 255 files per publish, so the file list comes in batches; publish `index.html`
with each batch to the same `url`. See `.agents/skills/mockup-hub/SKILL.md`. Stdlib only.
"""
import html
import json
from datetime import datetime, timezone
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOCKUPS = ROOT / ".agents/design/mockups"
TEMPLATE = Path(__file__).with_name("mockups_hub_template.html")
OUT = ROOT / "build/mockups-hub"
BATCH = 200  # well under the tool's 255 files per publish
MAX_BATCH_BYTES = 48 * 1024 * 1024  # under the tool's 64 MB per publish

KINDS = [
    ("page", "Pages", "Whole screens, as each tab and route draws them."),
    ("modal", "Modals and sheets", "Sheets, pushes inside sheets, full-screen covers and alerts."),
    ("component", "Components", "Reusable views with every variant and state: tiles, chips, headers, controls, cards."),
    ("flow", "Flows", "Launch, sign-in, navigation and offline, across several screens."),
]
SKIP_DIRS = {"_review"}
SKIP_FILES = {"catalog.json", "_review-groups.json", ".DS_Store"}

PILL = (
    '<script>document.addEventListener("DOMContentLoaded",function(){var a=document.createElement("a");'
    'a.href="%s";a.textContent="\\u2190 S+H Mockups";'
    'a.setAttribute("style","position:fixed;z-index:2147483647;right:max(12px,env(safe-area-inset-right,0px));'
    "bottom:max(12px,env(safe-area-inset-bottom,0px));padding:8px 14px;border-radius:99px;background:rgba(20,22,28,.82);"
    'color:#fff;font:600 13px -apple-system,system-ui,sans-serif;text-decoration:none;border:1px solid rgba(255,255,255,.25)");'
    "document.documentElement.appendChild(a)});</script>"
)


def humanize(slug: str) -> str:
    return slug.replace("-", " ").capitalize()


def proposal_title(page: Path) -> str:
    """The proposal's own <title> without a trailing "· proposal"; the folder name when it has none."""
    m = re.search(r"<title>(.*?)</title>", page.read_text(encoding="utf-8"), re.S | re.I)
    title = re.sub(r"\s*·\s*proposal\s*$", "", html.unescape(m.group(1)).strip(), flags=re.I) if m else ""
    return title or humanize(page.stem)


def card(it: dict, by_id: dict = None) -> str:
    sc = it.get("status", "shipped")
    note = it.get("note", "")
    if sc in ("decided", "superseded"):
        bits = [it["decision"]] if it.get("decision") else []
        if it.get("shippedIn"):
            bits.append("shipped " + it["shippedIn"])
        if it.get("supersededBy"):
            bits.append("superseded by " + (by_id or {}).get(it["supersededBy"], {}).get("title", it["supersededBy"]))
        note = (note + " " if note else "") + ("(" + "; ".join(bits) + ")" if bits else "")
    detail = it.get("presentation", "") if it["kind"] == "modal" else ""
    sum_ = note or detail
    tag = f'<span class="tag">{html.escape(sc)}</span>' if sc != "shipped" else ""
    return (
        f'<a class="card" href="a/{it["mockup"]}">{tag}<strong>{html.escape(it["title"])}</strong>'
        + (f'<span class="sum">{html.escape(sum_)}</span>' if sum_ else "")
        + f'<span class="meta">{html.escape(it["area"])} · {html.escape(it["id"])}</span></a>'
    )


def sections(cat: dict) -> tuple[str, str, int]:
    areas = cat["areas"]
    order = {a: i for i, a in enumerate(areas)}
    out, nav, total = [], [], 0
    for kind, title, blurb in KINDS:
        items = sorted((i for i in cat["items"] if i["kind"] == kind), key=lambda i: (order.get(i["area"], 99), i["title"].lower()))
        if not items:
            continue
        total += len(items)
        body = []
        for area in sorted({i["area"] for i in items}, key=lambda a: order.get(a, 99)):
            cards = "".join(card(i) for i in items if i["area"] == area)
            body.append(f'<div class="area"><h3>{html.escape(humanize(area))}</h3><div class="grid">{cards}</div></div>')
        out.append(f'<section id="{kind}"><h2>{title}</h2><p class="blurb">{blurb}</p>{"".join(body)}</section>')
        nav.append(f'<a href="#{kind}">{title}<b>{len(items)}</b></a>')

    # Proposals: those awaiting the owner are current; decided and superseded ones are history, kept only to explain why.
    by_id = {i["id"]: i for i in cat["items"]}
    listed = {i["mockup"] for i in cat["items"]}
    proposals = [i for i in cat["items"] if i["kind"] == "proposal"]
    for p in sorted(MOCKUPS.glob("proposals/*/*.html")):  # a folder the catalog does not know yet still shows, as proposed
        rel = p.relative_to(MOCKUPS).as_posix()
        if rel not in listed:
            proposals.append({"kind": "proposal", "area": "proposals", "id": p.stem, "title": proposal_title(p), "mockup": rel,
                              "status": "proposed", "note": "Owner-review proposal, not catalogued yet."})
    open_props = sorted((i for i in proposals if i.get("status", "proposed") == "proposed"), key=lambda i: i["title"].lower())
    if open_props:
        total += len(open_props)
        cards = "".join(card(i) for i in open_props)
        out.append(f'<section id="proposal"><h2>Proposals awaiting the owner</h2><p class="blurb">Options put to the owner before building; nothing is built until one is picked.</p><div class="area"><div class="grid">{cards}</div></div></section>')
        nav.append(f'<a href="#proposal">Proposals<b>{len(open_props)}</b></a>')
    kit = {"kind": "kit", "area": "kit", "id": "gallery", "title": "Component kit gallery", "mockup": "_kit/gallery.html",
           "note": "Every shared kit component, rendered."}
    total += 1
    out.append(f'<section id="kit"><h2>Kit</h2><p class="blurb">The shared building blocks behind every mockup.</p><div class="area"><div class="grid">{card(kit)}</div></div></section>')
    nav.append('<a href="#kit">Kit<b>1</b></a>')
    past = [i for i in proposals if i.get("status") in ("decided", "superseded")]
    if past:
        total += len(past)
        groups = []
        for status, label in (("decided", "Decided"), ("superseded", "Superseded")):
            rows = sorted((i for i in past if i["status"] == status), key=lambda i: i["title"].lower())
            if rows:
                cards = "".join(card(i, by_id) for i in rows)
                groups.append(f'<div class="area"><h3>{label} ({len(rows)})</h3><div class="grid">{cards}</div></div>')
        out.append(f'<section id="why"><details id="whyd"><summary>Why: decided and superseded proposals <b>{len(past)}</b></summary>'
                   f'<p class="blurb">History only, kept to explain why the app is the way it is. The current design is in the sections above, and the rule is in the doc each card names.</p>{"".join(groups)}</details></section>')
        nav.append(f'<a href="#why">Why<b>{len(past)}</b></a>')
    return "\n".join(out), "".join(nav), total


def publishable() -> list[Path]:
    return sorted(
        p for p in MOCKUPS.rglob("*")
        if p.is_file() and p.suffix != ".md" and p.name not in SKIP_FILES and not (SKIP_DIRS & set(p.relative_to(MOCKUPS).parts))
    )


def build(inline: bool) -> dict[str, Path]:
    cat = json.loads((MOCKUPS / "catalog.json").read_text(encoding="utf-8"))
    missing = [i["mockup"] for i in cat["items"] if not (MOCKUPS / i["mockup"]).is_file()]
    if missing:
        sys.exit(f"catalog.json lists missing files: {missing[:5]}")
    body, nav, total = sections(cat)
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    page = (TEMPLATE.read_text(encoding="utf-8").replace("__SECTIONS__", body).replace("__NAV__", nav)
            .replace("__COUNT__", f"{total} mockups"))
    (OUT / "index.html").write_text(page, encoding="utf-8")

    files: dict[str, Path] = {}
    for src in publishable():
        rel = src.relative_to(MOCKUPS)
        dest = OUT / "a" / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        if src.suffix == ".html":
            if inline and "_kit" in src.read_text(encoding="utf-8"):
                text = subprocess.run([sys.executable, str(ROOT / "tools/mockups_inline.py"), str(src)], check=True, capture_output=True, text=True).stdout
            else:
                text = src.read_text(encoding="utf-8")
            back = "../" * len(rel.parts) + "index.html"
            text = text.replace("</head>", PILL % back + "</head>", 1) if "</head>" in text else PILL % back + text
            if not text.lstrip()[:15].lower().startswith("<!doctype html"):
                text = "<!doctype html>\n" + text  # published as written, so a missing doctype would mean quirks mode
            dest.write_text(text, encoding="utf-8")
        elif inline and rel.parts[0] == "_kit" and src.suffix in {".js", ".css"}:
            continue  # inlined into each page
        else:
            shutil.copyfile(src, dest)
        files[f"a/{rel.as_posix()}"] = dest
    return files


def batches(files: dict[str, Path]) -> list[list[str]]:
    out, cur, size = [], [], 0
    for rel, p in files.items():
        n = p.stat().st_size
        if cur and (len(cur) >= BATCH or size + n > MAX_BATCH_BYTES):
            out.append(cur)
            cur, size = [], 0
        cur.append(rel)
        size += n
    if cur:
        out.append(cur)
    return out


def stamp(name: str) -> None:
    """Leave a marker for tools/hooks/mockup_hub_guard.py (mtime is what it compares)."""
    path = ROOT / "build" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(datetime.now(timezone.utc).isoformat() + "\n", encoding="utf-8")


def git(*args: str) -> subprocess.CompletedProcess:
    """Run git in the checkout that runs this script (never in the caller's cwd)."""
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)


def head_pair() -> dict:
    """The branch and full head commit of this checkout; branch is ``detached`` off a branch, sha is empty outside git."""
    sha = git("rev-parse", "HEAD").stdout.strip()
    branch = git("rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    return {"branch": "detached" if branch in ("", "HEAD") else branch, "sha": sha}


def read_pair(name: str) -> dict:
    """The ``{branch, sha}`` record in build/<name>, or {} when it is missing or unreadable."""
    try:
        data = json.loads((ROOT / "build" / name).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) and data.get("sha") else {}


def would_replace_newer(published: dict, head: dict) -> bool:
    """True when the published hub came from a different branch and its commit is not an ancestor of (or equal to) the head.

    The same named branch (a rebase or amend rewrote the commit) never refuses; ``detached`` names no branch.
    """
    if not published or not head.get("sha") or published["sha"] == head["sha"]:
        return False
    if published.get("branch") == head.get("branch") and head.get("branch") != "detached":
        return False
    return git("merge-base", "--is-ancestor", published["sha"], head["sha"]).returncode != 0


def label(pair: dict) -> str:
    return f"{pair.get('branch', '?')}@{str(pair.get('sha', ''))[:7]}"


def main(argv: list[str]) -> int:
    if "--mark-published" in argv:
        stamp("mockups-hub.published")  # run after the Artifact publish succeeded
        pair = read_pair("mockups-hub.built.json") or head_pair()
        (ROOT / "build" / "mockups-hub.published.json").write_text(json.dumps(pair) + "\n", encoding="utf-8")
        print(f"marked the hub as published ({label(pair)})")
        return 0
    head, published = head_pair(), read_pair("mockups-hub.published.json")
    if "--allow-older" not in argv and would_replace_newer(published, head):
        print(f"would replace a hub built from {label(published)} with {label(head)}; "
              "pass --allow-older to continue, or rebuild from a checkout that contains that commit", file=sys.stderr)
        return 1
    files = build("--inline" in argv)
    stamp("mockups-hub.built")
    (ROOT / "build" / "mockups-hub.built.json").write_text(json.dumps(head) + "\n", encoding="utf-8")
    pages = sum(1 for rel in files if rel.endswith(".html")) + 1
    print(f"built from {label(head)}, {pages} pages", file=sys.stderr if "--batches" in argv else sys.stdout)
    (ROOT / "build" / "mockups-hub.published").unlink(missing_ok=True)  # a new build is unpublished until the Artifact is updated
    groups = batches(files)
    if "--batches" in argv:
        print(json.dumps([[{"path": r} for r in g] for g in groups]))
        return 0
    total = sum(p.stat().st_size for p in files.values()) + (OUT / "index.html").stat().st_size
    print(f"built {OUT.relative_to(ROOT)}: {len(files) + 1} files, {total / 1048576:.1f} MB (limit 16 MB per file, 256 MB per version)")
    print(f"publish {len(groups)} time(s) to the same url: file_path={OUT / 'index.html'}, root={OUT}, files = batch N of `python3 tools/mockups_hub.py --batches`")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
