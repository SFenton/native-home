"""``tools/hooks/merge_guard.py``: text that merely mentions a merge command in a ``cat`` heredoc runs nothing (#370), and a read-only
``sed -n`` is not a landing step."""

import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
import merge_guard  # noqa: E402

#: The owner sign-off flag, built here so this source never spells it out.
FLAG = "owner" + "-ack"
MERGE = "gh pr merge 9 --auto --squash"


def verdict(cmd):
    """The agent-session verdict (the owner-sign-off check runs only for agent sessions)."""
    with mock.patch.dict("os.environ", {"FENTON_HEADLESS": ""}):
        return merge_guard.reason(cmd, agent=True)


class HeredocProseTests(unittest.TestCase):
    def test_a_cat_heredoc_that_mentions_the_merge_command_passes(self):
        for cmd in ("gh pr create --title t --body-file - <<'EOF'\nCloses the gap. gh pr merge 12 stays blocked.\nEOF",
                    "git commit -F - <<'EOF'\nmention gh pr merge 12 and git push origin main\nEOF",
                    "gh pr comment 5 --body-file - <<EOF\nuse tools/pr_land.sh 5, not gh pr merge 5\nEOF",
                    "cat <<'EOF' > notes.md\ngit push origin main\nEOF",
                    "cat > notes.md <<'EOF'\ngh pr merge 12 is blocked\nEOF",
                    "cat <<EOF >> notes.md\nNever run gh pr merge\nEOF"):
            with self.subTest(cmd=cmd):
                self.assertIsNone(merge_guard.reason(cmd), cmd)

    def test_true_positives_stay_blocked(self):
        for cmd in ("cat <<'EOF'\ngh pr merge 12\nEOF", "gh pr create --body-file - <<'EOF' | bash\ngh pr merge 12\nEOF",
                    "gh pr create --body-file - <<'EOF'\n$(gh pr merge 1)\nEOF",
                    "gh pr merge 12", "git push origin main", "cat <<'EOF' | bash\ngh pr merge 12\nEOF",
                    "bash <<'EOF'\ngh pr merge 12\nEOF", "cat <<EOF\n$(gh pr merge 12)\nEOF",
                    "cat <<'EOF' > notes.md\nok\nEOF\ngh pr merge 12", "cat <<'EOF' > .git/hooks/pre-push\ngh pr merge 1\nEOF"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(merge_guard.reason(cmd), cmd)


class QuotedBodyTests(unittest.TestCase):
    """B1: the shell does not expand a quoted-delimiter heredoc body, so backticks and ``$(`` in it are text."""

    def test_a_brief_with_a_backticked_merge_followed_by_a_task_command_passes(self):
        """Fails if: the substitution scan runs on the whole command, so a backtick in a quoted body blocks the brief (exit 2 `gh pr merge`)."""
        for cmd in (f"cat > build/briefs/x.md <<'EOF'\nthen run `{MERGE}` when green\nEOF\npython3 tools/tasks.py new T-x",
                    f"cat > build/briefs/x.md <<'EOF' && python3 tools/tasks.py new T-x\nthen run `{MERGE}` when green\nEOF",
                    "cat > build/briefs/x.md <<'EOF'\nuse `gh pr merge 1`\nEOF",
                    "cat > f <<'EOF'\n`git push origin main` and `gh pr merge 1`\nEOF",
                    "cat > f <<'EOF'\n`gh api repos/SFenton/native-home/pulls/5/merge -X PUT` $(gh pr merge 1)\nEOF",
                    "cat <<\"EOF\" > f\n`gh pr merge 1`\nEOF"):
            with self.subTest(cmd=cmd):
                self.assertIsNone(verdict(cmd), cmd)

    def test_an_unquoted_body_the_shell_expands_stays_blocked(self):
        for cmd in ("cat > f <<EOF\n`gh pr merge 1`\nEOF", "cat > f <<EOF\n$(gh pr merge 1)\nEOF",
                    "cat <<EOF > f\n`gh pr merge 1`\nEOF", "cat > f <<EOF\nsafe\nEOF\ngh pr merge 1",
                    "cat > f <<'EOF' && gh pr merge 1\nx\nEOF", "cat <<'EOF' | bash\n`gh pr merge 1`\nEOF", "python3 - <<'EOF'\nrun('gh api -X PUT repos/o/n/pulls/5/merge')\nEOF",
                    "cat > f <<'EOF' && python3 tools/tasks.py new T-x $(gh pr merge 1)\nx\nEOF",
                    "gh pr create --body-file - <<'EOF'\n`gh pr merge 1`\nEOF"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(verdict(cmd), cmd)


class SedReadTests(unittest.TestCase):
    """B1: a read-only ``sed -n N,Mp`` is data, like ``head``."""

    def test_read_only_sed_with_a_grep_for_the_flag_passes(self):
        """Fails if: ``sed`` is not exempt, so the owner-sign-off text in the grep pattern blocks a read (exit 2 owner-ack)."""
        for cmd in (f"sed -n 1,20p tools/pr_land.py | grep -n '{FLAG}'", f"grep -n \"{FLAG}\" tools/pr_land.py",
                    f"git show HEAD:tools/pr_land.py | sed -n 1,20p | grep -n '{FLAG}'", "sed -n 497,520p f", "sed -n 5p f g",
                    "sed -n '3,$p' f", f"sed -n 1,20p tools/pr_land.py | grep -n 'gh pr merge'"):
            with self.subTest(cmd=cmd):
                self.assertIsNone(verdict(cmd), cmd)

    def test_the_flag_text_alone_is_still_refused_when_something_runs(self):
        for cmd in (f"python3 tools/pr_land.py 5 --{FLAG}", f"tools/pr_land.sh 5 --{FLAG}", f"echo hi | bash -c 'x --{FLAG}'"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(verdict(cmd), cmd)

    def test_sed_that_writes_or_runs_stays_blocked(self):
        for cmd in (f"sed -i s/a/b/ f; grep {FLAG} f; gh pr merge 1", f"sed -i 1p tools/pr_land.py | grep '{FLAG}'",
                    f"sed -n '1e gh pr merge 1' f | grep '{FLAG}'", f"sed -n 'w x' f | grep '{FLAG}'",
                    f"sed -n 1p f; gh pr merge 1", f"sed -n -e 1p f | grep '{FLAG}'", f"sed -n 1p -s f | grep '{FLAG}'",
                    f"sed -n -f script f | grep '{FLAG}'", f"sed 1p f | grep '{FLAG}'", f"sed -n 1,2w out f | grep '{FLAG}'"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(verdict(cmd), cmd)

    def test_sed_prints_only_accepts_a_print_script(self):
        self.assertTrue(merge_guard.sed_prints(["-n", "1,20p", "f"]))
        self.assertTrue(merge_guard.sed_prints(["-n", "7,$p"]))
        for args in ([], ["-n"], ["1,20p", "f"], ["-n", "1,20p", "-i", "f"], ["-n", "p"], ["-n", "1e echo", "f"], ["-ni", "1p", "f"]):
            self.assertFalse(merge_guard.sed_prints(args), args)


if __name__ == "__main__":
    unittest.main()
