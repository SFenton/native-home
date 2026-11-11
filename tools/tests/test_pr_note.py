"""``tools/pr_note.py`` against a fake ``gh`` that keeps a PR (body and comments) in a JSON file."""

import ast
import io
import json
import os
import re
import stat
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import pr_note  # noqa: E402

FAKE_GH = r'''#!/usr/bin/env python3
import json, os, sys
state_path = os.environ["FAKE_STATE"]
st = json.load(open(state_path))
args = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps(args) + "\n")
if st.get("fail"):
    sys.stderr.write("HTTP 500 boom"); sys.exit(1)
def save(): json.dump(st, open(state_path, "w"))
if args[:2] == ["pr", "view"]:
    if not st.get("pr"):
        sys.stderr.write("no pull requests found for branch"); sys.exit(1)
    if "number" in args[-1]: print(json.dumps({"number": st["pr"]}))
    else: print(json.dumps({"body": st["body"]}))
elif args[:2] == ["pr", "list"]:
    print(json.dumps([{"number": st["branches"][args[3]]}] if args[3] in st.get("branches", {}) else []))
elif args[:2] == ["pr", "edit"]:
    st["body"] = sys.stdin.read(); save()
elif args[:2] == ["pr", "comment"]:
    text = sys.stdin.read()
    for i, a in enumerate(args):
        if a == "--attach":
            path = args[i + 1].split("#")[0]
            text = text.replace(path, "https://github.com/user-attachments/assets/x")
    st["comments"].append({"id": len(st["comments"]) + 1, "body": text, "html_url": "https://example.test/pull/7#issuecomment-%d" % (len(st["comments"]) + 1)}); save()
elif args[:2] == ["api", "user"]:
    print("SFenton")
elif args[0] == "api" and "DELETE" in args:
    cid = int(args[3].rsplit("/", 1)[1])
    st["comments"] = [c for c in st["comments"] if c["id"] != cid]; save()
elif args[0] == "api" and "PATCH" in args:
    cid = int(args[3].rsplit("/", 1)[1])
    for c in st["comments"]:
        if c["id"] == cid: c["body"] = json.loads(sys.stdin.read())["body"]
    save()
elif args[0] == "api":
    if st.get("slug") and st["slug"] not in args[1]: sys.exit(0)  # a renamed repository lists nothing
    for c in st["comments"]: print(json.dumps(c))
'''

REVIEW = "<!-- review:start -->\n### Review: pass (round 2)\n- a *b*  \tx\n<!-- review:end -->"


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        tmp = Path(self.tmp.name)
        fake = tmp / "bin"
        fake.mkdir()
        gh = fake / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(gh.stat().st_mode | stat.S_IEXEC)
        self.state = tmp / "state.json"
        self.log = tmp / "log"
        self.set_state(pr=7, body="", comments=[])
        # a fixture picture other test files write here counts as demo data (the manifest rule)
        (tmp / "manifest.json").write_text(json.dumps({"media": [{"path": "pic.png", "source": "demo"}]}))
        self.denylist = tmp / "denylist.txt"
        self.denylist.write_text("zzhouseterm\n")
        self.denylist.chmod(0o600)
        env = {"PATH": f"{fake}:{os.environ['PATH']}", "FAKE_STATE": str(self.state), "FAKE_LOG": str(self.log),
               "SH_PR_NOTES_DIR": str(tmp / "notes"), "HOUSE_SCAN_DENYLIST": str(self.denylist)}
        patcher = mock.patch.dict(os.environ, env)
        patcher.start()
        self.addCleanup(patcher.stop)
        for target, value in (("NOTES_DIR", tmp / "notes"), ("ROOT", tmp)):
            p = mock.patch.object(pr_note, target, value)
            p.start()
            self.addCleanup(p.stop)

    def set_state(self, **kw):
        cur = json.loads(self.state.read_text()) if self.state.exists() else {}
        cur.update(kw)
        self.state.write_text(json.dumps(cur))

    def get(self):
        return json.loads(self.state.read_text())

    def atlas_picture(self, name="a.png", data=b"x"):
        """A picture under the (temporary) checkout's mockup atlas folder, the one place any picture may come from without a manifest."""
        pic = Path(self.tmp.name) / ".agents" / "design" / "mockups" / name
        pic.parent.mkdir(parents=True, exist_ok=True)
        pic.write_bytes(data)
        return pic

    def body_file(self, text):
        f = Path(self.tmp.name) / "body.md"
        f.write_text(text)
        return str(f)

    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = pr_note.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def post(self, kind, text, rnd="1", *extra, task="T-x"):
        return self.run_cli("post", kind, "--task", task, "--round", rnd, "--body-file", self.body_file(text), *extra)


