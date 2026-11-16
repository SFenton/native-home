#!/usr/bin/env python3
"""Apply an edit file to a publication and compile the result with the app's own compiler, entirely offline.

    draft.py apply   --source PUBLICATION --edits EDITS --out DRAFT            # edit, check the envelope, write
    draft.py compile DRAFT [--result FILE]                                      # compile with ServerUICompositionPublication
    draft.py build   --source PUBLICATION --edits EDITS --out DRAFT             # apply, then compile

The publication, the edit file and the draft are house data: they live only under the git-ignored ``build/parity-loop-draft/``
(every path is checked with ``git check-ignore`` and refused otherwise). The tool and its tests (synthetic ``demo_`` data) are in
the repository. Nothing here talks to Home Assistant or to the Studio. Stage the draft into the candidate with
``stage.py --publication DRAFT`` (or ``launch.py live --side candidate --publication DRAFT``).

**Compiler entry point.** ``compile`` runs ``swift test --filter ServerUIDraftCompileTests/compilesTheNamedPublication`` in ``apple/``
with ``PARITY_DRAFT_PUBLICATION`` and ``PARITY_DRAFT_RESULT`` set. That test (``ServerUIDraftCompileTests.swift``) calls
``ServerUICompositionPublication.decode`` and writes ``{"ok": true}`` or the compiler's first issue (code, pointer, capability), never
an authored value. The first run builds the package (minutes); later runs are incremental. Run it through ``tools/bg_run.py``.

**Edit file.** JSON: ``{"edits": [ ... ]}``. Each edit picks targets and runs ops. A pointer is RFC 6901 and is relative to the
target. Every edit must match at least one target; an ``ifEquals`` guard skips a target whose value differs (counted).

- Component targets (anywhere in ``pages`` and ``modals``): ``"id": X``, ``"ids": [..]`` or
  ``"where": {"type": T, "pageIds": [..]}`` (``pageIds`` optional).
- Page targets: ``"page": X`` or ``"page": "*"`` (every page). Component ops then do not apply.
- ``"op": "set"``, ``"path"``, ``"value"`` (adds or replaces; ``-`` appends to a list), optional ``"ifEquals"``.
- ``"op": "remove"`` (a component, or ``path`` inside it).
- ``"op": "replace"``, ``"with"``: swap the whole component for a node.
- ``"op": "wrap"``, ``"with"``: a node that takes the component as its only child (``children`` is filled in).
- ``"op": "each"``, ``"path"`` (a list inside the target), ``"set"`` ``{relative pointer: value}``: set on every element.
- Document edits: ``{"patch": [RFC 6902 operations]}`` against the whole envelope (``add``, ``remove``, ``replace``, ``test``).
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable, Dict, Iterator, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from parity_loop.common import REPO  # noqa: E402

DRAFT_DIR = REPO / "build" / "parity-loop-draft"
COMPILE_FILTER = "ServerUIDraftCompileTests/compilesTheNamedPublication"


class DraftError(Exception):
    """An edit could not apply, or the result is refused. Messages carry edit numbers and counts, never authored values."""


# MARK: - Pointers

def _parts(pointer: str) -> List[str]:
    if pointer in ("", "/"):
        return []
    if not pointer.startswith("/"):
        raise DraftError("a pointer must start with /")
    return [p.replace("~1", "/").replace("~0", "~") for p in pointer[1:].split("/")]


def _walk(root: Any, parts: List[str]) -> Tuple[Any, str]:
    node = root
    for part in parts[:-1]:
        node = node[int(part)] if isinstance(node, list) else node[part]
    return node, parts[-1]


def get_at(root: Any, pointer: str) -> Any:
    node = root
    for part in _parts(pointer):
        node = node[int(part)] if isinstance(node, list) else node[part]
    return node


def set_at(root: Any, pointer: str, value: Any) -> None:
    parts = _parts(pointer)
    if not parts:
        raise DraftError("cannot set the target itself; use replace")
    parent, last = _walk(root, parts)
    if isinstance(parent, list):
        if last == "-":
            parent.append(copy.deepcopy(value))
        else:
            parent[int(last)] = copy.deepcopy(value)
    else:
        parent[last] = copy.deepcopy(value)


def remove_at(root: Any, pointer: str) -> None:
    parent, last = _walk(root, _parts(pointer))
    if isinstance(parent, list):
        del parent[int(last)]
    else:
        del parent[last]


def json_patch(document: Any, operations: List[Dict[str, Any]]) -> None:
    """The subset of RFC 6902 the drafts need: ``add``, ``remove``, ``replace`` and ``test``, applied in place and in order."""
    for number, op in enumerate(operations):
        kind, path = op.get("op"), op.get("path", "")
        try:
            if kind == "test":
                if get_at(document, path) != op["value"]:
                    raise DraftError(f"patch {number}: test failed")
            elif kind == "add":
                parts = _parts(path)
                parent, last = _walk(document, parts)
                value = copy.deepcopy(op["value"])
                if isinstance(parent, list):
                    parent.append(value) if last == "-" else parent.insert(int(last), value)
                else:
                    parent[last] = value
            elif kind == "replace":
                get_at(document, path)
                set_at(document, path, op["value"])
            elif kind == "remove":
                remove_at(document, path)
            else:
                raise DraftError(f"patch {number}: unsupported op")
        except (KeyError, IndexError, ValueError, TypeError):
            raise DraftError(f"patch {number}: the path does not resolve") from None


# MARK: - Targets

def _components(nodes: List[Dict[str, Any]], owner: Dict[str, Any]) -> Iterator[Tuple[List[Dict[str, Any]], int, Dict[str, Any], str]]:
    """Every component with its list, index, node and page id, depth first. Safe to mutate the list the caller is given
    only through the yielded list and index, after which the walk must be restarted."""
    for index, node in enumerate(nodes):
        yield nodes, index, node, owner.get("id", "")
        yield from _components(node.get("children") or [], owner)


def _all_components(document: Dict[str, Any]) -> Iterator[Tuple[List[Dict[str, Any]], int, Dict[str, Any], str]]:
    for kind in ("pages", "modals"):
        for page in document.get(kind) or []:
            yield from _components(page.get("components") or [], page)


def find_components(document: Dict[str, Any], edit: Dict[str, Any]) -> List[Tuple[List[Dict[str, Any]], int, Dict[str, Any]]]:
    ids = set(edit["ids"]) if "ids" in edit else ({edit["id"]} if "id" in edit else None)
    where = edit.get("where") or {}
    found = []
    for nodes, index, node, page_id in _all_components(document):
        if ids is not None and node.get("id") not in ids:
            continue
        if ids is None and ("type" in where and node.get("type") != where["type"]):
            continue
        if where.get("pageIds") and page_id not in where["pageIds"]:
            continue
        found.append((nodes, index, node))
    return found


def find_pages(document: Dict[str, Any], edit: Dict[str, Any]) -> List[Dict[str, Any]]:
    pages = (document.get("pages") or [])
    return pages if edit["page"] == "*" else [p for p in pages if p.get("id") == edit["page"]]


# MARK: - Applying

def apply_edit(envelope: Dict[str, Any], edit: Dict[str, Any]) -> Dict[str, int]:
    """Apply one edit in place; return ``{"targets": n, "changed": n}``. A guard that skips a target does not count as changed."""
    if "patch" in edit:
        json_patch(envelope, edit["patch"])
        return {"targets": 1, "changed": 1}
    document = envelope["document"]
    op = edit.get("op")
    if not any(key in edit for key in ("id", "ids", "page")) and not (edit.get("where") or {}).get("type"):
        raise DraftError("an edit names no target (id, ids, page or where.type)")
    if "page" in edit:
        targets: List[Any] = find_pages(document, edit)
        entries = [(None, None, page) for page in targets]
    else:
        entries = find_components(document, edit)
    if not entries:
        raise DraftError("an edit matched no target")
    changed = 0
    # replace, wrap and remove change the lists, so apply them last-to-first within a list
    for nodes, index, node in sorted(entries, key=lambda e: -(e[1] or 0)):
        if op == "set":
            if "ifEquals" in edit:
                try:
                    if get_at(node, edit["path"]) != edit["ifEquals"]:
                        continue
                except (KeyError, IndexError, TypeError):
                    continue
            set_at(node, edit["path"], edit["value"])
        elif op == "each":
            for item in get_at(node, edit["path"]):
                for pointer, value in edit["set"].items():
                    set_at(item, pointer, value)
        elif op == "remove" and "path" in edit:
            remove_at(node, edit["path"])
        elif nodes is None:
            raise DraftError("this op does not apply to a page")
        elif op == "remove":
            del nodes[index]
        elif op == "replace":
            nodes[index] = copy.deepcopy(edit["with"])
        elif op == "wrap":
            wrapper = copy.deepcopy(edit["with"])
            wrapper["children"] = [node]
            nodes[index] = wrapper
        else:
            raise DraftError("unsupported op")
        changed += 1
    return {"targets": len(entries), "changed": changed}


def apply_edits(envelope: Dict[str, Any], edits: List[Dict[str, Any]]) -> List[Dict[str, int]]:
    """Apply every edit in order to ``envelope`` (in place); return one counts row per edit. An error names the edit's number."""
    rows = []
    for number, edit in enumerate(edits):
        try:
            rows.append(apply_edit(envelope, edit))
        except DraftError as error:
            raise DraftError(f"edit {number}: {error}") from None
        except (KeyError, IndexError, TypeError, ValueError):
            raise DraftError(f"edit {number}: the path or fields do not resolve") from None
    return rows


