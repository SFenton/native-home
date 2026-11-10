"""Table-driven bypass ratchet for the tripwire hooks in ``tools/hooks`` (``change-loop.md`` "Guard lane").

A guard that decides on command text is patched shape by shape unless its blocked and allowed shapes sit in one table from round 1.
Each ``tools/tests/guard_tables/<guard>.tsv`` row is ``command<TAB>block|allow<TAB>why[<TAB>main|agent]``; the rows replay through the
guard's real ``main`` (payload on stdin, exit 2 blocks) in a hermetic environment: temp HOME, ``cwd`` in the payload, session
variables cleared, PR lookups faked, so the test passes with no ``gh`` on PATH and no network. ``guard_tables/uncovered.baseline``
lists the hooks without a table; it may only shrink, checked against the copy at the merge base with ``origin/main``.
"""

import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
HOOKS = ROOT / "tools" / "hooks"
TABLES = Path(__file__).resolve().parent / "guard_tables"
BASELINE = TABLES / "uncovered.baseline"
BASELINE_REL = "tools/tests/guard_tables/uncovered.baseline"
HOOKS_REL = "tools/hooks"
sys.path.insert(0, str(HOOKS))

#: Hooks that decide on a tool call but are not named ``*_guard.py``.
EXTRA_GUARDS = ("no_poll", "agent_model")
MIN_ROWS = 20
#: The owner sign-off flag, built here so this source never spells it out.
FLAG = "--owner" + "-ack"
#: A PR authored by the owner in this repository: what a faked ``pr_origin`` returns.
OWN_PR = {"author": {"login": "SFenton"}, "headRepository": {"name": "native-home"}, "headRepositoryOwner": {"login": "SFenton"}}


def guard_names(names):
    """The hook names in ``names`` (file stems) that are guards: ``*_guard`` plus ``EXTRA_GUARDS``."""
    return sorted(n for n in names if n.endswith("_guard") or n in EXTRA_GUARDS)


def guards():
    """The names of every guard under ``tools/hooks``."""
    return guard_names(p.stem for p in HOOKS.glob("*.py"))


def parse_baseline(text):
    """The names in a baseline file's text; comment and blank lines skipped."""
    return {line.strip() for line in text.splitlines() if line.strip() and not line.startswith("#")}


def coverage_problems(found, tabled, uncovered, allowed):
    """What is wrong with the guard coverage, as messages.

    ``found``: guard names on disk; ``tabled``: names with a table; ``uncovered``: this checkout's baseline; ``allowed``: the names
    that may be uncovered (the baseline at the merge base). A guard with no table must be allowed, so a new guard needs its table;
    a baseline name outside ``allowed`` or one that has a table, or that no longer exists, is stale or an addition.
    """
    problems = [f"{n}: no table and not in the baseline at the merge base (add guard_tables/{n}.tsv)" for n in found if n not in tabled and n not in allowed]
    problems += [f"{n}: in uncovered.baseline but not in the merge-base copy (the list may only shrink)" for n in sorted(uncovered - allowed)]
    problems += [f"{n}: has a table, remove it from uncovered.baseline" for n in sorted(uncovered & tabled)]
    problems += [f"{n}: in uncovered.baseline but no such hook" for n in sorted(uncovered - set(found))]
    problems += [f"{n}: no table and not in this checkout's uncovered.baseline" for n in found if n not in tabled and n not in uncovered]
    return problems


def merge_base_baseline():
    """The baseline names at ``git merge-base HEAD origin/main``, or ``None`` when git, the ref or the file at that commit is missing."""
    def git(*args):
        return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True, timeout=30, check=True).stdout
    try:
        base = git("merge-base", "HEAD", "origin/main").strip()
        return parse_baseline(git("show", f"{base}:{BASELINE_REL}"))
    except (OSError, subprocess.SubprocessError):
        return None


def rows(name):
    """The ``(command, expect, why, mode)`` rows of a guard's table; comment and blank lines skipped."""
    out = []
    for line in (TABLES / f"{name}.tsv").read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        command, expect, why, *mode = line.split("\t")
        out.append((command.replace("\\n", "\n").replace("{FLAG}", FLAG), expect, why, mode[0] if mode else ""))
    return out


