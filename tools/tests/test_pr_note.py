"""``tools/pr_note.py`` against a fake ``gh`` that keeps a PR (body and comments) in a JSON file.

A queued note has one target, fixed when it is queued: a PR (number, plus its head branch when read) or a branch with no PR
yet. ``TargetTests`` has one test per cell of this table that can occur (``test_<writer>_<named>_<when>``)::

    who writes                 target named by  no PR yet                gh error on post         gh error on edit
    -------------------------  ---------------  -----------------------  -----------------------  -----------------------
    lane worktree, no ledger   --pr N           cannot occur (N exists)  PR N                     PR N
    (the default setup)        --branch B       branch B                 PR found through B       PR found through B
                               nothing          branch = writer's        PR of writer's branch    PR of writer's branch
    lane worktree, ledger      --pr N           cannot occur             PR N                     PR N
    lists its branch           --branch B       branch B                 PR found through B       PR found through B
                               nothing          branch = writer's        PR of writer's branch    PR of writer's branch
    orchestrator checkout,     --pr N           cannot occur             PR N                     PR N
    branch not in the ledger   --branch B       branch B                 PR found through B       PR found through B
                               nothing          refused, exit 1: pass    the ledger's single      the ledger's single
                                                --pr N or --branch B     open PR                  open PR

In every cell that queues, the note is then not sent to a sibling PR (another number, another head branch), is reported there,
and is sent by the same writer naming the target the same way. Sending: the target is that PR's number, or the target branch is
that PR's head branch; nothing else. A note with no target (older version) goes only with ``--pr`` or ``--branch`` while the ledger
lists at most one branch. Every ``flush``, ``init`` and ``post`` ends with one stderr line per note left queued.

The default setup has no ledger (a lane worktree: ``build/tasks`` is git-ignored and absent there); tests that need one write it.
"""

import ast
import io
import json
import os
import re
import stat
import struct
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
if st.get("fail") or any(k in args for k in st.get("fail_on", [])):
    sys.stderr.write("HTTP 500 boom"); sys.exit(1)
def save(): json.dump(st, open(state_path, "w"))
def sent():
    """The body as GitHub shows it: every reference to an attached file (relative to the body file's folder, as gh reads
    it) becomes that file's own asset URL; an attached file the body does not reference is appended."""
    import hashlib, re
    source = args[args.index("--body-file") + 1]
    text = sys.stdin.read() if source == "-" else open(source).read()
    base = os.getcwd() if source == "-" else os.path.dirname(os.path.abspath(source))
    for i, a in enumerate(args):
        if a != "--attach":
            continue
        path = os.path.abspath(args[i + 1].split("#")[0])
        url = "https://github.com/user-attachments/assets/" + hashlib.sha256(open(path, "rb").read()).hexdigest()[:12]
        hit = [0]
        def swap(m):
            if os.path.abspath(os.path.join(base, m.group(2))) != path:
                return m.group(0)
            hit[0] += 1
            if path.endswith((".mp4", ".mov")):
                return url  # a video comes back as a bare asset URL (a player), with no alt text
            return "![%s](%s)" % (m.group(1), url)
        text = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)", swap, text)
        if not hit[0]:
            text += "\n![%s](%s)" % (os.path.basename(path), url)
    return text
if args[:2] == ["pr", "view"] and args[-1] == "headRefName":
    print(json.dumps({"headRefName": (st.get("heads") or {}).get(args[2], st.get("head", "agents/x"))}))
elif args[:2] == ["pr", "view"]:
    if not st.get("pr"):
        sys.stderr.write("no pull requests found for branch"); sys.exit(1)
    if "number" in args[-1]: print(json.dumps({"number": st["pr"]}))
    else: print(json.dumps({"body": st["body"]}))
elif args[:2] == ["pr", "list"]:
    print(json.dumps([{"number": st["branches"][args[3]]}] if args[3] in st.get("branches", {}) else []))
elif args[:2] == ["pr", "edit"]:
    st["body"] = sent(); save()
elif args[:2] == ["pr", "comment"]:
    text = sent()
    cid = max([st.get("last_id", 0), len(st["comments"])] + [c["id"] for c in st["comments"]]) + 1  # an id is never reused
    st["last_id"] = cid
    st["comments"].append({"id": cid, "body": text, "html_url": "https://example.test/pull/7#issuecomment-%d" % cid}); save()
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

def formed(text, result="Done.", following="Nothing."):
    """``text`` in the comment form: each line of words is one action, picture lines go below the result, and the three
    headings each hold a bullet list. Tests that are not about the form write one line and get a valid body."""
    words, pictures = [], []
    for line in text.splitlines():
        if line.strip().startswith(("![", "|", "<img")):
            pictures.append(line)
        elif line.strip() and not line.startswith("<!--"):
            words.append("- " + line.strip().lstrip("#").strip())
    marks = [line for line in text.splitlines() if line.startswith("<!--")]
    parts = ["### Actions Taken", *(words or ["- Did it."]), "", "### Result", f"- {result}", *([""] + pictures if pictures else []),
             "", "### Next Steps", f"- {following}", *([""] + marks if marks else [])]
    return "\n".join(parts) + "\n"


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
        os.environ.pop("TASKS_DIR", None)  # no ledger by default, as in a lane worktree; ``write_ledger`` makes one
        for target, value in (("NOTES_DIR", tmp / "notes"), ("ROOT", tmp), ("current_branch", lambda: "agents/x")):
            p = mock.patch.object(pr_note, target, value)
            p.start()
            self.addCleanup(p.stop)

    def write_ledger(self, *branches, task="T-x"):
        """The task ledger this checkout reads (``build/tasks/<task>.json``), listing ``branches``."""
        folder = Path(self.tmp.name) / "build" / "tasks"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{task}.json").write_text(json.dumps({"branches": list(branches)}))

    def writer(self, branch):
        """Run as a checkout whose current branch is ``branch``."""
        return mock.patch.object(pr_note, "current_branch", lambda: branch)

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
        f.write_text(text if "### Actions Taken" in text or text.startswith("**What I did.**") else formed(text))
        return str(f)

    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = pr_note.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def visible(self, index=0):
        """What people see of a comment: its text without the hidden marker lines."""
        return re.sub(r"<!--.*?-->", "", self.get()["comments"][index]["body"], flags=re.S).strip()

    def meta(self, index=0):
        """The hidden ``sh-meta`` values of a comment."""
        return pr_note.meta_of(self.get()["comments"][index])

    def post(self, kind, text, rnd="1", *extra, task="T-x"):
        return self.run_cli("post", kind, "--task", task, "--round", rnd, "--body-file", self.body_file(text), *extra)