def check_envelope(envelope: Dict[str, Any]) -> None:
    """The envelope fields ``stage.py`` needs: an integer revision and a document with an assets list."""
    if not isinstance(envelope.get("revision"), int) or isinstance(envelope.get("revision"), bool):
        raise DraftError("the envelope has no integer revision")
    if not isinstance((envelope.get("document") or {}).get("assets"), list):
        raise DraftError("the document has no assets list")


# MARK: - Files

def require_ignored(path: Path, *, write: bool = False) -> Path:
    """Return the resolved ``path`` after refusing anything that could land house data in a tracked file.

    The path is resolved first (against the process's directory, as it is opened). A symlink at the final component is refused, a
    file that will be written must resolve under ``DRAFT_DIR``, and git must ignore the resolved path.
    """
    path = Path(path)
    if path.is_symlink():
        raise DraftError("a draft file must not be a symlink")
    resolved = path.resolve()
    if write and not resolved.is_relative_to(DRAFT_DIR.resolve()):
        raise DraftError("a draft file is written only under build/parity-loop-draft/")
    result = subprocess.run(["git", "check-ignore", "-q", str(resolved)], cwd=REPO, capture_output=True)
    if result.returncode != 0:
        raise DraftError("a draft file must live under a git-ignored folder (build/parity-loop-draft/)")
    return resolved