def replay(module, command, agent, home):
    """The exit code of the guard's real ``main`` for a Bash payload carrying ``command``, as a main or an agent session."""
    payload = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(ROOT)}
    if agent:
        payload.update({"agent_type": "coder", "agent_id": "a1"})
    env = {"PATH": os.environ.get("PATH", ""), "HOME": home, "LANG": "C"}
    with mock.patch.dict("os.environ", env, clear=True), mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), \
            mock.patch.object(sys, "stderr", io.StringIO()):
        if hasattr(module, "pr_origin"):
            with mock.patch.object(module, "pr_origin", lambda number: OWN_PR):
                return module.main([])
        return module.main([])


class GuardTableTests(unittest.TestCase):
    def test_coverage_rule(self):
        """Fails if: a new guard without a table passes by also being added to `uncovered.baseline`, a baseline name absent from the
        merge-base copy is accepted, or a tabled or vanished hook stays listed (the ratchet that only lets the list shrink)."""
        self.assertEqual(coverage_problems(["a_guard"], {"a_guard"}, set(), set()), [])
        self.assertEqual(coverage_problems(["a_guard", "b_guard"], {"a_guard"}, {"b_guard"}, {"b_guard"}), [])
        added = coverage_problems(["a_guard", "new_guard"], {"a_guard"}, {"new_guard"}, set())
        self.assertTrue(any("new_guard" in m and "merge-base" in m for m in added), added)
        bare = coverage_problems(["a_guard", "new_guard"], {"a_guard"}, set(), set())
        self.assertTrue(any("new_guard" in m and "no table" in m for m in bare), bare)
        self.assertTrue(coverage_problems(["a_guard"], {"a_guard"}, {"a_guard"}, {"a_guard"}))
        self.assertTrue(coverage_problems(["a_guard"], {"a_guard"}, {"gone_guard"}, {"gone_guard"}))

    def test_every_guard_has_a_table_or_is_in_the_baseline(self):
        """Fails if: a hook guard has neither a table of at least 20 rows nor a place in the frozen baseline, a baseline name was
        added since the merge base, or a table or baseline entry went stale."""
        tabled = {p.stem for p in TABLES.glob("*.tsv")}
        uncovered = parse_baseline(BASELINE.read_text(encoding="utf-8"))
        allowed = merge_base_baseline()
        self.assertEqual(coverage_problems(guards(), tabled, uncovered, uncovered if allowed is None else allowed), [])
        for name in tabled:
            self.assertGreaterEqual(len(rows(name)), MIN_ROWS, f"{name}: fewer than {MIN_ROWS} rows")

    def test_rows_are_well_formed_and_balanced(self):
        """Fails if: a row's verdict or mode is invalid, or a table has only one side (blocks alone cannot catch a false positive;
        allows alone cannot catch a bypass)."""
        for table in sorted(TABLES.glob("*.tsv")):
            with self.subTest(table=table.name):
                found = rows(table.stem)
                self.assertTrue({e for _, e, _, _ in found} <= {"block", "allow"})
                self.assertEqual({e for _, e, _, _ in found}, {"block", "allow"})
                self.assertTrue(all(why.strip() for _, _, why, _ in found))
                self.assertTrue({m for _, _, _, m in found} <= {"", "main", "agent"})

    def test_rows_replay_through_the_real_main(self):
        """Fails if: a row's recorded verdict differs from the guard's (exit 2 for block, 0 for allow) in a main session or an agent
        session: a bypass reopened or a false positive returned. Hermetic: it must also pass with no `gh` on PATH and no network."""
        with tempfile.TemporaryDirectory() as home:
            for table in sorted(TABLES.glob("*.tsv")):
                module = __import__(table.stem)
                for command, expect, why, mode in rows(table.stem):
                    for agent in (False, True):
                        if mode == ("main" if agent else "agent"):
                            continue
                        with self.subTest(guard=table.stem, command=command, why=why, agent=agent):
                            self.assertEqual(replay(module, command, agent, home), 2 if expect == "block" else 0)


if __name__ == "__main__":
    unittest.main()