class CommentTests(Base):
    def test_new_then_unchanged_then_edited(self):
        self.assertIn("posted", self.post("verdict", "**Designer** (agent) · pass\n\nLooks right.")[1])
        self.assertEqual(len(self.get()["comments"]), 1)
        self.assertIn("<!-- sh:verdict:T-x:1 -->", self.get()["comments"][0]["body"])
        self.assertIn("unchanged", self.post("verdict", "**Designer** (agent) · pass\n\nLooks right.")[1])
        self.assertEqual(len(self.get()["comments"]), 1)
        self.assertIn("edited", self.post("verdict", "**Designer** (agent) · changes\n\nNo.")[1])
        comments = self.get()["comments"]
        self.assertEqual(len(comments), 1)
        self.assertRegex(comments[0]["body"].splitlines()[0], r"^#### Step 1 · Designer · round 1 · \d\d:\d\dZ · updated \d\d:\d\dZ$")

    def test_new_round_is_a_new_comment(self):
        self.post("verdict", "**Designer** (agent) · pass", "1")
        self.post("verdict", "**Designer** (agent) · pass", "2")
        self.assertEqual(len(self.get()["comments"]), 2)

    def test_one_evidence_comment_per_class_per_round(self):
        for cls in ("iphone", "duo", "ipad"):
            self.post("evidence", f"**Verifier** (agent) · {cls} · round 1", "1", "--class", cls)
        self.post("evidence", "**Verifier** (agent) · duo · round 1 again", "1", "--class", "duo")
        self.post("evidence", "**Verifier** (agent) · duo · round 2", "2", "--class", "duo")
        bodies = [c["body"] for c in self.get()["comments"]]
        self.assertEqual(len(bodies), 4)
        for tag in ("iphone:1", "duo:1", "ipad:1", "duo:2"):
            self.assertEqual(sum(f"<!-- sh:evidence:T-x:{tag} -->" in b for b in bodies), 1, tag)

    def test_evidence_needs_a_class(self):
        code, _out, err = self.post("evidence", "x")
        self.assertEqual(code, 0)
        self.assertIn("needs --class", err)
        self.assertEqual(self.get()["comments"], [])

    def test_renderer_marker_is_replaced_not_doubled(self):
        self.post("evidence", "**V** · duo\n\ntext\n\n<!-- sh:evidence:T-x:duo:1 -->", "1", "--class", "duo")
        self.assertEqual(self.get()["comments"][0]["body"].count("sh:evidence:T-x:duo:1"), 1)

    def test_resolve_marks_handoff(self):
        self.post("handoff", "**Orchestrator** · waiting on you")
        self.assertIn("resolved", self.run_cli("resolve", "--task", "T-x", "--round", "1", "--text", "You answered")[1])
        self.assertTrue(self.get()["comments"][0]["body"].startswith("**Resolved:** You answered"))
        self.assertIn("unchanged", self.run_cli("resolve", "--task", "T-x", "--round", "1", "--text", "You answered")[1])

    def test_secrets_are_redacted(self):
        self.post("owner", "**Orchestrator** · token=abcdefabcdefabcdefabcdefabcdefabcdef12 done")
        self.assertNotIn("abcdefabcdef", self.get()["comments"][0]["body"])

    def test_local_media_is_attached_and_remembered(self):
        pic = self.atlas_picture()
        self.post("pick", f"**Designer** · pick\n\n![A]({pic})")
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        comment = next(c for c in calls if c[:2] == ["pr", "comment"])
        self.assertIn("--attach", comment)
        self.assertIn("user-attachments", self.get()["comments"][0]["body"])
        self.post("pick", f"**Designer** · pick changed\n\n![A]({pic})")
        self.assertIn("user-attachments", self.get()["comments"][0]["body"])