class CommentTests(Base):
    def test_new_then_unchanged_then_edited(self):
        self.assertIn("posted", self.post("verdict", "**Designer** (agent) · pass\n\nLooks right.")[1])
        self.assertEqual(len(self.get()["comments"]), 1)
        self.assertIn("<!-- sh:verdict:T-x:s1 -->", self.get()["comments"][0]["body"])
        self.assertIn("unchanged", self.post("verdict", "**Designer** (agent) · pass\n\nLooks right.")[1])
        self.assertEqual(len(self.get()["comments"]), 1)
        self.assertIn("edited", self.post("verdict", "**Designer** (agent) · changes\n\nNo.")[1])
        comments = self.get()["comments"]
        self.assertEqual(len(comments), 1)
        self.assertEqual(comments[0]["body"].splitlines()[0], "## Designer")
        self.assertEqual(self.meta(), {"step": "1", "round": "1", "ident": "round"})

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
        for tag in ("iphone:s1", "duo:s2", "ipad:s3", "duo:s4"):
            self.assertEqual(sum(f"<!-- sh:evidence:T-x:{tag} -->" in b for b in bodies), 1, tag)
        self.assertEqual([self.meta(i)["round"] for i in range(4)], ["1", "1", "1", "2"])
        self.assertIn("again", bodies[1])

    def test_evidence_needs_a_class(self):
        code, _out, err = self.post("evidence", "x")
        self.assertEqual(code, 0)
        self.assertIn("needs --class", err)
        self.assertEqual(self.get()["comments"], [])

    def test_renderer_marker_is_replaced_not_doubled(self):
        self.post("evidence", "**V** · duo\n\ntext\n\n<!-- sh:evidence:T-x:duo:1 -->", "1", "--class", "duo")
        body = self.get()["comments"][0]["body"]
        self.assertEqual((body.count("<!-- sh:evidence:"), body.count("<!-- sh:evidence:T-x:duo:s1 -->")), (1, 1))

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
        self.assertNotRegex(self.visible(), r"\d\d:\d\dZ|happened|posted when")  # no time is shown, also for a queued note
        self.assertEqual(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json")), [])

    def test_failed_post_is_queued_and_exits_zero(self):
        self.set_state(fail=True)
        code, _out, err = self.post("verdict", "**D** · pass")
        self.assertEqual(code, 0)
        self.assertEqual(len(err.strip().splitlines()), 2)  # the warning and the line for the queued note
        self.assertEqual(len(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json"))), 1)


class BlockTests(Base):
    BODY = "intro\n<!-- sh-status:start -->\nold\n<!-- sh-status:end -->\nmid\n<!-- sh-devices:start -->\nold\n<!-- sh-devices:end -->\n" + REVIEW + "\ntail\n"

    def test_status_and_devices_leave_everything_else_identical(self):
        """Fails if: ``devices`` writes a table into the description or keeps an old filled block, ``status`` shows text, or
        either changes text outside its own block, the reviewer's block included."""
        self.set_state(body=self.BODY)
        self.assertIn("updated", self.run_cli("status", "--task", "T", "--line", "**Status:** Review pass")[1])
        self.assertIn("updated", self.run_cli("devices", "--task", "T")[1])
        body = self.get()["body"]
        self.assertNotIn("sh-devices", body)
        self.assertNotIn("| Duo", body)
        self.assertIn("intro\n", body)
        self.assertIn("mid\n", body)
        self.assertIn("unchanged", self.run_cli("devices", "--task", "T")[1])
        self.assertEqual(body[body.index("<!-- review:start -->"):body.index("<!-- review:end -->")],
                         REVIEW[:REVIEW.index("<!-- review:end -->")])
        self.assertTrue(body.startswith("intro\n") and body.endswith("tail\n") and "\nmid\n" in body)
        self.assertNotIn("old", body)

    def test_status_text_is_never_shown(self):
        """Fails if: ``status`` writes text people see into the description ("Drafting" or any other line), drops the hidden
        ``sh-status`` markers, leaves an earlier visible line there, or a line with ``--`` or ``>`` ends the comment early."""
        self.set_state(body="Intro\n<!-- sh-status:start -->\n**Status:** Drafting · Waiting on: nobody\n<!-- sh-status:end -->\nTail\n")
        self.assertIn("updated", self.run_cli("status", "--task", "T", "--line", "Ready --> waiting on: nobody")[1])
        body = self.get()["body"]
        self.assertEqual(re.sub(r"<!--.*?-->", "", body, flags=re.S), "Intro\n\n\n\nTail\n")
        self.assertIn("<!-- sh-status:start -->\n<!-- sh-status-line: Ready - waiting on: nobody -->\n<!-- sh-status:end -->", body)

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
        ``sh-devices`` / ``sh-status`` block, adds a ``sh-timeline`` block (a place for a step list), does not flush the queue, or a second ``init`` rewrites the body."""
        self.set_state(pr=None)
        self.post("pick", "**Designer** · pick")
        self.set_state(pr=7, body="Old text\n" + REVIEW + "\ntail")
        self.assertIn("body updated, flushed 1", self.run_cli("init", "--task", "T-x")[1])
        body = self.get()["body"]
        self.assertTrue(body.startswith("Old text\n"))
        self.assertIn("Old text\n" + REVIEW + "\ntail", body)
        self.assertEqual(body.count("<!-- review:start -->"), 1)
        self.assertIn("<!-- sh-status:start -->", body)
        self.assertNotIn("sh-devices", body)
        self.assertNotIn("sh-timeline", body)
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
            f.write_text("not json")
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
        ``## <Role>`` on its own line, or does not keep its step and round in the hidden line."""
        for rnd, (kind, role) in enumerate((("research", "Researcher"), ("build", "Coder"), ("review", "Reviewer"),
                                            ("retro", "Steward")), start=1):
            self.assertIn("posted", self.post(kind, f"{role} did the work.", str(rnd))[1])
            body = self.get()["comments"][-1]["body"]
            self.assertEqual(body.splitlines()[:3], [f"## {role}", "", "### Actions Taken"])
            self.assertEqual(self.meta(-1), {"step": str(rnd), "round": str(rnd), "ident": "round"})
            self.assertTrue(body.rstrip().endswith(f"<!-- sh:{kind}:T-x:s{rnd} -->"))

    def test_as_names_the_role_and_head_is_shortened(self):
        """Fails if: ``--as`` does not set the role in the heading, ``--head`` is not kept as its first 7 characters in the hidden
        line, or the head is shown to people."""
        with mock.patch.dict(os.environ, {"FENTON_HASS_APPS_DIR": str(Path(self.tmp.name) / "no-apps")}):  # no key: the owner login posts
            _code, _out, err = self.post("build", "Done.", "2", "--as", "coder", "--head", "8afc84d1234567")
        self.assertIn("no app identity for coder", err)
        self.assertEqual(self.comment_lines()[0], "## Coder")
        self.assertEqual(self.meta(), {"step": "1", "round": "2", "ident": "round", "head": "8afc84d"})
        self.assertNotIn("8afc84d", self.visible())

    def test_heading_is_its_own_line_and_an_edit_keeps_its_step(self):
        """Fails if: the role heading shares a line with the body, the blank line or the body is lost, an edit loses its step
        number, or an edit shows "updated" or a time."""
        self.post("research", "First.")
        self.post("pick", "Body.")
        self.post("pick", "Body, changed.")
        lines = self.comment_lines(1)
        self.assertEqual(lines[:4], ["## Designer", "", "### Actions Taken", "- Body, changed."])
        self.assertEqual(self.meta(1)["step"], "2")
        self.assertNotRegex(self.visible(1), r"updated|\d\d:\d\dZ")

    def test_step_numbers_count_distinct_markers_and_an_edit_keeps_its_number(self):
        """Fails if: steps do not count up by distinct marker, a second post of one marker takes a new number, ``--step`` is
        ignored, or a queued note is not counted. (Step 9 skips steps, so it needs ``--now``: see ``StepTests``.)"""
        self.post("research", "One.", "1")
        self.post("build", "Two.", "1")
        self.post("build", "Two, changed.", "1")
        self.post("review", "Nine.", "1", "--step", "9", "--now")
        steps = [pr_note.step_of(c) for c in self.get()["comments"]]
        self.assertEqual(steps, [1, 2, 9])
        self.set_state(pr=None, comments=[])
        self.post("retro", "Q one.", "1", task="T-q")
        self.post("retro", "Q two.", "2", task="T-q")
        self.set_state(pr=7)
        self.run_cli("flush", "--task", "T-q")
        steps = [pr_note.step_of(c) for c in self.get()["comments"]]
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
        open PRs and a writer it does not list picks one instead of refusing with the fix, or anything is queued or posted."""
        ledger = Path(self.tmp.name) / "tasks"
        ledger.mkdir()
        (ledger / "T-x.json").write_text(json.dumps({"branches": ["agents/sibling", "agents/mine"]}))
        self.set_state(pr=7, branches={"agents/sibling": 70, "agents/mine": 7}, heads={"7": "agents/mine", "70": "agents/sibling"})
        self.assertEqual(pr_note.find_pr(None, None, "T-x", str(ledger)), (7, "agents/mine"))
        self.assertEqual(pr_note.find_pr(None, "agents/sibling", "T-x", str(ledger)), (70, "agents/sibling"))
        self.set_state(pr=None)
        with self.writer("t3/orchestrator"):
            with self.assertRaises(pr_note.NoteError) as ctx:
                pr_note.find_pr(None, None, "T-x", str(ledger))
            self.assertIn("#7", str(ctx.exception))
            self.assertIn("#70", str(ctx.exception))
            code, _out, err = self.run_cli("post", "build", "--task", "T-x", "--round", "1", "--ledger-dir", str(ledger),
                                           "--body-file", self.body_file("Built."))
        self.assertEqual(code, 1)
        self.assertIn("pass --pr N or --branch B", err)
        self.assertEqual(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json")), [])
        self.assertEqual(self.get()["comments"], [])

    def test_head_must_be_7_to_40_hex_characters(self):
        """Fails if: ``--head`` accepts text that is not a commit id, or refuses a full 40-character sha."""
        for bad in ("abc", "not-a-sha!", "g" * 8, "a" * 41):
            with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
                self.post("build", "x", "1", "--head", bad)
        self.assertIn("posted", self.post("build", "x", "1", "--head", "a" * 40)[1])

    def test_pr_found_by_the_task_ledger(self):
        """Fails if: the single open PR of the ledger's branches is not used by a writer the ledger does not list, it is used
        silently, or an unreadable ledger breaks the run instead of counting as no ledger."""
        ledger = Path(self.tmp.name) / "tasks"
        ledger.mkdir()
        (ledger / "T-x.json").write_text(json.dumps({"branches": ["agents/y", "agents/x"]}))
        self.set_state(pr=None, branches={"agents/x": 7})
        with self.writer("t3/orchestrator"):
            _code, out, err = self.run_cli("post", "research", "--task", "T-x", "--round", "1", "--ledger-dir", str(ledger),
                                           "--body-file", self.body_file("Found."))
        self.assertIn("posted", out)
        self.assertIn("using #7 (agents/x)", err)
        (ledger / "T-x.json").write_text("not json")
        self.assertEqual(pr_note.ledger_branches("T-x", str(ledger)), [])


class SharedQueueTests(Base):
    """The queue lives in one shared folder; the old per-checkout queue is drained into it."""

    def entry(self, folder, stamp, kind, body):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{stamp:020d}-{kind}-all-1.json").write_text(json.dumps(
            {"kind": kind, "class": None, "round": 1, "body": formed(body), "time": "11:32Z", "branch": "agents/x", "as": None}))

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
        self.assertNotIn("11:32Z", self.get()["comments"][0]["body"])

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
            {"kind": "pick", "class": None, "round": 1, "body": "zzhouseterm", "time": "11:32Z", "branch": "agents/x", "as": None}))
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


STEP_LIST = ("<!-- sh-timeline:start -->\n1. [Researcher: Looked.](https://example.test/pull/7#issuecomment-1)\n"
             "<!-- sh-timeline:end -->")


class TimelineTests(Base):
    """The description holds no step list; the tool keeps the step order in its own memory."""

    def test_a_post_writes_no_step_list(self):
        """Fails if: a post writes a ``sh-timeline`` block or any ``N. [Role: ...]`` line into the description, other body text
        changes, or the step order the tool keeps (``steps_of``) is lost."""
        self.set_state(body="Intro\n")
        self.post("research", "Looked at prior art.\nRead two more notes.", "1")
        self.post("build", "Built the writer.", "1")
        self.post("review", "Reviewed the head.", "1", "--step", "7", "--now")
        body = self.get()["body"]
        self.assertEqual(body, "Intro\n")
        self.assertNotIn("sh-timeline", body)
        self.assertNotRegex(body, r"\d+\. \[")
        self.assertEqual(pr_note.steps_of(self.get()["comments"], "T-x"), {1: 1, 2: 2, 3: 7})

    def test_the_timeline_command_writes_no_list(self):
        """Fails if: ``timeline`` adds a block to a body that has none, or reports an update."""
        self.set_state(body="Intro\n")
        self.post("research", "Looked.", "1")
        self.assertIn("unchanged", self.run_cli("timeline", "--task", "T-x")[1])
        self.assertEqual(self.get()["body"], "Intro\n")

    def test_a_filled_step_list_goes_on_the_next_post(self):
        """Fails if: a description that still holds a filled list keeps it after a post, loses text around it, or keeps the
        markers; or an empty marker pair is rewritten."""
        self.set_state(body="Intro\n\n" + STEP_LIST + "\n\n<!-- sh-status:start -->\n<!-- sh-status:end -->\n")
        self.post("research", "Looked.", "1")
        self.assertEqual(self.get()["body"], "Intro\n\n<!-- sh-status:start -->\n<!-- sh-status:end -->\n")
        empty = "Intro\n\n<!-- sh-timeline:start -->\n<!-- sh-timeline:end -->\n"
        self.set_state(body=empty)
        self.assertIn("unchanged", self.run_cli("timeline", "--task", "T-x")[1])
        self.assertEqual(self.get()["body"], empty)

    def test_the_timeline_command_removes_a_filled_list(self):
        """Fails if: the ``timeline`` command leaves a filled list in place."""
        self.set_state(body="Intro\n\n" + STEP_LIST + "\n")
        self.assertIn("updated", self.run_cli("timeline", "--task", "T-x")[1])
        self.assertEqual(self.get()["body"], "Intro\n\n")

    def test_a_list_removal_failure_only_warns(self):
        """Fails if: a failing removal undoes or hides the post, or changes the exit code."""
        with mock.patch.object(pr_note, "timeline", side_effect=pr_note.NoteError("boom")):
            code, out, err = self.post("build", "Built.")
        self.assertEqual((code, out.strip()), (0, "pr_note: posted"))
        self.assertIn("step list not removed", err)
        self.assertEqual(len(self.get()["comments"]), 1)


class ElsewhereCommentTests(Base):
    def test_the_eight_live_comments_of_pr_81_pass_the_comment_gate(self):
        """Fails if: any of the eight step comments on pull request 81 (fixtures copied from the live pull request) is refused
        by the comment form gate, for its form or for pointing elsewhere."""
        comments = json.loads((Path(__file__).parent / "pr81_comments.json").read_text(encoding="utf-8"))
        self.assertEqual(len(comments), 8)
        for text in comments:
            pr_note.form_gate(text, "fixture")

    """A comment that sends the reader to a fix made elsewhere names the repository and its state, as a description does."""

    def test_a_comment_without_a_name_is_refused_and_one_with_a_name_is_posted(self):
        """Fails if: a comment saying the fix is "in a different repository" is posted, the refusal does not name the rule,
        the refused text reaches the queue, or a comment that names ``owner/repo`` and its state is refused."""
        code, _out, err = self.post("build", "The finished card stays; that fix is in the server engine in a different repository.")
        self.assertEqual(code, 1)
        self.assertIn("elsewhere", err)
        self.assertEqual(self.get()["comments"], [])
        self.assertEqual(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json")), [])
        code, out, _err = self.post(
            "build", "The finished card stays; that fix is in a different repository, `SFenton/ha-fenton-home`, and is not pushed.")
        self.assertEqual((code, out.strip()), (0, "pr_note: posted"))


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
        self.assertRegex(self.get()["comments"][0]["body"], r"^## Steward\n")
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
        second.write_text("not json")
        self.set_state(pr=7)
        code, _out, err = self.run_cli("flush", "--task", "T-x")
        self.assertEqual(code, 1)
        self.assertNotIn("zzhouseterm", err)
        self.assertIn(first.name, err)
        self.assertIn(second.name, err)
        self.assertEqual([c["body"].count("<!-- sh:research") for c in self.get()["comments"]], [1])
        self.assertEqual(self.queue_files(), [first, second])


class TargetBase(Base):
    """Helpers for the queue target tests: lane ``agents/x`` (PR #7) and its sibling ``agents/sib`` (PR #8)."""

    LANE, SIB, ORCH = "agents/x", "agents/sib", "t3/orchestrator"

    def queue_dir(self, task="T-x"):
        return pr_note.NOTES_DIR / task / "queue"

    def notes(self, task="T-x"):
        return [json.loads(f.read_text()) for f in sorted(self.queue_dir(task).glob("*.json"))]

    def targets(self):
        return [(n.get("pr"), n.get("branch")) for n in self.notes()]

    def kinds(self):
        return [n["kind"] for n in self.notes()]

    def posted(self):
        return [re.search(r"<!-- sh:(\w+)", c["body"]).group(1) for c in self.get()["comments"]]

    def pr_open(self, own=True, **extra):
        """PR #7 (head ``agents/x``) and the sibling's #8 exist; ``own``: #7 is the PR of the writer's current branch."""
        self.set_state(pr=7 if own else None, branches={self.LANE: 7}, heads={"7": self.LANE, "8": self.SIB}, **extra)

    def flush(self, *flags):
        return self.run_cli("flush", "--task", "T-x", *flags)


class TargetTests(TargetBase):
    """One test per cell of the module table: what target a queued note gets, that a sibling PR never receives it, and that the
    same writer's next flush delivers it."""

    def check(self, who, named, when):
        """Run one cell: queue a note as ``who`` (``lane``, ``listed`` or ``orch``) naming the target by ``named`` (``pr``,
        ``branch`` or ``nothing``) at ``when`` (``no_pr``, ``post_error`` or ``edit_error``); then flush the sibling, then the lane."""
        if who != "lane":
            self.write_ledger(self.LANE, self.SIB)
        flags = {"pr": ["--pr", "7"], "branch": ["--branch", self.LANE], "nothing": []}[named]
        own = who != "orch"  # the orchestrator's own branch never has the lane's PR
        with self.writer(self.ORCH if who == "orch" else self.LANE):
            if when == "no_pr":
                self.set_state(pr=None)
                code, out, _err = self.post("build", "Note text.", "1", *flags)
                want = (None, self.LANE)
            else:
                self.pr_open(own)
                if when == "edit_error":
                    self.assertIn("posted", self.post("build", "First text.", "1", *flags)[1])
                self.set_state(fail_on=["PATCH" if when == "edit_error" else "comment"])
                code, out, _err = self.post("build", "Note text.", "1", *flags)
                want = (7, self.LANE)
            self.assertEqual((code, self.targets()), (0, [want]), out)
            self.pr_open(own, fail_on=[])
            before = json.dumps(self.get()["comments"])
            _code, out, err = self.flush("--pr", "8")
            self.assertIn("flushed 0", out)
            self.assertEqual((self.targets(), json.dumps(self.get()["comments"])), ([want], before))
            self.assertRegex(err, r"queued build round 1 for .* not sent \(.*\): this is #8 \(agents/sib\)")
            _code, out, err = self.flush(*flags)
            self.assertIn("flushed 1", out)
            self.assertEqual((self.targets(), self.posted()), ([], ["build"]))
            self.assertIn("Note text.", self.get()["comments"][0]["body"])
            self.assertNotIn("not sent", err)

    def test_default_setup_has_no_ledger(self):
        """Fails if: the shared test setup gives every test a ledger again, hiding the commonest real case (a lane worktree)."""
        self.assertEqual(pr_note.ledger_branches("T-x"), [])
        self.assertFalse((Path(self.tmp.name) / "build" / "tasks").exists())
        self.assertIsNone(os.environ.get("TASKS_DIR"))

    # who writes: a lane worktree with no ledger
    def test_lane_pr_post_error(self):
        """Fails if: a post with ``--pr`` that hits a gh error is not queued for that PR, reaches the sibling, or is not sent later."""
        self.check("lane", "pr", "post_error")

    def test_lane_pr_edit_error(self):
        """Fails if: an edit with ``--pr`` that hits a gh error is lost, reaches the sibling, or is not applied later."""
        self.check("lane", "pr", "edit_error")

    def test_lane_branch_no_pr(self):
        """Fails if: ``--branch B`` before B's PR exists does not queue for branch B, or the note goes to a PR with another head."""
        self.check("lane", "branch", "no_pr")

    def test_lane_branch_post_error(self):
        """Fails if: a failed post whose PR was found through ``--branch`` is not queued for that PR's number and head."""
        self.check("lane", "branch", "post_error")

    def test_lane_branch_edit_error(self):
        """Fails if: a failed edit whose PR was found through ``--branch`` is lost or queued for anything but that PR."""
        self.check("lane", "branch", "edit_error")

    def test_lane_nothing_no_pr(self):
        """Fails if: a lane worktree with no ledger cannot queue for its own branch (the round 4 finding), or the note is not sent
        once that branch has a PR."""
        self.check("lane", "nothing", "no_pr")

    def test_lane_nothing_post_error(self):
        """Fails if: a failed post to the current branch's PR is queued without that PR's number, or goes elsewhere."""
        self.check("lane", "nothing", "post_error")

    def test_lane_nothing_edit_error(self):
        """Fails if: a failed edit on the current branch's PR is lost or queued for anything but that PR."""
        self.check("lane", "nothing", "edit_error")

    # who writes: a lane worktree whose branch the ledger lists
    def test_listed_pr_post_error(self):
        """Fails if: a readable ledger changes where a failed ``--pr`` post is queued or sent."""
        self.check("listed", "pr", "post_error")

    def test_listed_pr_edit_error(self):
        """Fails if: a readable ledger changes where a failed ``--pr`` edit is queued or applied."""
        self.check("listed", "pr", "edit_error")

    def test_listed_branch_no_pr(self):
        """Fails if: with a ledger, ``--branch B`` before B's PR exists queues for anything but branch B."""
        self.check("listed", "branch", "no_pr")

    def test_listed_branch_post_error(self):
        """Fails if: with a ledger, a failed post found through ``--branch`` is not queued for that PR."""
        self.check("listed", "branch", "post_error")

    def test_listed_branch_edit_error(self):
        """Fails if: with a ledger, a failed edit found through ``--branch`` is lost or queued for another target."""
        self.check("listed", "branch", "edit_error")

    def test_listed_nothing_no_pr(self):
        """Fails if: a writer on a ledger branch is refused, or its note is queued for a sibling ledger branch instead of its own."""
        self.check("listed", "nothing", "no_pr")

    def test_listed_nothing_post_error(self):
        """Fails if: a failed post from a ledger branch with its own PR is queued for anything but that PR."""
        self.check("listed", "nothing", "post_error")

    def test_listed_nothing_edit_error(self):
        """Fails if: a failed edit from a ledger branch with its own PR is lost or queued for another target."""
        self.check("listed", "nothing", "edit_error")

    # who writes: the orchestrator's checkout, whose branch the ledger does not list
    def test_orch_pr_post_error(self):
        """Fails if: a failed ``--pr`` post from the orchestrator's checkout is queued for that checkout's branch (no PR's head)
        and stranded."""
        self.check("orch", "pr", "post_error")

    def test_orch_pr_edit_error(self):
        """Fails if: a failed ``--pr`` edit from the orchestrator's checkout is lost or stranded."""
        self.check("orch", "pr", "edit_error")

    def test_orch_branch_no_pr(self):
        """Fails if: ``--branch B`` from the orchestrator's checkout is refused, or queued for the checkout's own branch."""
        self.check("orch", "branch", "no_pr")

    def test_orch_branch_post_error(self):
        """Fails if: a failed post found through ``--branch`` from the orchestrator's checkout is not queued for that PR."""
        self.check("orch", "branch", "post_error")

    def test_orch_branch_edit_error(self):
        """Fails if: a failed edit found through ``--branch`` from the orchestrator's checkout is lost or stranded."""
        self.check("orch", "branch", "edit_error")

    def test_orch_nothing_no_pr(self):
        """Fails if: a write that names no target, from a checkout whose branch a readable ledger does not list, is queued (for
        that branch or with no target) or posted, does not exit 1, or its one line does not name the fix."""
        self.write_ledger(self.LANE, self.SIB)
        self.set_state(pr=None)
        with self.writer(self.ORCH):
            code, out, err = self.post("build", "For which lane?", "1")
        self.assertEqual((code, out), (1, ""))
        self.assertEqual(len(err.strip().splitlines()), 1)
        self.assertIn("pass --pr N or --branch B", err)
        self.assertEqual((self.notes(), self.get()["comments"]), ([], []))

    def test_orch_nothing_post_error(self):
        """Fails if: a failed post to the ledger's single open PR is queued for the orchestrator's branch or with no target."""
        self.check("orch", "nothing", "post_error")

    def test_orch_nothing_edit_error(self):
        """Fails if: a failed edit on the ledger's single open PR is lost or queued for the orchestrator's branch."""
        self.check("orch", "nothing", "edit_error")


class TargetRuleTests(TargetBase):
    """The reproductions of the four review rounds, the rules around the table, and further attempts to misroute or strand a note."""

    def old_note(self, stamp, kind="research", rnd=1, body="Old."):
        """A queued note with no target, as an older version wrote it."""
        self.queue_dir().mkdir(parents=True, exist_ok=True)
        (self.queue_dir() / f"{stamp:020d}-{kind}-all-{rnd}.json").write_text(json.dumps(
            {"kind": kind, "class": None, "round": rnd, "body": formed(body), "time": "11:32Z", "as": None}))

    # the reproductions from the review rounds
    def test_regression_note_to_a_sibling_pull_request(self):
        """Fails if: with a ledger whose first branch is a sibling lane with an open PR, a lane's note (posted, or queued and then
        flushed) lands on the sibling's PR instead of its own."""
        self.write_ledger(self.SIB, self.LANE)
        self.set_state(pr=7, branches={self.SIB: 8, self.LANE: 7}, heads={"7": self.LANE, "8": self.SIB})
        self.assertEqual(pr_note.find_pr(None, None, "T-x"), (7, self.LANE))
        self.set_state(fail_on=["comment"])
        self.post("build", "Mine.", "1")
        self.assertEqual(self.targets(), [(7, self.LANE)])
        self.set_state(fail_on=[])
        self.assertIn("flushed 0", self.flush("--pr", "8")[1])
        self.assertEqual(self.get()["comments"], [])
        self.assertIn("flushed 1", self.flush()[1])

    def test_regression_failed_edit_is_not_lost(self):
        """Fails if: an edit that hit a gh error is dropped by the next flush because its marker is already on the PR, instead of
        being applied."""
        self.post("retro", "Old text.", "1")
        self.set_state(fail_on=["PATCH"])
        self.post("retro", "Edited text.", "1")
        self.assertEqual(self.targets(), [(7, self.LANE)])
        self.set_state(fail_on=[])
        self.assertIn("flushed 1", self.flush()[1])
        self.assertEqual((self.notes(), len(self.get()["comments"])), ([], 1))
        self.assertIn("Edited text.", self.get()["comments"][0]["body"])

    def test_regression_cross_lane_flush(self):
        """Fails if: flushing one lane's PR sends the notes another lane queued for the same task, or leaves them unreported."""
        self.set_state(pr=None)
        with self.writer("agents/lane-a"):
            self.post("research", "Lane A.", "1")
        with self.writer("agents/lane-b"):
            self.post("build", "Lane B.", "1")
        self.set_state(heads={"7": "agents/lane-a", "8": "agents/lane-b"})
        _code, out, err = self.flush("--pr", "7")
        self.assertIn("flushed 1", out)
        self.assertEqual((self.posted(), self.kinds()), (["research"], ["build"]))
        self.assertIn("queued build round 1 for branch agents/lane-b not sent", err)
        self.assertIn("this is #7 (agents/lane-a)", err)
        self.set_state(comments=[])
        self.assertIn("flushed 1", self.flush("--pr", "8")[1])
        self.assertEqual((self.posted(), self.kinds()), (["build"], []))

    def test_regression_note_stranded_from_the_orchestrators_checkout_with_pr(self):
        """Fails if: a post with ``--pr 8`` from the orchestrator's checkout that hits a gh error (the head unreadable too) is queued
        for that checkout's branch, which is no PR's head, so no flush ever sends it."""
        self.write_ledger("agents/lane-a", "agents/lane-b")
        self.set_state(pr=None, heads={"8": "agents/lane-b"}, fail_on=["comment", "headRefName"])
        with self.writer(self.ORCH):
            code, _out, err = self.post("build", "Built.", "1", "--pr", "8")
            self.assertEqual((code, self.targets()), (0, [(8, "")]))
            self.assertIn("queued build round 1 for #8 not sent", err)
            self.set_state(fail_on=[])
            self.assertIn("flushed 1", self.flush("--pr", "8")[1])
        self.assertEqual((self.notes(), self.posted()), ([], ["build"]))

    def test_regression_note_queued_in_a_lane_worktree_before_its_pr_is_sent_by_init_there(self):
        """Fails if: a note queued in a lane worktree with no ledger, before ``ship.sh`` opens its PR, records no target, or
        ``init`` in that same worktree (no flags) does not send it."""
        self.set_state(pr=None)
        self.assertIn("queued", self.post("research", "Before the PR.", "1")[1])
        self.assertEqual(self.targets(), [(None, self.LANE)])
        self.set_state(pr=7)
        _code, out, err = self.run_cli("init", "--task", "T-x")
        self.assertIn("flushed 1", out)
        self.assertEqual((self.notes(), self.posted(), err), ([], ["research"], ""))

    def test_regression_drop_queued_keeps_notes_that_are_not_for_this_pr(self):
        """Fails if: a successful post removes a queued note of the same marker whose target is another lane's branch, another
        PR, or nothing (an older note); or keeps the stale one whose target is this PR (by branch or by number)."""
        self.set_state(pr=None)
        self.old_note(1, "build")
        with self.writer(self.SIB):
            self.post("build", "Sibling's.", "1")
        self.post("build", "Mine, stale.", "1")
        self.post("build", "Other lane's.", "1", "--branch", "agents/other")
        pr_note.queue_note("T-x", "build", None, 1, "Number 9.", (9, "agents/nine"))
        pr_note.queue_note("T-x", "build", None, 1, "Mine by number, stale.", (7, ""))
        self.pr_open()
        with mock.patch.object(pr_note, "flush", side_effect=pr_note.NoteError("not now")):  # only drop_queued may remove a note
            _code, out, err = self.post("build", "Mine, new.", "1")
        self.assertIn("posted", out)
        self.assertEqual(self.targets(), [(None, None), (None, self.SIB), (None, "agents/other"), (9, "agents/nine")])
        self.assertEqual(err.count("not sent"), 4)
        self.assertIn("flushed 0", self.flush()[1])
        self.assertEqual(len(self.get()["comments"]), 1)
        self.assertIn("Mine, new.", self.get()["comments"][0]["body"])

    # the rules around the table
    def test_ledger_with_no_branches_or_unreadable_queues_for_the_writers_branch(self):
        """Fails if: a ledger that lists no branches, or cannot be parsed, makes a write that names nothing be refused."""
        self.set_state(pr=None)
        self.write_ledger()
        with self.writer(self.ORCH):
            self.assertEqual(self.post("build", "One.", "1")[0], 0)
            (Path(self.tmp.name) / "build" / "tasks" / "T-x.json").write_text("not json")
            self.assertEqual(self.post("build", "Two.", "2")[0], 0)
        self.assertEqual(self.targets(), [(None, self.ORCH)] * 2)

    def test_refusal_applies_to_two_open_ledger_prs_and_when_gh_is_down(self):
        """Fails if: from a checkout the ledger does not list, a note that names nothing is sent to one of two open PRs, or is
        queued with the checkout's branch when gh fails, instead of being refused with the fix."""
        self.write_ledger(self.LANE, self.SIB)
        with self.writer(self.ORCH):
            self.set_state(pr=None, branches={self.LANE: 7, self.SIB: 8})
            self.assertEqual(self.post("build", "Which?", "1")[0], 1)
            self.set_state(fail=True)
            code, _out, err = self.post("build", "Which?", "1")
        self.assertEqual((code, self.notes(), self.get()["comments"]), (1, [], []))
        self.assertIn("pass --pr N or --branch B", err)

    def test_note_without_a_target_goes_only_when_named_and_the_ledger_lists_at_most_one_branch(self):
        """Fails if: a note with no target (older version) is sent by a run that names no PR, or while the ledger lists two
        branches, or is kept unreported; or is held back by ``--pr`` with one ledger branch or none."""
        self.old_note(1, rnd=1)
        self.old_note(2, rnd=2)
        _code, out, err = self.flush()
        self.assertIn("flushed 0", out)
        self.assertEqual(err.count("for no target not sent"), 2)
        self.assertIn("sent only with --pr or --branch", err)
        self.write_ledger("agents/a", "agents/b")
        self.assertIn("flushed 0", self.flush("--pr", "7")[1])
        self.assertIn("flushed 0", self.run_cli("init", "--task", "T-x", "--pr", "7")[1])
        self.assertEqual(self.get()["comments"], [])
        self.write_ledger("agents/a")
        self.assertIn("flushed 2", self.flush("--pr", "7")[1])
        (Path(self.tmp.name) / "build" / "tasks" / "T-x.json").unlink()
        self.old_note(3, rnd=3)
        self.set_state(branches={self.LANE: 7})
        self.assertIn("flushed 1", self.flush("--branch", self.LANE)[1])
        self.assertEqual(self.notes(), [])

    def test_init_flush_and_post_report_every_note_they_leave(self):
        """Fails if: ``init``, ``flush`` or ``post`` finishes with a note still queued and no stderr line giving its kind, round,
        target and reason; or ``flush`` and ``init`` stay silent about the queue when there is no PR or gh fails."""
        self.set_state(pr=None)
        with self.writer(self.SIB):
            self.post("build", "Sibling.", "1")
        line = "queued build round 1 for branch agents/sib not sent"
        for cmd in ("flush", "init"):
            err = self.run_cli(cmd, "--task", "T-x")[2]
            self.assertIn(line, err)
            self.assertIn("waiting for a pull request", err)
        self.set_state(pr=7, fail_on=["api"])
        self.assertIn("gh failed in this run", self.flush()[2])
        self.set_state(fail_on=[])
        for err in (self.flush()[2], self.run_cli("init", "--task", "T-x")[2], self.post("research", "Mine.", "1")[2]):
            self.assertIn(line, err)
            self.assertIn("this is #7 (agents/x)", err)

    def test_the_single_open_ledger_pull_request_is_named_when_used(self):
        """Fails if: the ledger's only open PR is used silently, or is used by a writer whose own branch the ledger lists."""
        self.write_ledger("agents/y", self.LANE)
        self.set_state(pr=None, branches={"agents/y": 9})
        err = io.StringIO()
        with self.writer(self.ORCH), redirect_stderr(err):
            self.assertEqual(pr_note.find_pr(None, None, "T-x"), (9, "agents/y"))
        self.assertIn("using #9 (agents/y)", err.getvalue())
        self.assertEqual(pr_note.find_pr(None, None, "T-x"), (None, ""))

    # further attempts to misroute or strand a note
    def test_break_branch_flag_without_a_pr_never_falls_back_to_the_writers_own_pr(self):
        """Fails if: ``--branch B`` before B's PR exists, written from a checkout whose own branch has a PR, posts the note (or
        the status line) to the writer's PR instead of queueing it for B."""
        self.pr_open()
        code, out, _err = self.post("build", "For the other lane.", "1", "--branch", "agents/other")
        self.assertEqual((code, self.targets(), self.get()["comments"]), (0, [(None, "agents/other")], []), out)
        self.set_state(body="x<!-- sh-status:start -->\n<!-- sh-status:end -->")
        self.assertIn("no PR yet", self.run_cli("status", "--task", "T-x", "--line", "Other lane", "--branch", "agents/other")[1])
        self.assertNotIn("Other lane", self.get()["body"])
        self.assertIn("flushed 0", self.flush()[1])
        self.set_state(branches={"agents/other": 9}, heads={"9": "agents/other"})
        self.assertIn("flushed 1", self.flush("--branch", "agents/other")[1])

    def test_break_a_ledger_lane_without_a_pr_never_uses_its_siblings_only_open_pr(self):
        """Fails if: a note written in a lane worktree whose branch the ledger lists, before its own PR opens, is posted to the
        sibling lane's PR because that is the ledger's single open one."""
        self.write_ledger(self.LANE, self.SIB)
        self.set_state(pr=None, branches={self.SIB: 8}, heads={"8": self.SIB})
        code, out, err = self.post("build", "Mine, early.", "1")
        self.assertEqual((code, self.targets(), self.get()["comments"]), (0, [(None, self.LANE)], []), out)
        self.assertNotIn("using #8", err)
        self.assertEqual(self.flush()[1].strip(), "pr_note: no PR yet")
        self.pr_open()
        self.assertIn("flushed 1", self.flush()[1])

    def test_break_no_branch_checked_out_is_refused_not_queued_for_head(self):
        """Fails if: a write that names nothing from a detached checkout (or one git cannot read) is queued for the branch ``HEAD``
        or with no target, where no flush would ever send it; or ``--branch`` does not fix it."""
        self.set_state(pr=None)
        for branch in ("HEAD", ""):
            with self.writer(branch):
                code, _out, err = self.post("build", "Detached.", "1")
            self.assertEqual((code, self.notes()), (1, []))
            self.assertIn("pass --pr N or --branch B", err)
        with self.writer("HEAD"):
            self.assertEqual(self.post("build", "Detached.", "1", "--branch", self.LANE)[0], 0)
        self.assertEqual(self.targets(), [(None, self.LANE)])

    def test_break_pr_flag_with_a_wrong_branch_flag_records_the_pr_only(self):
        """Fails if: ``--pr 8 --branch X`` that hits a gh error (the head unreadable) records X as the head of #8, so a flush of
        X's own PR takes the note."""
        self.set_state(pr=None, heads={"8": self.SIB, "9": "agents/wrong"}, fail_on=["comment", "headRefName"])
        self.post("build", "For 8.", "1", "--pr", "8", "--branch", "agents/wrong")
        self.assertEqual(self.targets(), [(8, "")])
        self.set_state(fail_on=[])
        self.assertIn("flushed 0", self.flush("--pr", "9")[1])
        self.assertEqual(self.get()["comments"], [])
        self.assertIn("flushed 1", self.flush("--pr", "8")[1])

    def test_break_an_unreadable_head_never_lets_a_newer_note_overtake_an_older_one(self):
        """Fails if: while the PR's head branch cannot be read, a note queued by number is sent (or a new post goes out) ahead of
        an older note of the same marker queued by branch, which a later flush would then apply over the newer text."""
        self.set_state(pr=None)
        self.post("build", "Older text.", "1")
        self.pr_open(fail_on=["headRefName"])
        code, _out, err = self.post("build", "Newer text.", "1")
        self.assertEqual((code, self.targets(), self.get()["comments"]), (0, [(None, self.LANE), (7, "")], []))
        self.assertIn("head branch of #7 could not be read", err)
        _code, _out, err = self.flush()
        self.assertEqual((len(self.notes()), self.get()["comments"]), (2, []))
        self.assertIn("head branch of #7 could not be read", err)
        self.assertEqual(err.count("not sent"), 2)
        self.set_state(fail_on=[])
        self.assertIn("flushed 2", self.flush()[1])
        self.assertEqual((self.notes(), len(self.get()["comments"])), ([], 1))
        self.assertIn("Newer text.", self.get()["comments"][0]["body"])


class HeaderFormTests(Base):
    """The comment form: ``## <Role>``, three bullet lists, and nothing about steps, rounds, heads or times in sight."""

    BODY = ("### Actions Taken\n- Read the report.\n- Read the code.\n\n### Result\n- Found the cause.\n\n"
            "### Next Steps\n- The Coder corrects it.\n")

    def test_comment_is_role_heading_three_lists_and_hidden_step_data(self):
        """Fails if: a posted comment is anything but ``## <Role>`` then the body as written, shows a step number, a round, a
        head or a time, or does not keep step, round and head in the hidden line."""
        self.post("research", self.BODY, "3", "--head", "8afc84d1234567")
        body = self.get()["comments"][0]["body"]
        self.assertEqual(self.visible(), "## Researcher\n\n" + self.BODY.strip())
        self.assertNotRegex(self.visible(), r"Step \d|round|8afc84d|\d\d:\d\dZ")
        self.assertTrue(body.endswith("<!-- sh-meta:step=1 round=3 ident=round head=8afc84d -->\n<!-- sh:research:T-x:s1 -->\n"), body)
        self.assertIn("unchanged", self.post("research", self.BODY, "3")[1])

    def test_body_must_be_three_bullet_lists(self):
        """Fails if: a body that lacks one of the three headings, has them out of order, has a paragraph where a list belongs,
        has an empty section, an extra heading, or is in the older ``**What I did.**`` form is posted or queued, the exit
        code is not 1, or the refusal is more than one line. Fails also if a valid body with pictures below a list is refused."""
        good = self.BODY
        bad = {
            "no Next Steps": good.split("### Next Steps")[0],
            "out of order": "### Result\n- a\n\n### Actions Taken\n- b\n\n### Next Steps\n- c\n",
            "a paragraph": good.replace("- Found the cause.", "Found the cause."),
            "an empty section": good.replace("- Found the cause.\n", ""),
            "an extra heading": good + "\n### Notes\n- more\n",
            "text first": "Hello.\n\n" + good,
            "the older form": "**What I did.** I read it.\n\n**What I found.** A cause.\n\n**Next.** The Coder.\n",
        }
        for name, body in bad.items():
            for pr in (7, None):
                self.set_state(pr=pr)
                code, out, err = self.post("research", body)
                self.assertEqual((code, out, len(err.strip().splitlines())), (1, "", 1), name)
                self.assertIn("not in the comment form", err, name)
        self.assertEqual(self.get()["comments"], [])
        self.assertFalse(list((pr_note.NOTES_DIR / "T-x").glob("queue/*.json")))
        self.set_state(pr=7)
        pic = self.atlas_picture()
        with_pictures = good.replace("- Found the cause.\n", f"- Found the cause.\n  It was the hash.\n\n![Shot]({pic})\n")
        for body in (good, "## Researcher\n\n" + good, with_pictures):
            self.assertEqual(self.post("research", body)[0], 0, body)
        self.assertIsNone(pr_note.form_problem(good.replace("- Found the cause.", "* Found the cause.\n\n| A | B |\n|---|---|\n| <img src=\"u\" alt=\"a\" width=\"260\"> | Same as a |")))

    def test_comment_with_an_older_visible_header_is_rewritten_in_place(self):
        """Fails if: a comment whose body hash is unchanged keeps the visible ``Step N · Role · round R`` header of an older
        version, loses its step number, or the rewrite adds a second comment."""
        old = ("#### Step 4 · Steward · round 1 · 01:38Z\n\n" + self.BODY +
               f"\n<!-- sh-hash:{pr_note.digest_of(self.BODY)} -->\n<!-- sh:retro:T-x:1 -->\n")
        self.set_state(comments=[{"id": 1, "body": old, "html_url": "https://example.test/pull/7#issuecomment-1"}])
        self.assertIn("edited", self.post("retro", self.BODY, "1")[1])
        comments = self.get()["comments"]
        self.assertEqual(len(comments), 1)
        self.assertEqual(self.visible(), "## Steward\n\n" + self.BODY.strip())
        self.assertEqual(self.meta()["step"], "4")
        self.assertIn("unchanged", self.post("retro", self.BODY, "1")[1])

    def test_role_heading_replaces_a_body_heading_and_a_mention_stays_first(self):
        """Fails if: a ``## `` heading the body starts with is kept beside the role's, an ``@SFenton`` mention is not the first
        line, or the hidden lines are not hash, meta, marker in that order at the end."""
        tag, meta = "<!-- sh:retro:T-x:1 -->", pr_note.meta_line(2, 1, "abcdef0123")
        self.assertEqual(pr_note.compose("## Someone\n\n" + self.BODY, tag, "abc", "Steward", meta).splitlines()[:3],
                         ["## Steward", "", "### Actions Taken"])
        text = pr_note.compose("@SFenton\n\n" + self.BODY, tag, "abc", "Orchestrator", meta)
        self.assertEqual(text.splitlines()[:5], ["@SFenton", "", "## Orchestrator", "", "### Actions Taken"])
        self.assertEqual(text.splitlines()[-3:], ["<!-- sh-hash:abc -->", "<!-- sh-meta:step=2 round=1 head=abcdef0 -->", tag])

    def test_hand_edited_comments_are_edited_in_place_and_keep_their_look(self):
        """Fails if: comments edited by hand into the plain form (round markers, no step recorded, scaled ``<img>`` tags, a
        picture table) are doubled or replaced by a re-post, lose their marker, get a step number, a round or a time in
        sight, or have their ``<img>`` lines changed; or a post by step does not find the comment at that place on the page."""
        table = ('| Before | After |\n|---|---|\n| <img src="https://github.com/user-attachments/assets/aa-1" alt="Before" width="280"> '
                 '| <img src="https://github.com/user-attachments/assets/bb-2" alt="After" width="280"> |')
        single = '<img src="https://github.com/user-attachments/assets/cc-3" alt="The card, on iPhone" width="220">'

        def body(action, picture):
            return f"### Actions Taken\n- {action}\n\n### Result\n- Seen.\n\n{picture}\n\n### Next Steps\n- Go on.\n"
        hand = [("research", 1, body("Read it.", single)), ("evidence", 0, body("Recorded it.", single)),
                ("verdict", 1, body("Compared.", table))]
        comments = []
        for cid, (kind, rnd, text) in enumerate(hand, start=1):
            key = f"iphone:{rnd}" if kind == "evidence" else str(rnd)
            role = pr_note.KIND_ROLE[kind]
            comments.append({"id": cid, "html_url": f"u{cid}",
                             "body": f"## {role}\n\n{text}\n<!-- sh-hash:feedfacecafe -->\n<!-- sh:{kind}:R-9:{key} -->\n"})
        self.set_state(comments=comments)
        self.assertIn("edited", self.post("research", body("Read it again.", single), "1", task="R-9")[1])
        self.assertIn("edited", self.post("evidence", body("Recorded it again.", single), "0", "--class", "iphone", task="R-9")[1])
        self.assertIn("edited", self.post("verdict", body("Compared again.", table), "5", "--step", "3", task="R-9")[1])
        after = self.get()["comments"]
        self.assertEqual([c["id"] for c in after], [1, 2, 3])
        for index, (kind, rnd, text) in enumerate(hand):
            role = pr_note.KIND_ROLE[kind]
            want = f"## {role}\n\n" + text.replace("it.", "it again.").replace("Compared.", "Compared again.").strip()
            self.assertEqual(self.visible(index), want)
            self.assertEqual(self.meta(index)["step"], str(index + 1))
        self.assertTrue(after[1]["body"].endswith("<!-- sh:evidence:R-9:iphone:0 -->\n"))
        self.assertTrue(after[2]["body"].endswith("<!-- sh:verdict:R-9:1 -->\n"))
        self.assertIn("unchanged", self.post("verdict", body("Compared again.", table), "5", "--step", "3", task="R-9")[1])


class RepoPathTests(Base):
    """REST paths use the repository of ``origin``; a stale ``repo`` in ``apps.json`` lists no comments."""

    def test_comments_and_the_timeline_use_the_origin_repository_not_the_apps_file(self):
        """Fails if: comments are listed under the ``repo`` of ``apps.json`` (so markers are never found and the step list stays
        empty); the posts are the check here."""
        self.set_state(slug="Real/Repo", body="Intro\n")
        with mock.patch.object(pr_note.gh_app_token, "default_repo", return_value="Real/Repo"), \
                mock.patch.object(pr_note.gh_app_token, "repo", return_value="Stale/Repo"):
            self.post("research", "Looked.", "1")
            self.post("build", "Built.", "1")
            self.assertIn("unchanged", self.post("build", "Built.", "1")[1])
        body = self.get()["body"]
        self.assertEqual(len(self.get()["comments"]), 2)
        self.assertNotIn("sh-timeline", body)
        self.assertNotIn("Stale/Repo", self.log.read_text())


class InitNoPlaceholderTests(Base):
    def test_init_adds_marker_blocks_and_no_text(self):
        """Fails if: ``init`` puts any plain section or placeholder text into an empty body."""
        self.run_cli("init", "--task", "T-x")
        body = self.get()["body"]
        self.assertNotRegex(re.sub(r"<!--.*?-->", "", body, flags=re.S).strip(), r"\S")
        self.assertNotIn("What changed", body)


class PictureBase(Base):
    """Helpers for the picture rule: evidence pictures listed the way the Verifier writes them (``{path, source}`` objects)."""

    def evidence(self, rel, data=b"x", source="demo", root=None, result="pass"):
        """A picture ``build/evidence/agents-x/<rel>`` under ``root`` (default: the checkout), named in that folder's manifest
        under the pose ``rel`` starts with."""
        folder = (root or pr_note.ROOT) / "build" / "evidence" / "agents-x"
        pic = folder / rel
        pic.parent.mkdir(parents=True, exist_ok=True)
        pic.write_bytes(data)
        manifest = folder / "manifest.json"
        listed = json.loads(manifest.read_text()) if manifest.exists() else {"poses": {}}
        pose = listed["poses"].setdefault(rel.split("/")[0], {"result": result, "screenshots": []})
        pose["screenshots"].append({"path": f"build/evidence/agents-x/{rel}", "source": source})
        manifest.write_text(json.dumps(listed))
        return pic

    def attached(self):
        """How many files were attached to comments so far."""
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return sum(c.count("--attach") for c in calls if c[:2] == ["pr", "comment"])

    def bodies(self):
        return [c["body"] for c in self.get()["comments"]]

    @staticmethod
    def url(data):
        """The asset URL the fake ``gh`` gives a file with these bytes."""
        import hashlib
        return "https://github.com/user-attachments/assets/" + hashlib.sha256(data).hexdigest()[:12]

    def img(self, data, caption, width=280):
        """The scaled tag a posted picture with these bytes and caption is written as."""
        return f'<img src="{self.url(data)}" alt="{caption}" width="{width}">'

    def media(self, task="T-x"):
        return json.loads((pr_note.NOTES_DIR / task / "media.json").read_text())


class PictureRuleTests(PictureBase):
    """One picture rule: relative path, identity by bytes, a URL per file, "unchanged" judged after the pictures are resolved."""

    def test_new_picture_after_known_picture(self):
        """Fails if: in a body with a known-URL picture first and a new local one second, the second picture's URL equals the
        first's, ``media.json`` maps two files to one URL or is keyed by anything but the file hash, or an entry an older
        version keyed by path is still used."""
        before, after = self.evidence("iphone/before.png", b"before"), self.evidence("iphone/after.png", b"after")
        notes = pr_note.NOTES_DIR / "T-x"
        notes.mkdir(parents=True)
        (notes / "media.json").write_text(json.dumps({str(before): "https://example.test/old-wrong-url"}))
        self.assertIn("posted", self.post("build", f"Shots.\n\n![Before]({before})")[1])
        self.assertNotIn("old-wrong-url", self.bodies()[0])
        _code, out, _err = self.post("build", f"Shots.\n\n![Before]({before})\n\n![After]({after})")
        self.assertIn("replaced", out)
        self.assertEqual(len(self.bodies()), 1)
        body = self.bodies()[0]
        self.assertIn(self.img(b"before", "Before"), body)
        self.assertIn(self.img(b"after", "After"), body)
        media = self.media()
        self.assertEqual(len(set(media.values())), 2)
        self.assertEqual(sorted(media), sorted(pr_note.file_hash(f) for f in (before, after)))
        self.assertEqual(media[pr_note.file_hash(after)], self.url(b"after"))
        # a later text-only change is an edit in place that keeps each picture's own URL
        self.assertIn("edited", self.post("build", f"Shots, again.\n\n![Before]({before})\n\n![After]({after})")[1])
        self.assertIn(self.img(b"after", "After"), self.bodies()[0])
        self.assertEqual(self.attached(), 2)

    def test_edit_uploads_new_picture(self):
        """Fails if: after an edit of a posted comment with a new local file the posted text still contains the local path (in
        its absolute or relative form), the picture was not uploaded, the comment is doubled, or it loses its step number."""
        self.post("research", "Step one.")
        self.post("verdict", "Looks right.")
        pic = self.evidence("iphone/home.png", b"home")
        _code, out, _err = self.post("verdict", f"Looks right.\n\n![Home]({pic})")
        self.assertIn("replaced", out)
        bodies = self.bodies()
        self.assertEqual(len(bodies), 2)
        self.assertNotIn(str(pic), bodies[1])
        self.assertNotIn("build/evidence", bodies[1])
        self.assertNotIn("home.png", bodies[1])
        self.assertIn(self.img(b"home", "Home"), bodies[1])
        self.assertEqual((bodies[1].splitlines()[0], self.meta(1)["step"]), ("## Designer", "2"))
        self.assertEqual(self.attached(), 1)

    def test_corrected_link_is_an_edit(self):
        """Fails if: the same body with one picture replaced by a different file (another path, or the same path with new
        bytes) is ``unchanged``, or the same bytes under another name are not."""
        wrong, right = self.evidence("iphone/wrong.png", b"wrong"), self.evidence("iphone/right.png", b"right")
        self.post("build", f"After.\n\n![After]({wrong})")
        _code, out, _err = self.post("build", f"After.\n\n![After]({right})")
        self.assertNotIn("unchanged", out)
        self.assertIn(self.url(b"right"), self.bodies()[0])
        self.assertNotIn(self.url(b"wrong"), self.bodies()[0])
        right.write_bytes(b"right, retaken")
        self.assertNotIn("unchanged", self.post("build", f"After.\n\n![After]({right})")[1])
        self.assertIn(self.url(b"right, retaken"), self.bodies()[0])
        copy = self.evidence("iphone/copy.png", b"right, retaken")
        self.assertIn("unchanged", self.post("build", f"After.\n\n![After]({copy})")[1])
        self.assertEqual(len(self.bodies()), 1)

    def test_absolute_path_rewritten(self):
        """Fails if: an absolute picture path under the checkout (below a home folder whose name is on the denylist) trips the
        denylist or reaches the comment or the queue, or the refusal of an absolute path outside every checkout contains
        the path."""
        home = Path(self.tmp.name) / "Users" / "zzhouseterm"
        with mock.patch.object(pr_note, "ROOT", home / "repo"):
            pic = self.evidence("iphone/home.png", b"home")
            self.assertIn("zzhouseterm", str(pic))
            code, out, err = self.post("build", f"Done.\n\n![Home]({pic})")
            self.assertEqual((code, out.strip()), (0, "pr_note: posted"), err)
            self.assertNotIn("zzhouseterm", out + err + self.bodies()[0])
            self.assertIn(self.url(b"home"), self.bodies()[0])
            self.assertEqual(pr_note.normalize_pictures(f"![a]({home}/repo/build/evidence/agents-x/gone.png)"),
                             "![a](build/evidence/agents-x/gone.png)")
            self.set_state(pr=None)
            self.assertIn("queued", self.post("build", f"Later.\n\n![Home]({pic})", "2")[1])
            queued = json.loads(next((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json")).read_text())
            self.assertNotIn("zzhouseterm", queued["body"])  # what will be posted; the file it named is kept beside it, on this machine only
            self.assertIn("build/evidence/agents-x/iphone/home.png", queued["body"])
            self.assertEqual({ref: Path(named).resolve() for ref, named in queued["pictures"].items()},
                             {"build/evidence/agents-x/iphone/home.png": pic.resolve()})
            outside = home / "Pictures" / "private.png"
            outside.parent.mkdir(parents=True)
            outside.write_bytes(b"p")
            code, out, err = self.post("build", f"![P]({outside})", "3")
            self.assertEqual(code, 1)
            self.assertIn("picture 1", err)
            for leak in ("zzhouseterm", "private.png", "Pictures"):
                self.assertNotIn(leak, out + err)
            self.assertEqual(len(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json"))), 1)

    def test_relative_paths_are_found_in_the_evidence_folder_and_in_another_worktree(self):
        """Fails if: a path relative to the checkout, to the branch's evidence folder, or to another worktree of the same
        repository (where the evidence was captured) is not attached, or a file in another worktree skips the manifest rule."""
        self.evidence("iphone/here.png", b"here")
        other = Path(self.tmp.name) / "other-worktree"
        self.evidence("duo-folded/there.png", b"there", root=other)
        self.evidence("duo-folded/live.png", b"live", source="live", root=other)
        with mock.patch.object(pr_note, "checkouts", lambda: [pr_note.ROOT, other]):
            self.post("build", "A.\n\n![Here](build/evidence/agents-x/iphone/here.png)", "1")
            self.post("build", "B.\n\n![Here](iphone/here.png)\n\n![There](build/evidence/agents-x/duo-folded/there.png)", "2")
            code, _out, err = self.post("build", "C.\n\n![L](build/evidence/agents-x/duo-folded/live.png)", "3")
            self.assertEqual(pr_note.normalize_pictures(f"![a]({other}/build/evidence/agents-x/duo-folded/there.png)"),
                             "![a](build/evidence/agents-x/duo-folded/there.png)")
        self.assertEqual((code, "live.png" in err), (1, True))
        first, second = self.bodies()
        self.assertIn(self.url(b"here"), first)
        self.assertIn("Same as Here", second)
        self.assertIn(self.img(b"there", "There"), second)
        self.assertEqual(self.attached(), 2)

    def test_an_absolute_path_in_another_worktree_attaches_that_file(self):
        """Fails if: an absolute path under another worktree attaches this checkout's copy of the same relative path (other
        bytes) instead of the file it named, at once or after the note waited in the queue."""
        other = Path(self.tmp.name) / "lane-worktree"
        self.evidence("iphone/home.png", b"this checkout")
        there = self.evidence("iphone/home.png", b"the lane worktree", root=other)
        with mock.patch.object(pr_note, "checkouts", lambda: [pr_note.ROOT, other]):
            self.assertIn("posted", self.post("build", f"Shot.\n![Home]({there})", "1")[1])
            self.set_state(pr=None)
            self.assertIn("queued", self.post("review", f"Seen.\n![Home again]({there})", "1", task="T-q")[1])
            self.set_state(pr=7)
            self.assertIn("flushed 1", self.run_cli("flush", "--task", "T-q")[1])
        first, second = self.bodies()
        self.assertIn(self.img(b"the lane worktree", "Home"), first)
        self.assertIn(self.img(b"the lane worktree", "Home again"), second)
        for body in (first, second):
            self.assertNotIn(self.url(b"this checkout"), body)
            self.assertNotIn("lane-worktree", body)

    def test_a_queued_notes_picture_file_is_forgotten_before_the_next_note(self):
        """Fails if: in one send of the queue, a note that names a picture by its relative path attaches the file an earlier
        note's absolute path named in another worktree, instead of this checkout's file."""
        other = Path(self.tmp.name) / "lane-worktree"
        rel = "build/evidence/agents-x/iphone/home.png"
        self.evidence("iphone/home.png", b"this checkout")
        there = self.evidence("iphone/home.png", b"the lane worktree", root=other)
        with mock.patch.object(pr_note, "checkouts", lambda: [pr_note.ROOT, other]):
            self.set_state(pr=None)
            self.assertIn("queued", self.post("build", f"Shot.\n![Lane]({there})", "1", task="T-q")[1])
            self.assertIn("queued", self.post("review", f"Seen.\n![Here]({rel})", "1", task="T-q")[1])
            self.set_state(pr=7)
            self.assertIn("flushed 2", self.run_cli("flush", "--task", "T-q")[1])
        first, second = self.bodies()
        self.assertIn(self.img(b"the lane worktree", "Lane"), first)
        self.assertIn(self.img(b"this checkout", "Here"), second)
        self.assertNotIn(self.url(b"the lane worktree"), second)

    def test_manifest_three_shapes(self):
        """Fails if: a picture is refused or attached differently depending on the manifest shape that names it (path strings
        with a pose-level ``source``, ``{path, source}`` objects, a top-level ``media`` list), a ``live`` entry in any shape
        is attached, or a pose that did not run yields a picture."""
        folder = pr_note.ROOT / "build" / "evidence" / "agents-x"
        (folder / "iphone").mkdir(parents=True)
        pic = folder / "iphone" / "home.png"
        pic.write_bytes(b"home")
        rel = "build/evidence/agents-x/iphone/home.png"

        def shapes(source, result="pass"):
            return ({"poses": {"iphone": {"result": result, "source": source, "screenshots": [rel]}}},
                    {"poses": {"iphone": {"result": result, "screenshots": [{"path": rel, "source": source}]}}},
                    {"poses": {"iphone": {"result": result}}, "media": [{"path": rel, "source": source, "pose": "iphone"}]})
        for source, want in (("demo", "demo"), ("mockup", "mockup"), ("live", "live")):
            for manifest in shapes(source):
                (folder / "manifest.json").write_text(json.dumps(manifest))
                self.assertEqual(pr_note.manifest_source(pic), want, manifest)
        for manifest in shapes("live"):
            (folder / "manifest.json").write_text(json.dumps(manifest))
            code, _out, err = self.post("build", f"![Home]({pic})")
            self.assertEqual((code, "home.png" in err), (1, True), manifest)
        for manifest in shapes("demo", result="not_run"):
            (folder / "manifest.json").write_text(json.dumps(manifest))
            self.assertIsNone(pr_note.manifest_source(pic), manifest)
            self.assertEqual(self.post("build", f"![Home]({pic})")[0], 1, manifest)
        self.assertEqual((self.bodies(), self.attached()), ([], 0))
        (folder / "manifest.json").write_text(json.dumps(shapes("demo")[1]))
        self.assertIn("posted", self.post("build", f"![Home]({pic})")[1])

    def test_same_picture_three_classes(self):
        """Fails if: the same bytes for the evidence classes ``iphone``, ``duo`` (iPhone Duo) and ``ipad`` cause more than one
        upload, the second or third class carries a picture instead of ``Same as <caption>``, or different bytes on ``duo``
        do not upload."""
        shots = {"iphone": self.evidence("iphone/card.png", b"card"), "duo": self.evidence("duo-folded/card.png", b"card"),
                 "ipad": self.evidence("ipad-portrait/card.png", b"card")}
        for step, (cls, pic) in enumerate(shots.items(), start=1):
            self.assertIn("posted", self.post("evidence", f"Card.\n\n![{cls} card]({pic})", "1", "--class", cls,
                                              "--step", str(step))[1])
        self.assertEqual(self.attached(), 1)
        first, second, third = self.bodies()
        self.assertIn(self.img(b"card", "iphone card"), first)
        for body in (second, third):
            self.assertIn("Same as iphone card", body)
            self.assertNotIn("user-attachments", body)
            self.assertNotIn("card.png", body)
        # a re-post of the first class keeps its picture, and is the same note
        self.assertIn("unchanged", self.post("evidence", f"Card.\n\n![iphone card]({shots['iphone']})", "1", "--class",
                                             "iphone", "--step", "1")[1])
        differs = self.evidence("duo-partial-fold/card.png", b"card, half open")
        self.post("evidence", f"Card.\n\n![duo half open]({differs})", "2", "--class", "duo", "--step", "4")
        self.assertEqual(self.attached(), 2)
        self.assertIn(self.img(b"card, half open", "duo half open"), self.bodies()[3])


class StepTests(Base):
    """A comment is identified by its kind and step; the older kind and round markers are still read; page order is step order."""

    def steps(self):
        return [pr_note.step_of(c) for c in self.get()["comments"]]

    def markers(self):
        return [re.search(r"<!-- (sh:[^ ]+) -->\s*$", c["body"]).group(1) for c in self.get()["comments"]]

    def old_comment(self, cid, kind, step, rnd, text="Old.", task="T"):
        return {"id": cid, "html_url": f"https://example.test/pull/7#issuecomment-{cid}",
                "body": f"#### Step {step} · Designer · round {rnd} · 10:00Z\n\n{text}\n\n<!-- sh-hash:0 -->\n"
                        f"<!-- sh:{kind}:{task}:{rnd} -->\n"}

    def test_two_notes_one_kind_one_round(self):
        """Fails if: a second note of one kind in the same round with another step edits the first (``pick`` and ``evidence``),
        a re-post of a step makes a new comment, or an old-marker comment (``sh:pick:T:1``) on the PR is no longer found by
        an old-form re-post or by a post that names its step, or loses its marker when edited."""
        self.assertIn("posted", self.post("pick", "Options.", "1", "--step", "1")[1])
        self.assertIn("posted", self.post("pick", "The pick.", "1", "--step", "2")[1])
        self.assertIn("posted", self.post("evidence", "Recorded.", "1", "--class", "duo", "--step", "3")[1])
        self.assertIn("posted", self.post("evidence", "Captured.", "1", "--class", "duo", "--step", "4")[1])
        self.assertEqual(self.markers(), ["sh:pick:T-x:s1", "sh:pick:T-x:s2", "sh:evidence:T-x:duo:s3", "sh:evidence:T-x:duo:s4"])
        self.assertIn("Options.", self.get()["comments"][0]["body"])
        self.assertIn("unchanged", self.post("pick", "The pick.", "1", "--step", "2")[1])
        self.assertIn("edited", self.post("pick", "The pick, revised.", "3", "--step", "2")[1])
        self.assertEqual((len(self.get()["comments"]), self.steps()), (4, [1, 2, 3, 4]))
        self.assertEqual(self.meta(1), {"step": "2", "round": "3"})
        # the comments an older version left on a pull request: kind and round markers
        self.set_state(comments=[self.old_comment(1, "pick", 1, 1), self.old_comment(2, "verdict", 2, 0),
                                 self.old_comment(3, "pick", 3, 0)])
        self.assertIn("edited", self.post("pick", "Re-posted the old way.", "1", task="T")[1])
        self.assertIn("edited", self.post("verdict", "Re-posted by its step.", "1", "--step", "2", task="T")[1])
        self.assertIn("edited", self.post("pick", "Second pick by its step.", "1", "--step", "3", task="T")[1])
        comments = self.get()["comments"]
        self.assertEqual([c["id"] for c in comments], [1, 2, 3])
        self.assertEqual(self.markers(), ["sh:pick:T:1", "sh:verdict:T:0", "sh:pick:T:0"])
        for comment, text in zip(comments, ("Re-posted the old way.", "Re-posted by its step.", "Second pick by its step.")):
            self.assertIn(text, comment["body"])
        self.assertEqual(self.steps(), [1, 2, 3])

    def test_a_post_by_round_finds_the_single_step_form_comment_of_that_round(self):
        """Fails if: a post that names no step doubles the one comment of its kind and round that was posted with ``--step``,
        or picks one of two such comments."""
        self.post("build", "Built.", "1", "--step", "1")
        self.assertIn("edited", self.post("build", "Built, more.", "1")[1])
        self.assertEqual(len(self.get()["comments"]), 1)
        self.post("build", "Built again.", "1", "--step", "2")
        self.assertIn("posted", self.post("build", "Which one?", "1")[1])
        self.assertEqual(self.markers(), ["sh:build:T-x:s1", "sh:build:T-x:s2", "sh:build:T-x:s3"])
        self.assertIn("unchanged", self.post("build", "Which one?", "1")[1])  # found again by its kind and round

    def test_a_post_without_a_step_gets_the_next_step_and_the_step_marker(self):
        """Fails if: a new comment posted without ``--step`` still gets the older round marker, takes a step number a comment on
        the page holds, is not found again by its kind and round (a re-post doubles it), or a comment with the older round
        marker is no longer edited in place with its marker kept."""
        self.post("research", "One.", "1")
        self.post("build", "Two.", "1")
        self.post("build", "Round two.", "2")
        self.assertEqual(self.markers(), ["sh:research:T-x:s1", "sh:build:T-x:s2", "sh:build:T-x:s3"])
        self.assertIn("edited", self.post("build", "Two, changed.", "1")[1])
        self.assertIn("unchanged", self.post("build", "Round two.", "2")[1])
        self.assertEqual((len(self.get()["comments"]), self.steps()), (3, [1, 2, 3]))
        self.assertIn("Two, changed.", self.get()["comments"][1]["body"])
        self.set_state(comments=[self.old_comment(1, "pick", 1, 1), self.old_comment(2, "pick", 5, 2)])
        self.assertIn("posted", self.post("verdict", "New.", "1", task="T")[1])
        self.assertIn("edited", self.post("pick", "Old one, edited.", "2", task="T")[1])
        self.assertEqual(self.markers(), ["sh:pick:T:1", "sh:pick:T:2", "sh:verdict:T:s3"])
        self.assertEqual(self.steps(), [1, 5, 3])
        self.assertIn("posted", self.post("build", "Newer.", "1", task="T")[1])  # four markers: 4 is free
        self.assertIn("posted", self.post("review", "Newest.", "1", task="T")[1])  # 5 is held: one above the highest
        self.assertEqual(self.steps(), [1, 5, 3, 4, 6])

    def test_replacing_a_hand_edited_comment_keeps_every_step(self):
        """Fails if: after a comment that records no step (edited by hand) is posted anew because of a new picture, it or any
        other unrecorded comment of the task counts as a different step than before, or the new copy loses its round marker."""
        def plain(cid, kind, text):
            return {"id": cid, "html_url": f"u{cid}",
                    "body": f"## {pr_note.KIND_ROLE[kind]}\n\n{formed(text)}\n<!-- sh-hash:0 -->\n<!-- sh:{kind}:T:1 -->\n"}
        self.set_state(comments=[plain(1, "research", "Read."), plain(2, "pick", "Wrote."), plain(3, "build", "Built."),
                                 plain(4, "review", "Passed.")])
        self.assertEqual(pr_note.steps_of(self.get()["comments"], "T"), {1: 1, 2: 2, 3: 3, 4: 4})
        pic = self.atlas_picture("new.png", b"new shot")
        self.assertIn("replaced", self.post("pick", f"Wrote.\n![Shot]({pic})", "1", task="T")[1])
        comments = self.get()["comments"]
        steps = pr_note.steps_of(comments, "T")
        self.assertEqual([c["id"] for c in comments][:3], [1, 3, 4])
        self.assertEqual([steps[c["id"]] for c in comments], [1, 3, 4, 2])
        self.assertTrue(comments[3]["body"].endswith("<!-- sh:pick:T:1 -->\n"))
        self.assertIn("user-attachments", comments[3]["body"])

    def test_step_order_hold(self):
        """Fails if: after step 3 is posted before step 2 the page order (creation order) is 3 then 2, a held step is lost or
        sent twice, the hold is not reported, ``--now`` does not send at once with a warning, or an edit of a posted step
        is held."""
        self.post("research", "One.", "1", "--step", "1")
        code, out, err = self.post("review", "Three.", "1", "--step", "3")
        self.assertEqual(code, 0)
        self.assertIn("held", out)
        self.assertIn("held until step 2 is posted", err)
        self.assertEqual(self.steps(), [1])
        self.assertIn("flushed 0", self.run_cli("flush", "--task", "T-x")[1])
        self.assertEqual(self.steps(), [1])
        self.assertIn("posted", self.post("build", "Two.", "1", "--step", "2")[1])
        self.assertEqual(self.steps(), [1, 2, 3])
        self.assertEqual(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json")), [])
        self.assertIn("flushed 0", self.run_cli("flush", "--task", "T-x")[1])
        self.assertEqual(len(self.get()["comments"]), 3)
        code, out, err = self.post("retro", "Six.", "1", "--step", "6", "--now")
        self.assertIn("posted", out)
        self.assertIn("step 6 posted before step 4", err)
        self.assertIn("edited", self.post("retro", "Six, changed.", "1", "--step", "6")[1])
        self.assertEqual(self.steps(), [1, 2, 3, 6])

    def test_flush_sends_a_queue_in_step_order(self):
        """Fails if: notes queued before the PR exists as steps 3, 2, 1 appear on the page in any order but 1, 2, 3 after one
        ``flush``, or a step whose predecessor never arrives is sent instead of staying queued and reported."""
        self.set_state(pr=None)
        for step, text in ((3, "Three."), (2, "Two."), (1, "One."), (5, "Five.")):
            self.assertIn("queued", self.post("build", text, "1", "--step", str(step))[1])
        self.set_state(pr=7)
        _code, out, err = self.run_cli("flush", "--task", "T-x")
        self.assertIn("flushed 3", out)
        self.assertEqual(self.steps(), [1, 2, 3])
        self.assertIn("held until step 4 is posted", err)
        self.assertEqual(len(list((pr_note.NOTES_DIR / "T-x" / "queue").glob("*.json"))), 1)
        self.assertIn("posted", self.post("review", "Four.", "1", "--step", "4")[1])
        self.assertEqual(self.steps(), [1, 2, 3, 4, 5])


def png(width, height, salt=b""):
    """The start of a PNG file of this size (enough for its size to be read), made unique by ``salt``."""
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", width, height) + b"\x08\x06\x00\x00\x00" + salt


class PictureScaleTests(PictureBase):
    """Every attached picture, gif or video is written scaled: ``<img src alt width>`` (a video as a player of the same width)."""

    BODY = "### Actions Taken\n- Captured.\n\n### Result\n- Seen.\n\n{pictures}\n\n### Next Steps\n- Go on.\n"

    def post_pictures(self, pictures, *extra, kind="build", rnd="1"):
        return self.post(kind, self.BODY.format(pictures=pictures), rnd, *extra)

    def test_a_picture_is_an_img_tag_with_a_width_for_its_shape(self):
        """Fails if: a posted picture is left in the full-size ``![]()`` form, a portrait capture is not 280 wide, a landscape one
        (PNG or gif) not 480, a file whose size cannot be read not 280, the caption is not the ``alt`` text, or a quote in a
        caption breaks the tag."""
        tall = self.evidence("iphone/tall.png", png(1179, 2556))
        wide = self.evidence("ipad-landscape/wide.png", png(2732, 2048))
        gif = self.evidence("ipad-landscape/move.gif", b"GIF89a" + struct.pack("<HH", 800, 600) + b"x")
        odd = self.evidence("iphone/odd.png", b"not a picture")
        self.assertIn("posted", self.post_pictures(
            f'![The card, on iPhone]({tall})\n\n![iPad "on its side"]({wide})\n\n![Moving]({gif})\n\n![Odd]({odd})')[1])
        body = self.bodies()[0]
        self.assertIn(self.img(png(1179, 2556), "The card, on iPhone", 280), body)
        self.assertIn(f'<img src="{self.url(png(2732, 2048))}" alt="iPad &quot;on its side&quot;" width="480">', body)
        self.assertIn(self.img(b"GIF89a" + struct.pack("<HH", 800, 600) + b"x", "Moving", 480), body)
        self.assertIn(self.img(b"not a picture", "Odd", 280), body)
        self.assertNotIn("![", body)
        self.assertEqual((len(self.bodies()), self.attached()), (1, 4))
        self.assertEqual(pr_note.picture_size(tall), (1179, 2556))
        jpeg = Path(self.tmp.name) / "p.jpg"
        jpeg.write_bytes(b"\xff\xd8\xff\xe0\x00\x04ab\xff\xc0\x00\x11\x08" + struct.pack(">HH", 600, 800) + b"rest")
        self.assertEqual(pr_note.picture_size(jpeg), (800, 600))
        # the same pictures again, with other words: an edit in place that keeps the scaled tags
        self.assertIn("edited", self.post_pictures(f"![The card, on iPhone]({tall})\n\n![Odd]({odd})")[1])
        self.assertIn(self.img(png(1179, 2556), "The card, on iPhone", 280), self.bodies()[0])
        self.assertNotIn("![", self.bodies()[0])

    def test_two_pictures_side_by_side_are_a_table_at_260_each(self):
        """Fails if: two pictures alone on one line are not one table row under their captions at 260 each, pictures in a table
        the body wrote are not 260 each, or a single picture takes the table width."""
        before, after = self.evidence("iphone/before.png", png(1179, 2556, b"b")), self.evidence("iphone/after.png", png(1179, 2556, b"a"))
        self.post_pictures(f"![Before]({before}) ![After]({after})")
        b, a = self.img(png(1179, 2556, b"b"), "Before", 260), self.img(png(1179, 2556, b"a"), "After", 260)
        self.assertIn(f"| Before | After |\n|---|---|\n| {b} | {a} |", self.bodies()[0])
        left, right = self.evidence("duo-folded/left.png", png(10, 20, b"l")), self.evidence("duo-folded/right.png", png(10, 20, b"r"))
        self.post_pictures(f"| Option B (selected) | Option C |\n|---|---|\n| ![B]({left}) | ![C]({right}) |", rnd="2")
        want = f"| Option B (selected) | Option C |\n|---|---|\n| {self.img(png(10, 20, b'l'), 'B', 260)} | {self.img(png(10, 20, b'r'), 'C', 260)} |"
        self.assertIn(want, self.bodies()[1])
        for body in self.bodies():
            self.assertNotIn("![", body)

    def test_a_video_is_a_player_of_the_same_width_and_an_asset_link_is_scaled_too(self):
        """Fails if: an attached video is left as a bare full-size link or as ``![]()`` instead of ``<video src width controls>``,
        its URL is taken from a picture beside it, or an uploaded-asset URL written as ``![]()`` is not written scaled."""
        clip = self.evidence("duo-partial-fold/fold.mp4", b"a clip")
        shot = self.evidence("duo-partial-fold/shot.png", png(20, 10))
        asset = "https://github.com/user-attachments/assets/11111111-aaaa"
        self.post_pictures(f"![Shot]({shot})\n\n![Folding]({clip})\n\n![Earlier]({asset})")
        body = self.bodies()[0]
        self.assertIn(f'<video src="{self.url(b"a clip")}" width="280" controls></video>', body)
        self.assertIn(self.img(png(20, 10), "Shot", 480), body)
        self.assertIn(f'<img src="{asset}" alt="Earlier" width="280">', body)
        self.assertNotIn("![", body)
        self.assertEqual(re.findall(r"^https://\S+$", body, re.M), [])
        self.assertEqual(self.media()[pr_note.file_hash(clip)], self.url(b"a clip"))

    def test_devices_never_writes_a_table_or_a_picture_into_the_description(self):
        """Fails if: ``devices`` puts a table or a picture into a description with an empty block, or adds a block to one without."""
        shot = self.evidence("ipad-portrait/home.png", png(2048, 2732))
        f = Path(self.tmp.name) / "devices.md"
        f.write_text(f"| iPad | ![Home]({shot}) |")
        for start in ("Intro\n<!-- sh-devices:start -->\n<!-- sh-devices:end -->\nTail\n", "Intro\nTail\n"):
            self.set_state(body=start)
            self.assertIn("unchanged", self.run_cli("devices", "--task", "T-x", "--file", str(f))[1])
            self.assertEqual(self.get()["body"], start)


class RenderedEvidenceTests(PictureBase):
    """What ``pr_visual.py render`` prints is what the Verifier posts: it must pass the comment form and come out scaled."""

    def test_the_rendered_class_comment_posts_through_pr_note(self):
        """Fails if: the body ``pr_visual.render_class`` writes is refused by the comment form, is posted with a visible round
        or role line, leaves a before or after picture in the full-size form or not uploaded, or the same output posted
        again is not ``unchanged``."""
        import pr_visual
        before = self.evidence("duo-partial-fold/before.png", png(1812, 2176, b"b"))
        after = self.evidence("duo-partial-fold/after.png", png(1812, 2176, b"a"))
        selection = {"task": "T-x", "base_pack": "build/evidence/agents-x/before", "after_pack": "build/evidence/agents-x/after",
                     "pose_notes": {"duo-folded": "no tree in the before pack"},
                     "classes": {"duo": {
                         "needs_evidence": True, "reason": "the hinge layout changed",
                         "poses": {"Half open": "changed", "Folded": "unknown", "Lying flat": "same"},
                         "pairs": [{"pose": "Half open", "surface": "Security", "before": str(before), "after": str(after),
                                    "compared": True}],
                         "clips": [{"label": "Flat to half open and back", "why": "the sections move across the hinge"}],
                         "checked_not_shown": [{"what": "2 more screens", "covered_by": "the same layout code"}],
                         "more_pairs": [], "transition_files": ["apple/Sources/HassUI/UKHingedPanes.swift"]}}}
        body = pr_visual.render_class(selection, "duo", 2)
        self.assertIsNone(pr_note.form_problem(body), body)
        code, out, err = self.post("evidence", body, "2", "--class", "duo")
        self.assertEqual((code, out.strip()), (0, "pr_note: posted"), err)
        posted = self.bodies()[0]
        seen = self.visible()
        self.assertTrue(seen.startswith("## Verifier\n\n### Actions Taken\n"))
        self.assertNotRegex(seen, r"round|\*\*Verifier\*\*|!\[")
        row = (f"| Half open: Security | {self.img(png(1812, 2176, b'b'), 'Before: Half open, Security', 260)} | "
               f"{self.img(png(1812, 2176, b'a'), 'After: Half open, Security', 260)} |")
        self.assertIn(row, posted)
        self.assertIn("- Clip: Flat to half open and back, about 10 s. Why this one: the sections move across the hinge. Not recorded yet.", posted)
        self.assertEqual((self.attached(), self.meta()["round"]), (2, "2"))
        self.assertEqual(posted.count("<!-- sh:evidence:"), 1)
        self.assertIn("unchanged", self.post("evidence", body, "2", "--class", "duo")[1])


if __name__ == "__main__":
    unittest.main()