def apply_files(source: Path, edits: Path, out: Path, *, check_ignore: bool = True) -> List[Dict[str, int]]:
    """Read ``source`` and ``edits``, apply, check the envelope and write ``out`` (compact, sorted as the source was read)."""
    if check_ignore:
        source, edits = require_ignored(source), require_ignored(edits)
        out = require_ignored(out, write=True)
    try:
        envelope = json.loads(Path(source).read_text(encoding="utf-8"))
        edit_file = json.loads(Path(edits).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise DraftError("the source or the edit file cannot be read as JSON") from None
    if not isinstance(envelope, dict) or not isinstance(edit_file, dict) or not isinstance(edit_file.get("edits"), list):
        raise DraftError("the source is not an envelope, or the edit file has no edits list")
    rows = apply_edits(envelope, edit_file["edits"])
    check_envelope(envelope)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(envelope, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    return rows


def compile_publication(path: Path, result_file: Optional[Path] = None, timeout: float = 3000.0, *, check_ignore: bool = True) -> Dict[str, Any]:
    """Compile ``path`` with the app's compiler (``swift test`` on the draft test); return its report.

    The report is ``{"ok": true, ...}`` or ``{"ok": false, "code", "pointer", "capability"?}``: no authored values.
    """
    result_file = result_file or Path(path).with_suffix(".result.json")
    if check_ignore:
        path = require_ignored(path)
        result_file = require_ignored(result_file, write=True)
    result_file.unlink(missing_ok=True)
    env = dict(os.environ, PARITY_DRAFT_PUBLICATION=str(Path(path).resolve()), PARITY_DRAFT_RESULT=str(Path(result_file).resolve()))
    for secret in ("FENTON_HASS_TOKEN", "FENTON_HASS_SERVER"):
        env.pop(secret, None)
    try:
        run = subprocess.run(["swift", "test", "--filter", COMPILE_FILTER], cwd=REPO / "apple", env=env,
                             capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise DraftError("the compile timed out") from None
    if not result_file.is_file():
        raise DraftError(f"the compile test wrote no result (swift exit {run.returncode}); build errors are in the swift output")
    return json.loads(result_file.read_text(encoding="utf-8"))


def describe(report: Dict[str, Any]) -> str:
    if report.get("ok"):
        return "compiles: no rejection"
    extra = f" capability {report['capability']}" if report.get("capability") else ""
    return f"rejected: {report.get('code')} at {report.get('pointer')}{extra}"


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    for name in ("apply", "build"):
        p = sub.add_parser(name)
        p.add_argument("--source", type=Path, required=True)
        p.add_argument("--edits", type=Path, required=True)
        p.add_argument("--out", type=Path, required=True)
    c = sub.add_parser("compile")
    c.add_argument("publication", type=Path)
    c.add_argument("--result", type=Path)
    args = ap.parse_args(argv)
    try:
        if args.command in ("apply", "build"):
            rows = apply_files(args.source, args.edits, args.out)
            print(f"applied {len(rows)} edits; targets changed: {sum(r['changed'] for r in rows)}")
            target = args.out
        else:
            target = args.publication
        if args.command in ("build", "compile"):
            report = compile_publication(target, getattr(args, "result", None))
            print(describe(report))
            return 0 if report.get("ok") else 1
    except DraftError as error:
        print(f"draft: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
