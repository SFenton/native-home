"""``tools/mockups_hub.py``: build and publish stamps, the per-file manifest, and publishing from several branches."""

import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import mockups_hub as hub  # noqa: E402

REL = ".agents/design/mockups"


def item(slug: str, title: str = "") -> dict:
    return {"kind": "page", "area": "home", "id": slug, "title": title or slug.title(), "mockup": f"pages/{slug}/{slug}.html"}


class HubRepoCase(unittest.TestCase):
    """A throwaway repo with a mockup tree, one worktree per branch, and the hub pointed at whichever one is current."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name) / "main"
        self.root.mkdir()
        self.git(self.root, "init", "-q", "-b", "main")
        self.git(self.root, "config", "user.email", "t@example.com")
        self.git(self.root, "config", "user.name", "t")
        (self.root / REL).mkdir(parents=True)
        self.write(self.root, "catalog.json", json.dumps({"areas": ["home"], "items": [item("base")]}))
        self.write(self.root, "pages/base/base.html", "<!doctype html><title>base</title></head>")
        self.main_sha = self.commit(self.root, "one")

    # git and files
    def git(self, where, *args):
        return subprocess.run(["git", "-C", str(where), *args], capture_output=True, text=True, check=True).stdout.strip()

    def write(self, where, rel, text):
        path = where / REL / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def commit(self, where, msg):
        self.git(where, "add", "-A")
        self.git(where, "commit", "-q", "-m", msg, "--allow-empty")
        return self.git(where, "rev-parse", "HEAD")

    def branch(self, name):
        """A worktree on a new branch cut from main."""
        where = Path(self._tmp.name) / name
        self.git(self.root, "worktree", "add", "-q", "-b", name, str(where), "main")
        return where

    def add_page(self, where, slug, text=None):
        cat = json.loads((where / REL / "catalog.json").read_text())
        cat["items"].append(item(slug))
        self.write(where, "catalog.json", json.dumps(cat))
        self.write(where, f"pages/{slug}/{slug}.html", text or f"<!doctype html><title>{slug}</title></head>")
        return self.commit(where, f"add {slug}")

    # running the hub from one worktree
    @contextmanager
    def session(self, where):
        patches = [mock.patch.object(hub, "ROOT", where), mock.patch.object(hub, "MOCKUPS", where / REL),
                   mock.patch.object(hub, "OUT", where / "build/mockups-hub")]
        for p in patches:
            p.start()
        try:
            yield
        finally:
            for p in patches:
                p.stop()

    def run_main(self, where, *argv):
        out, err = io.StringIO(), io.StringIO()
        with self.session(where), redirect_stdout(out), redirect_stderr(err):
            code = hub.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def publish(self, where, *argv):
        """Build with --batches, then mark published; returns the parsed batches."""
        code, out, err = self.run_main(where, "--batches", *argv)
        self.assertEqual(code, 0, err)
        self.assertEqual(self.run_main(where, "--mark-published")[0], 0)
        return json.loads(out)

    def paths(self, batches):
        return {e["path"] for b in batches for e in b if "path" in e}

    def read(self, where, name):
        return json.loads((where / "build" / name).read_text())

    def index(self, where):
        return (where / "build/mockups-hub/index.html").read_text()


class HubStampTests(HubRepoCase):
    def test_build_writes_the_stamp_and_prints_branch_and_sha(self):
        """Fails if: the build writes no branch and head sha beside the old stamp, or prints no `built from branch@sha7, N pages` line."""
        code, out, _ = self.run_main(self.root)
        self.assertEqual(code, 0)
        built = self.read(self.root, "mockups-hub.built.json")
        self.assertEqual({k: built[k] for k in ("branch", "sha")}, {"branch": "main", "sha": self.main_sha})
        self.assertIn(f"built from main@{self.main_sha[:7]}, 2 pages", out)
        self.assertTrue((self.root / "build/mockups-hub.built").is_file(), "the old mtime stamp the Stop hook reads must stay")

    def test_batches_keeps_stdout_json(self):
        """Fails if: the provenance line lands on stdout in --batches mode and breaks the JSON."""
        code, out, err = self.run_main(self.root, "--batches")
        self.assertEqual(code, 0)
        json.loads(out)
        self.assertIn("built from main@", err)

    def test_mark_published_records_the_built_pair_and_the_files(self):
        """Fails if: --mark-published drops the pair the Stop hook reads, or records no per-file manifest."""
        self.run_main(self.root)
        code, out, _ = self.run_main(self.root, "--mark-published")
        self.assertEqual(code, 0)
        self.assertEqual(self.read(self.root, "mockups-hub.published.json"), {"branch": "main", "sha": self.main_sha})
        self.assertTrue((self.root / "build/mockups-hub.published").is_file())
        self.assertIn(self.main_sha[:7], out)
        with self.session(self.root):
            manifest = hub.read_manifest()
        self.assertEqual(list(manifest["files"]), ["a/pages/base/base.html"])
        self.assertEqual(manifest["files"]["a/pages/base/base.html"]["branch"], "main")


class HubMultiBranchTests(HubRepoCase):
    def test_disjoint_mockups_from_two_branches_both_publish(self):
        """Fails if: a branch is refused because another branch published first, or the index drops the other branch's mockup."""
        a, b = self.branch("lane-a"), self.branch("lane-b")
        self.add_page(a, "alpha")
        self.add_page(b, "beta")
        first = self.publish(a)
        self.assertEqual(self.paths(first), {"a/pages/alpha/alpha.html", "a/pages/base/base.html"})
        second = self.publish(b)  # neither refused
        self.assertEqual(self.paths(second), {"a/pages/beta/beta.html"}, "only this branch's changed files, never the index")
        self.assertIn("pages/alpha/alpha.html", self.index(b))
        self.assertIn("pages/beta/beta.html", self.index(b))
        self.assertIn("pages/base/base.html", self.index(b))
        third = self.publish(a)  # and the first branch again keeps the second's page
        self.assertEqual(self.paths(third), set())
        self.assertIn("pages/beta/beta.html", self.index(a))

    def test_unmerged_proposal_from_another_branch_is_not_dropped(self):
        """Fails if: an uncatalogued proposal another session published disappears from the index of a later build."""
        a, b = self.branch("lane-a"), self.branch("lane-b")
        self.write(a, "proposals/siri/siri.html", "<!doctype html><title>Siri context · proposal</title></head>")
        self.commit(a, "proposal")
        self.publish(a)
        self.assertIn("Siri context", self.index(a))
        self.publish(b)
        self.assertIn("Siri context", self.index(b))
        self.assertIn("proposals/siri/siri.html", self.index(b))

    def test_overwriting_the_other_branchs_changed_file_refuses(self):
        """Fails if: a build that would overwrite a published file the other branch changed exits 0, or touches the stamps."""
        a, b = self.branch("lane-a"), self.branch("lane-b")
        self.write(a, "pages/base/base.html", "<!doctype html><title>from a</title></head>")
        self.commit(a, "a edits base")
        self.write(b, "pages/base/base.html", "<!doctype html><title>from b</title></head>")
        self.commit(b, "b edits base")
        self.publish(a)
        code, _, err = self.run_main(b, "--batches")
        self.assertEqual(code, 1)
        self.assertIn("a/pages/base/base.html", err)
        self.assertIn("lane-a@", err)
        self.assertFalse((b / "build/mockups-hub.built.json").exists())
        self.assertEqual(self.run_main(b, "--allow-older")[0], 0)

    def test_deleting_the_other_branchs_changed_file_refuses(self):
        """Fails if: a build that would delete a published file the other branch changed exits 0."""
        a, b = self.branch("lane-a"), self.branch("lane-b")
        self.write(a, "pages/base/base.html", "<!doctype html><title>from a</title></head>")
        self.commit(a, "a edits base")
        (b / REL / "pages/base/base.html").unlink()
        cat = json.loads((b / REL / "catalog.json").read_text())
        cat["items"] = []
        self.write(b, "catalog.json", json.dumps(cat))
        self.commit(b, "b deletes base")
        self.publish(a)
        self.assertEqual(self.run_main(b)[0], 1)

    def test_a_file_only_the_other_branch_changed_is_kept_not_overwritten(self):
        """Fails if: a build that left a file alone republishes its stale copy over the other branch's change."""
        a, b = self.branch("lane-a"), self.branch("lane-b")
        self.write(a, "pages/base/base.html", "<!doctype html><title>from a</title></head>")
        self.commit(a, "a edits base")
        self.add_page(b, "beta")
        self.publish(a)
        batches = self.publish(b)
        self.assertEqual(self.paths(batches), {"a/pages/beta/beta.html"})

    def test_deleting_an_untouched_published_file_removes_it(self):
        """Fails if: a deletion of a file nobody else changed is refused or never listed for removal."""
        a = self.branch("lane-a")
        self.publish(self.root)
        (a / REL / "pages/base/base.html").unlink()
        self.write(a, "catalog.json", json.dumps({"areas": ["home"], "items": []}))
        self.commit(a, "drop base")
        batches = self.publish(a)
        self.assertIn([{"a/pages/base/base.html": None}], batches)

    def test_a_descendant_branch_changing_a_published_file_publishes_it(self):
        """Fails if: a later commit on top of the published one is refused, or its edit is left out of the batches."""
        self.publish(self.root)
        self.write(self.root, "pages/base/base.html", "<!doctype html><title>two</title></head>")
        self.commit(self.root, "edit")
        self.assertEqual(self.paths(self.publish(self.root)), {"a/pages/base/base.html"})


if __name__ == "__main__":
    unittest.main()