class QueueTests(Base):
    def test_queue_then_flush_in_order_keeps_time(self):
        self.set_state(pr=None)
        self.assertIn("queued", self.post("pick", "**Designer** · pick", "1")[1])
        self.post("verdict", "**Designer** · pass", "1")
        self.post("evidence", "**Verifier** · duo", "1", "--class", "duo")
        queue = sorted((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json"))
        self.assertEqual([q.name.split("-")[1] for q in queue], ["pick", "verdict", "evidence"])
        self.set_state(pr=7)
        self.assertIn("flushed 3", self.run_cli("flush", "--task", "T-x")[1])
        bodies = [c["body"] for c in self.get()["comments"]]
        self.assertEqual(["sh:pick", "sh:verdict", "sh:evidence"], [re.search(r"<!-- (sh:\w+)", b).group(1) for b in bodies])
        self.assertRegex(bodies[0].splitlines()[0], r"happened \d\d:\d\dZ, posted when the PR opened")
        self.assertEqual(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json")), [])

    def test_failed_post_is_queued_and_exits_zero(self):
        self.set_state(fail=True)
        code, _out, err = self.post("verdict", "**D** · pass")
        self.assertEqual(code, 0)
        self.assertEqual(len(err.strip().splitlines()), 1)
        self.assertEqual(len(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json"))), 1)


class BlockTests(Base):
    BODY = "intro\n<!-- sh-status:start -->\nold\n<!-- sh-status:end -->\nmid\n<!-- sh-devices:start -->\nold\n<!-- sh-devices:end -->\n" + REVIEW + "\ntail\n"

    def test_status_and_devices_leave_everything_else_identical(self):
        self.set_state(body=self.BODY)
        self.assertIn("updated", self.run_cli("status", "--task", "T", "--line", "**Status:** Review pass")[1])
        self.run_cli("devices", "--task", "T", "--file", self.body_file("| Device | Result |\n|---|---|\n| Duo | Unchanged |"))
        body = self.get()["body"]
        self.assertIn("**Status:** Review pass", body)
        self.assertIn("| Duo | Unchanged |", body)
        self.assertEqual(body[body.index("<!-- review:start -->"):body.index("<!-- review:end -->")],
                         REVIEW[:REVIEW.index("<!-- review:end -->")])
        self.assertTrue(body.startswith("intro\n") and body.endswith("tail\n") and "\nmid\n" in body)
        self.assertNotIn("old", body)

    def test_same_line_is_a_no_op(self):
        self.set_state(body=self.BODY)
        self.run_cli("status", "--task", "T", "--line", "same")
        self.assertIn("unchanged", self.run_cli("status", "--task", "T", "--line", "same")[1])

    def test_missing_markers_change_nothing(self):
        self.set_state(body="plain\n" + REVIEW)
        self.assertIn("no markers", self.run_cli("status", "--task", "T", "--line", "x")[1])
        self.assertEqual(self.get()["body"], "plain\n" + REVIEW)

    def test_gh_error_warns_and_exits_zero(self):
        self.set_state(body=self.BODY, fail=True)
        code, out, err = self.run_cli("status", "--task", "T", "--line", "x")
        self.assertEqual((code, out), (0, ""))
        self.assertIn("warning", err)

    def test_timeout_warns_and_exits_zero(self):
        import subprocess
        with mock.patch.object(pr_note.subprocess, "run", side_effect=subprocess.TimeoutExpired("gh", 20)):
            code, _out, err = self.run_cli("status", "--task", "T", "--line", "x", "--pr", "7")
        self.assertEqual(code, 0)
        self.assertIn("timed out", err)


class SourceTests(unittest.TestCase):
    """The helper only writes issue comments and the PR body: no merge, ready, label, approval or other endpoint."""

    def constants(self):
        tree = ast.parse((TOOLS / "pr_note.py").read_text())
        docstrings = {id(n.body[0].value) for n in ast.walk(tree)
                      if isinstance(n, (ast.Module, ast.FunctionDef, ast.ClassDef)) and n.body
                      and isinstance(n.body[0], ast.Expr) and isinstance(getattr(n.body[0], "value", None), ast.Constant)}
        return [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)
                and id(n) not in docstrings]

    def test_no_forbidden_gh_verbs(self):
        for text in self.constants():
            if text == "DELETE":  # only the old copy of a comment after a change of author, see AsRoleTests in test_gh_app_token.py
                continue
            self.assertIsNone(re.search(r"merge|ready|label|approv|--edit-last|pulls/|/merges|delete|close", text, re.I), text)

    def test_api_endpoints_are_issue_comments_only(self):
        endpoints = [c for c in self.constants() if c.startswith("repos/")]
        self.assertTrue(endpoints)
        for e in endpoints:
            self.assertRegex(e, r"^repos/\{(owner\}/\{repo|slug)\}/issues/(\{pr\}/comments|comments/(\{id\})?)?$")

    def test_only_pr_subcommands_view_edit_comment(self):
        source = (TOOLS / "pr_note.py").read_text()
        verbs = set(re.findall(r'gh\(\["pr", "(\w+)"', source))
        self.assertEqual(verbs, {"view", "edit", "comment", "list"})


class AgentLoginIdentityTests(Base):
    """With an agent login configured ``gh`` is the agent: the owner stays the constant SFenton and both count as plain-``gh`` writers."""

    def setUp(self):
        super().setUp()
        pr_note._OWNER_LOGIN.clear()
        self.addCleanup(pr_note._OWNER_LOGIN.clear)

    def configure(self, login):
        """Write ``agent_login`` into the (temporary) ROOT's pinned config, where pr_note reads it."""
        config = pr_note.ROOT / "tools" / "triage" / "config.json"
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text(json.dumps({"agent_login": login}))

    def test_empty_agent_login_reads_the_owner_from_gh_as_before(self):
        """Fails if: an unset agent_login changes owner_login (it must still be gh's own login) or adds a second writer, or a process
        setting names a writer the config does not."""
        self.configure("")
        with mock.patch.dict(os.environ, {"FENTON_AGENT_LOGIN": "mallory"}):
            self.assertEqual(pr_note.owner_login(), "SFenton")
            self.assertEqual(pr_note.gh_logins(), {"SFenton"})
            self.assertFalse(pr_note.Identity().mine({"user": {"login": "mallory"}}))
            self.assertFalse(pr_note.Identity().mine({"user": {"login": "sh-agent"}}))

    def test_agent_login_keeps_the_owner_constant_and_both_logins_write_as_gh(self):
        """Fails if: owner_login asks gh (which now answers with the agent) so @SFenton handoffs go to the agent, or the agent's own
        comments are no longer editable, or a third login's comment is."""
        self.configure("sh-agent")
        with mock.patch.object(pr_note, "gh", side_effect=AssertionError("gh api user must not be asked")):
            self.assertEqual(pr_note.owner_login(), "SFenton")
        self.assertEqual(pr_note.gh_logins(), {"SFenton", "sh-agent"})
        self.assertEqual(pr_note.MENTION, "@SFenton")
        identity = pr_note.Identity()
        self.assertTrue(identity.mine({"user": {"login": "sh-agent"}}))
        self.assertTrue(identity.mine({"user": {"login": "SFenton"}}))
        self.assertFalse(identity.mine({"user": {"login": "mallory"}}))


class InitAndQueueIdentityTests(Base):
    """``init`` makes the body follow the template; queues are keyed by task and never go stale."""

    def queue_files(self, task="T-x"):
        return sorted((pr_note.NOTES_DIR / task / "queue").glob("*.json"))

    def test_init_appends_missing_blocks_only_keeps_review_and_flushes(self):
        """Fails if: ``init`` changes text outside the marker blocks, drops or duplicates the review block, omits a missing
        ``sh-devices`` / ``sh-status`` / ``sh-timeline`` block, does not flush the queue, or a second ``init`` rewrites the body."""
        self.set_state(pr=None)
        self.post("pick", "**Designer** · pick")
        self.set_state(pr=7, body="Old text\n" + REVIEW + "\ntail")
        self.assertIn("body updated, flushed 1", self.run_cli("init", "--task", "T-x")[1])
        body = self.get()["body"]
        self.assertTrue(body.startswith("Old text\n"))
        self.assertIn("Old text\n" + REVIEW + "\ntail", body)
        self.assertEqual(body.count("<!-- review:start -->"), 1)
        for name in ("sh-devices", "sh-status", "sh-timeline"):
            self.assertIn(f"<!-- {name}:start -->", body)
        self.assertEqual(len(self.get()["comments"]), 1)
        self.assertIn("body kept", self.run_cli("init", "--task", "T-x")[1])

    def test_post_flushes_the_task_queue_first(self):
        self.set_state(pr=None)
        self.post("pick", "**Designer** · pick")
        self.set_state(pr=7)
        self.post("verdict", "**Designer** · pass")
        kinds = [re.search(r"<!-- sh:(\w+)", c["body"]).group(1) for c in self.get()["comments"]]
        self.assertEqual(kinds, ["pick", "verdict"])

    def test_stale_queued_note_never_overwrites_a_newer_comment(self):
        self.set_state(fail=True)
        self.post("verdict", "**D** · old")
        self.set_state(fail=False)
        self.post("verdict", "**D** · new")
        self.assertEqual(self.queue_files(), [])
        self.run_cli("flush", "--task", "T-x")
        self.assertIn("new", self.get()["comments"][0]["body"])

    def test_queue_is_per_task(self):
        self.set_state(pr=None)
        self.post("pick", "a", "1", task="T-a")
        self.post("pick", "b", "1", task="T-b")
        self.set_state(pr=7)
        self.run_cli("flush", "--task", "T-a")
        self.assertEqual(len(self.get()["comments"]), 1)
        self.assertTrue(self.queue_files("T-b"))

    def test_partial_flush_keeps_unique_ordered_names(self):
        self.set_state(pr=None)
        for r in ("1", "2", "3"):
            self.post("verdict", f"v{r}", r)
        self.queue_files()[0].unlink()
        self.post("verdict", "v4", "4")
        names = [p.name for p in self.queue_files()]
        self.assertEqual(len(set(names)), 3)
        self.assertEqual([n.rsplit("-", 1)[1] for n in names], ["2.json", "3.json", "4.json"])

    def test_identical_repost_with_media_is_a_no_op(self):
        pic = self.atlas_picture()
        self.post("pick", f"**D** · pick\n\n![A]({pic})")
        self.assertIn("unchanged", self.post("pick", f"**D** · pick\n\n![A]({pic})")[1])

    def test_bad_task_is_refused_and_nothing_is_written(self):
        with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
            self.post("pick", "x", task="../..")

    def test_unexpected_error_still_exits_zero(self):
        self.set_state(pr=None)
        self.post("pick", "x")
        for f in self.queue_files():
            f.write_text("{}")
        self.set_state(pr=7)
        code, _out, err = self.run_cli("flush", "--task", "T-x")
        self.assertEqual(code, 0)
        self.assertIn("warning", err)

    def test_no_redact_means_no_post(self):
        with mock.patch.object(pr_note, "_redact", None):
            code, _out, err = self.post("pick", "x")
        self.assertEqual(code, 0)
        self.assertIn("redact", err)
        self.assertEqual(self.get()["comments"], [])
        self.assertEqual(len(self.queue_files()), 1)


class RoleKindTests(Base):
    """The role kinds, their header, step numbers and where the PR is looked up."""

    def comment_lines(self, index=0):
        return self.get()["comments"][index]["body"].splitlines()

    def test_each_new_kind_posts_with_its_header_and_marker(self):
        """Fails if: research, build, review or retro is refused, lacks the marker for its kind, or starts with anything but
        ``#### Step N · <Role> · round R · HH:MMZ`` on its own line."""
        for rnd, (kind, role) in enumerate((("research", "Researcher"), ("build", "Coder"), ("review", "Reviewer"),
                                            ("retro", "Steward")), start=1):
            self.assertIn("posted", self.post(kind, f"{role} did the work.", str(rnd))[1])
            body = self.get()["comments"][-1]["body"]
            self.assertRegex(body.splitlines()[0], rf"^#### Step {rnd} · {role} · round {rnd} · \d\d:\d\dZ$")
            self.assertEqual(body.splitlines()[1], "")
            self.assertTrue(body.rstrip().endswith(f"<!-- sh:{kind}:T-x:{rnd} -->"))

    def test_as_names_the_role_and_head_is_shortened(self):
        """Fails if: ``--as`` does not set the role in the header, or ``--head`` is not shown as its first 7 characters."""
        with mock.patch.dict(os.environ, {"FENTON_HASS_APPS_DIR": str(Path(self.tmp.name) / "no-apps")}):  # no key: the owner login posts
            _code, _out, err = self.post("build", "Done.", "2", "--as", "coder", "--head", "8afc84d1234567")
        self.assertIn("no app identity for coder", err)
        self.assertRegex(self.comment_lines()[0], r"^#### Step 1 · Coder · round 2 · head 8afc84d · \d\d:\d\dZ$")

    def test_header_is_its_own_line_and_updated_is_appended(self):
        """Fails if: the header shares a line with a body that starts with ``**Role**``, the blank line or the body is lost, or an
        edit loses its step number."""
        self.post("pick", "**Designer** (agent) · pick\n\nBody.")
        self.post("pick", "**Designer** (agent) · pick 2\n\nBody.")
        lines = self.comment_lines()
        self.assertRegex(lines[0], r"^#### Step 1 · Designer · round 1 · \d\d:\d\dZ · updated \d\d:\d\dZ$")
        self.assertEqual(lines[1:3], ["", "**Designer** (agent) · pick 2"])

    def test_step_numbers_count_distinct_markers_and_an_edit_keeps_its_number(self):
        """Fails if: steps do not count up by distinct marker, a second post of one marker takes a new number, ``--step`` is
        ignored, or a queued note is not counted."""
        self.post("research", "One.", "1")
        self.post("build", "Two.", "1")
        self.post("build", "Two, changed.", "1")
        self.post("review", "Nine.", "1", "--step", "9")
        steps = [int(re.match(r"#### Step (\d+)", c["body"]).group(1)) for c in self.get()["comments"]]
        self.assertEqual(steps, [1, 2, 9])
        self.set_state(pr=None, comments=[])
        self.post("retro", "Q one.", "1", task="T-q")
        self.post("retro", "Q two.", "2", task="T-q")
        self.set_state(pr=7)
        self.run_cli("flush", "--task", "T-q")
        steps = [int(re.match(r"#### Step (\d+)", c["body"]).group(1)) for c in self.get()["comments"]]
        self.assertEqual(steps, [1, 2])

    def test_pr_found_by_branch_from_another_directory(self):
        """Fails if: ``--branch`` is ignored (the note would queue because the current branch has no PR), or it is looked up
        when ``--pr`` is given."""
        self.set_state(pr=None, branches={"agents/x": 7})
        self.assertIn("posted", self.run_cli("post", "build", "--task", "T-x", "--round", "1", "--branch", "agents/x",
                                             "--body-file", self.body_file("Built."))[1])
        self.assertEqual(len(self.get()["comments"]), 1)
        self.log.write_text("")
        self.run_cli("post", "build", "--task", "T-x", "--round", "2", "--pr", "7", "--branch", "agents/x",
                     "--body-file", self.body_file("Built again."))
        self.assertNotIn('"list"', self.log.read_text())

    def test_current_branch_beats_the_ledger_and_two_open_ledger_prs_refuse(self):
        """Fails if: the ledger's first branch (another lane's PR) wins over the current branch's own PR, or a ledger with two
        open PRs and no current-branch PR picks the first instead of queueing with a message naming both."""
        ledger = Path(self.tmp.name) / "tasks"
        ledger.mkdir()
        (ledger / "T-x.json").write_text(json.dumps({"branches": ["agents/sibling", "agents/mine"]}))
        self.set_state(pr=7, branches={"agents/sibling": 70, "agents/mine": 7})
        self.assertEqual(pr_note.find_pr(None, None, "T-x", str(ledger)), 7)
        self.assertEqual(pr_note.find_pr(None, "agents/sibling", "T-x", str(ledger)), 70)
        self.set_state(pr=None)
        with self.assertRaises(pr_note.NoteError) as ctx:
            pr_note.find_pr(None, None, "T-x", str(ledger))
        self.assertIn("#7", str(ctx.exception))
        self.assertIn("#70", str(ctx.exception))
        code, _out, err = self.run_cli("post", "build", "--task", "T-x", "--round", "1", "--ledger-dir", str(ledger),
                                       "--body-file", self.body_file("Built."))
        self.assertEqual(code, 0)
        self.assertIn("pass --pr or --branch", err)
        self.assertEqual(len(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json"))), 1)
        self.assertEqual(self.get()["comments"], [])

    def test_head_must_be_7_to_40_hex_characters(self):
        """Fails if: ``--head`` accepts text that is not a commit id, or refuses a full 40-character sha."""
        for bad in ("abc", "not-a-sha!", "g" * 8, "a" * 41):
            with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
                self.post("build", "x", "1", "--head", bad)
        self.assertIn("posted", self.post("build", "x", "1", "--head", "a" * 40)[1])

    def test_pr_found_by_the_task_ledger(self):
        """Fails if: the ledger's ``branches`` are not tried, or an unreadable ledger breaks the run instead of falling back."""
        ledger = Path(self.tmp.name) / "tasks"
        ledger.mkdir()
        (ledger / "T-x.json").write_text(json.dumps({"branches": ["agents/y", "agents/x"]}))
        self.set_state(pr=None, branches={"agents/x": 7})
        self.assertIn("posted", self.run_cli("post", "research", "--task", "T-x", "--round", "1", "--ledger-dir", str(ledger),
                                             "--body-file", self.body_file("Found."))[1])
        (ledger / "T-x.json").write_text("not json")
        self.assertEqual(pr_note.ledger_branches("T-x", str(ledger)), [])


class SharedQueueTests(Base):
    """The queue lives in one shared folder; the old per-checkout queue is drained into it."""

    def entry(self, folder, stamp, kind, body):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{stamp:020d}-{kind}-all-1.json").write_text(json.dumps(
            {"kind": kind, "class": None, "round": 1, "body": body, "time": "11:32Z", "branch": "b", "as": None}))

    def test_queue_goes_to_the_env_folder_and_legacy_is_drained_in_original_order(self):
        """Fails if: ``SH_PR_NOTES_DIR`` is ignored, the legacy queue is left behind, or the notes post in any order but their
        original one."""
        other = Path(self.tmp.name) / "elsewhere"
        legacy = pr_note.ROOT / "build" / "pr-notes" / "T-x" / "queue"
        with mock.patch.dict(os.environ, {"SH_PR_NOTES_DIR": str(other)}):
            self.set_state(pr=None)
            self.post("pick", "Mine.", "5")
            self.assertEqual(len(list((other / "T-x" / "queue").glob("*.json"))), 1)
            self.entry(legacy, 100, "research", "First.")
            self.entry(legacy, 300, "retro", "Third.")
            self.entry(other / "T-x" / "queue", 200, "build", "Second.")
            self.set_state(pr=7)
            self.assertIn("flushed 4", self.run_cli("flush", "--task", "T-x")[1])
        kinds = [re.search(r"<!-- sh:(\w+)", c["body"]).group(1) for c in self.get()["comments"]]
        self.assertEqual(kinds, ["research", "build", "retro", "pick"])
        self.assertEqual(list(legacy.glob("*.json")), [])
        self.assertRegex(self.get()["comments"][0]["body"].splitlines()[0], r"happened 11:32Z, posted when the PR opened")

    def test_init_and_post_drain_the_legacy_queue_too(self):
        """Fails if: ``init`` or ``post`` skips the legacy queue."""
        legacy = pr_note.ROOT / "build" / "pr-notes" / "T-x" / "queue"
        self.entry(legacy, 100, "research", "Old.")
        self.assertIn("flushed 1", self.run_cli("init", "--task", "T-x")[1])
        self.entry(legacy, 200, "retro", "Old two.")
        self.post("build", "New.")
        kinds = [re.search(r"<!-- sh:(\w+)", c["body"]).group(1) for c in self.get()["comments"]]
        self.assertEqual(kinds, ["research", "retro", "build"])


class GateTests(Base):
    """House data never goes out; pictures follow the demo rule."""

    def test_denylist_hit_refuses_with_exit_1_and_prints_no_term(self):
        """Fails if: a body with a listed term is posted or queued, the exit code is not 1, or the term (or any line of the body)
        appears in the output."""
        code, out, err = self.post("build", "The panel at zzhouseterm is done. zzhouseterm again.")
        self.assertEqual(code, 1)
        self.assertNotIn("zzhouseterm", out + err)
        self.assertIn("2 house-denylist hit(s) in body file body.md", err)
        self.assertEqual(self.get()["comments"], [])
        self.assertFalse((pr_note.NOTES_DIR / "T-x" / "queue").exists() and list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json")))
        self.set_state(body="x<!-- sh-status:start -->\n<!-- sh-status:end -->")
        code, out, err = self.run_cli("status", "--task", "T-x", "--line", "zzhouseterm is up")
        self.assertEqual(code, 1)
        self.assertNotIn("zzhouseterm", out + err)
        self.assertNotIn("zzhouseterm", self.get()["body"])

    def test_queued_note_is_gated_when_it_is_flushed(self):
        """Fails if: a note that reached the queue by another route (the old queue) goes out without the denylist."""
        legacy = pr_note.ROOT / "build" / "pr-notes" / "T-x" / "queue"
        legacy.mkdir(parents=True)
        (legacy / f"{100:020d}-pick-all-1.json").write_text(json.dumps(
            {"kind": "pick", "class": None, "round": 1, "body": "zzhouseterm", "time": "11:32Z", "branch": "b", "as": None}))
        code, out, err = self.run_cli("flush", "--task", "T-x")
        self.assertEqual(code, 1)
        self.assertNotIn("zzhouseterm", out + err)
        self.assertEqual(self.get()["comments"], [])

    def test_manifest_search_never_climbs_past_the_checkout(self):
        """Fails if: a ``manifest.json`` above the checkout can mark a picture as demo, or ``denylist_required`` is read by a
        second implementation instead of ``house_scan.denylist_required``."""
        outer = Path(self.tmp.name) / "outer"
        inner = outer / "checkout"
        (inner / "shots").mkdir(parents=True)
        (outer / "manifest.json").write_text(json.dumps({"media": [{"path": "checkout/shots/p.png", "source": "demo"}]}))
        pic = inner / "shots" / "p.png"
        pic.write_bytes(b"x")
        with mock.patch.object(pr_note, "ROOT", inner):
            self.assertIsNone(pr_note.manifest_source(pic))
            (inner / "shots" / "manifest.json").write_text(json.dumps({"media": [{"path": "p.png", "source": "demo"}]}))
            self.assertEqual(pr_note.manifest_source(pic), "demo")
        with mock.patch.object(pr_note.house_scan, "denylist_required", return_value=True) as seen:
            self.assertTrue(pr_note.denylist_required())
        seen.assert_called_once()

    def test_missing_denylist_warns_once_and_goes_on_unless_required(self):
        """Fails if: a missing list blocks work by default, the warning repeats, or ``denylist_required`` does not refuse."""
        missing = {"HOUSE_SCAN_DENYLIST": str(Path(self.tmp.name) / "nope.txt")}
        with mock.patch.dict(os.environ, missing), mock.patch.object(pr_note, "_WARNED", []):
            code, _out, err = self.post("build", "One.", "1")
            self.assertEqual(code, 0)
            self.assertEqual(err.count("denylist not loaded"), 1)
            self.assertEqual(self.post("build", "Two.", "2")[2].count("denylist not loaded"), 0)
            config = pr_note.ROOT / "tools" / "triage" / "config.json"
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({"denylist_required": True}))
            code, _out, err = self.post("build", "Three.", "3")
            self.assertEqual(code, 1)
            self.assertIn("denylist_required", err)
        self.assertEqual(len(self.get()["comments"]), 2)

    def manifest(self, source, name="shot.png", data=b"x"):
        folder = pr_note.ROOT / "build" / "evidence" / "agents-x" / "pose"
        folder.mkdir(parents=True, exist_ok=True)
        pic = folder / name
        pic.write_bytes(data)
        entry = {"screenshots": [f"build/evidence/agents-x/pose/{name}"]}
        if source:
            entry["source"] = source
        (folder.parent / "manifest.json").write_text(json.dumps({"poses": {"pose": entry}}))
        return pic

    def test_live_unlisted_and_unmanifested_pictures_are_refused(self):
        """Fails if: a picture from live data, one with no manifest entry, or one outside the atlas is attached, or the refusal
        does not name the file."""
        live = self.manifest("live")
        code, _out, err = self.post("build", f"![L]({live})")
        self.assertEqual(code, 1)
        self.assertIn("shot.png", err)
        self.manifest(None)
        self.assertEqual(self.post("build", f"![L]({live})")[0], 1)
        stray = Path(self.tmp.name) / "stray.png"
        stray.write_bytes(b"x")
        code, _out, err = self.post("build", f"![S]({stray})")
        self.assertEqual((code, "stray.png" in err), (1, True))
        self.assertEqual(self.get()["comments"], [])

    def test_demo_and_mockup_pictures_are_attached(self):
        """Fails if: a manifest entry with source demo or mockup is not attached."""
        for rnd, source in enumerate(("demo", "mockup"), start=1):
            pic = self.manifest(source, name=f"{source}.png", data=source.encode())
            self.assertEqual(self.post("build", f"![D]({pic})", str(rnd))[0], 0)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(sum(c.count("--attach") for c in calls if c[:2] == ["pr", "comment"]), 2)
        self.assertEqual(len(self.get()["comments"]), 2)

    def test_oversize_picture_is_refused_with_its_size(self):
        """Fails if: a file over 10 MB is attached, or the refusal does not give its size."""
        big = self.atlas_picture("big.mp4")
        with big.open("r+b") as f:
            f.truncate(11 * 1024 * 1024)
        code, _out, err = self.post("build", f"![V]({big})")
        self.assertEqual(code, 1)
        self.assertIn("big.mp4 is 11.0 MB, over the 10 MB limit", err)

    def test_a_duplicate_file_is_uploaded_once(self):
        """Fails if: two files with the same bytes are both uploaded, in one comment or across comments, or the second is not
        replaced by ``Same as <first caption>``."""
        one, two = self.atlas_picture("one.png", b"same"), self.atlas_picture("two.png", b"same")
        self.post("evidence", f"![iPhone Duo folded]({one})\n![iPad]({two})", "1", "--class", "duo")
        self.post("evidence", f"![iPad again]({two})", "1", "--class", "ipad")
        calls = [json.loads(line) for line in self.log.read_text().splitlines() if '"comment"' in line]
        self.assertEqual(sum(c.count("--attach") for c in calls), 1)
        first, second = (c["body"] for c in self.get()["comments"])
        self.assertIn("Same as iPhone Duo folded", first)
        self.assertIn("Same as iPhone Duo folded", second)
        self.assertEqual(second.count("user-attachments"), 0)


class TimelineTests(Base):
    """The step index in the PR body."""

    def test_timeline_lists_posted_steps_in_order_with_links(self):
        """Fails if: a post does not refresh the index, lines are out of step order, a line lacks its link, the block is
        duplicated, or other body text changes."""
        self.set_state(body="Intro\n")
        self.post("research", "Looked at prior art. More words follow.", "1")
        self.post("build", "Built the writer. Next bit.", "1")
        self.post("review", "Reviewed the head.", "1", "--step", "7")
        body = self.get()["body"]
        self.assertTrue(body.startswith("Intro\n"))
        self.assertEqual(body.count("<!-- sh-timeline:start -->"), 1)
        block = body.split("<!-- sh-timeline:start -->\n")[1].split("\n<!-- sh-timeline:end -->")[0].splitlines()
        self.assertEqual(block, [
            "1. [Researcher, round 1: Looked at prior art.](https://example.test/pull/7#issuecomment-1)",
            "2. [Coder, round 1: Built the writer.](https://example.test/pull/7#issuecomment-2)",
            "7. [Reviewer, round 1: Reviewed the head.](https://example.test/pull/7#issuecomment-3)"])
        self.assertIn("unchanged", self.run_cli("timeline", "--task", "T-x")[1])

    def test_a_bold_lead_in_label_is_not_the_step_sentence(self):
        """Fails if: a step whose body starts ``**What I did.** I read it.`` is listed as just ``What I did.``."""
        self.post("research", "**What I did.** I read it. More.", "1")
        self.assertIn("1. [Researcher, round 1: I read it.](", self.get()["body"])

    def test_a_timeline_failure_only_warns(self):
        """Fails if: a failing index update undoes or hides the post, or changes the exit code."""
        with mock.patch.object(pr_note, "timeline", side_effect=pr_note.NoteError("boom")):
            code, out, err = self.post("build", "Built.")
        self.assertEqual((code, out.strip()), (0, "pr_note: posted"))
        self.assertIn("timeline not updated", err)
        self.assertEqual(len(self.get()["comments"]), 1)


class AppFailureTests(Base):
    """A role whose GitHub App call fails: the reason is shown and the note is posted with the gh login, never lost."""

    REASON = "GitHub answered 404 for POST /repos/o/n/issues/7/comments"
    SECRET = "gh" + "p_" + "abcdefghijklmnopqrstuvwxyz0123456789"

    def app(self, fail=True, reason=None):
        """Patch ``gh_app_token`` so ``steward`` resolves to an app whose REST call fails."""
        def api_request(method, path, token, payload=None):
            if fail:
                raise pr_note.gh_app_token.AppError(reason or self.REASON)
        for name, value in (("available", lambda role: True), ("token", lambda role, timeout=None: "t"),
                            ("has_recorded_slug", lambda role: True), ("recorded_slug", lambda role: f"s-h-{role}"),
                            ("api_request", api_request)):
            p = mock.patch.object(pr_note.gh_app_token, name, value)
            p.start()
            self.addCleanup(p.stop)

    def queue_files(self, task="T-x"):
        return sorted((pr_note.NOTES_DIR / task / "queue").glob("*.json"))

    def test_a_failing_role_prints_its_reason_and_posts_with_the_gh_login(self):
        """Fails if: the stderr line shows only the exception class name, carries a secret from the message, or the comment is
        lost (queued instead of posted with the ``gh`` login)."""
        self.app(reason=self.REASON + " " + self.SECRET)
        code, out, err = self.post("retro", "Did it.", "1", "--as", "steward")
        self.assertEqual((code, out.strip()), (0, "pr_note: posted"))
        self.assertIn("pr_note: steward app failed (GitHub answered 404 for POST /repos/o/n/issues/7/comments", err)
        self.assertIn("); posted with the gh login", err)
        self.assertNotIn(self.SECRET, err)
        self.assertNotIn("AppError", err)
        self.assertEqual(len(self.get()["comments"]), 1)
        self.assertRegex(self.get()["comments"][0]["body"], r"^#### Step 1 · Steward · round 1")
        self.assertEqual(self.queue_files(), [])

    def test_a_queued_note_for_a_failing_role_does_not_block_later_posts(self):
        """Fails if: a queued note whose role fails keeps the queue from flushing, a later post warns ``queue not flushed``, or
        the notes are not posted in their original order."""
        self.set_state(pr=None)
        self.post("research", "First.", "1", "--as", "steward")
        self.post("build", "Second.", "1", "--as", "steward")
        self.assertEqual(len(self.queue_files()), 2)
        self.set_state(pr=7)
        self.app()
        code, _out, err = self.post("review", "Third.", "1")
        self.assertEqual(code, 0)
        self.assertNotIn("queue not flushed", err)
        kinds = [re.search(r"<!-- sh:(\w+)", c["body"]).group(1) for c in self.get()["comments"]]
        self.assertEqual(kinds, ["research", "build", "review"])
        self.assertEqual(self.queue_files(), [])

    def test_flush_drops_a_queued_note_with_the_posted_body_and_applies_a_changed_one(self):
        """Fails if: a queued note with the same body as the posted comment is posted again, or a queued edit (a different body for
        a posted marker, queued after a failed post) is dropped instead of applied."""
        self.post("retro", "Old text.", "1")
        self.set_state(pr=None)
        self.post("retro", "Old text.", "1")
        self.set_state(pr=7)
        self.assertIn("flushed 0", self.run_cli("flush", "--task", "T-x")[1])
        self.assertEqual(self.queue_files(), [])
        self.set_state(fail=True)
        self.post("retro", "Edited text.", "1")  # the edit fails and is queued
        self.set_state(fail=False)
        self.assertEqual(len(self.queue_files()), 1)
        self.assertIn("flushed 1", self.run_cli("flush", "--task", "T-x")[1])
        self.assertEqual(self.queue_files(), [])
        self.assertEqual(len(self.get()["comments"]), 1)
        self.assertIn("Edited text.", self.get()["comments"][0]["body"])

    def test_a_refused_or_failing_queued_note_does_not_stop_the_ones_behind_it(self):
        """Fails if: a queued note the gate refuses (or that cannot be read) stays first and blocks the later notes, is deleted, or
        is not reported."""
        self.set_state(pr=None)
        self.post("pick", "ok one", "1")
        self.post("verdict", "ok two", "1")
        self.post("research", "ok three", "1")
        first, second, _third = self.queue_files()
        bad = json.loads(first.read_text())
        bad["body"] = "zzhouseterm"
        first.write_text(json.dumps(bad))
        second.write_text("{}")
        self.set_state(pr=7)
        code, _out, err = self.run_cli("flush", "--task", "T-x")
        self.assertEqual(code, 1)
        self.assertNotIn("zzhouseterm", err)
        self.assertIn(first.name, err)
        self.assertIn(second.name, err)
        self.assertEqual([c["body"].count("<!-- sh:research") for c in self.get()["comments"]], [1])
        self.assertEqual(self.queue_files(), [first, second])


class HeaderFormTests(Base):
    """The step header is its own heading line; the two exceptions keep their first line."""

    def test_old_glued_comment_is_rewritten_in_the_new_form_in_place(self):
        """Fails if: a comment whose body hash is unchanged keeps its older glued header, or the rewrite adds a second comment."""
        old = ("Step 1 · Steward · round 1 · 01:38Z · **What I did.** I read it.\n\n"
               f"<!-- sh-hash:{pr_note.body_hash('**What I did.** I read it.')} -->\n<!-- sh:retro:T-x:1 -->\n")
        self.set_state(comments=[{"id": 1, "body": old, "html_url": "https://example.test/pull/7#issuecomment-1"}])
        self.assertIn("edited", self.post("retro", "**What I did.** I read it.", "1")[1])
        comments = self.get()["comments"]
        self.assertEqual(len(comments), 1)
        lines = comments[0]["body"].splitlines()
        self.assertRegex(lines[0], r"^#### Step 1 · Steward · round 1 · \d\d:\d\dZ · updated \d\d:\d\dZ$")
        self.assertEqual(lines[1:3], ["", "**What I did.** I read it."])
        self.assertIn("unchanged", self.post("retro", "**What I did.** I read it.", "1")[1])

    def test_a_body_heading_stays_first_and_a_mention_stays_first(self):
        """Fails if: the header goes above the body's own ``#`` heading or above an ``@SFenton`` mention."""
        tag = "<!-- sh:retro:T-x:1 -->"
        head = "Step 2 · Steward · round 1 · 01:00Z"
        self.assertEqual(pr_note.compose("# Title\n\nText.", tag, None, "abc", head).splitlines()[:4],
                         ["# Title", "#### " + head, "", "Text."])
        self.assertEqual(pr_note.compose("@SFenton\n\nText.", tag, None, "abc", head).splitlines()[:5],
                         ["@SFenton", "", "#### " + head, "", "Text."])
        self.assertEqual(pr_note.compose("@SFenton look\nText.", tag, "updated 02:00Z", "abc", head).splitlines()[:5],
                         ["@SFenton look", "", "#### " + head + " · updated 02:00Z", "", "Text."])


class RepoPathTests(Base):
    """REST paths use the repository of ``origin``; a stale ``repo`` in ``apps.json`` lists no comments."""

    def test_comments_and_the_timeline_use_the_origin_repository_not_the_apps_file(self):
        """Fails if: comments are listed under the ``repo`` of ``apps.json`` (so markers are never found and the step list stays
        empty), or the timeline is not written after the posts."""
        self.set_state(slug="Real/Repo", body="Intro\n")
        with mock.patch.object(pr_note.gh_app_token, "default_repo", return_value="Real/Repo"), \
                mock.patch.object(pr_note.gh_app_token, "repo", return_value="Stale/Repo"):
            self.post("research", "Looked.", "1")
            self.post("build", "Built.", "1")
            self.assertIn("unchanged", self.post("build", "Built.", "1")[1])
        body = self.get()["body"]
        self.assertEqual(len(self.get()["comments"]), 2)
        self.assertEqual(body.count("<!-- sh-timeline:start -->"), 1)
        self.assertIn("2. [Coder, round 1: Built.]", body)
        self.assertNotIn("Stale/Repo", self.log.read_text())

    def test_an_empty_step_list_after_a_post_warns_with_its_reason(self):
        """Fails if: a post that cannot find any step for the task ends silently without a timeline."""
        with mock.patch.object(pr_note, "timeline", return_value="no steps"):
            _code, _out, err = self.post("build", "Built.")
        self.assertIn("timeline not updated: no steps", err)


class InitNoPlaceholderTests(Base):
    def test_init_adds_marker_blocks_and_no_text(self):
        """Fails if: ``init`` puts any plain section or placeholder text into an empty body."""
        self.run_cli("init", "--task", "T-x")
        body = self.get()["body"]
        self.assertNotRegex(re.sub(r"<!--.*?-->", "", body, flags=re.S).strip(), r"\S")
        self.assertNotIn("What changed", body)


if __name__ == "__main__":
    unittest.main()
