"""``tools/hooks/merge_guard.py``: the owner-ack, ack-base, ack-verified and land-word checks read command words, not text a command only
carries (a heredoc body, a quoted ``--body`` or ``printf`` argument). The table rows in ``guard_tables/merge_guard.tsv`` replay the verdicts."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
import merge_guard  # noqa: E402

#: The owner sign-off flag, built here so this source never spells it out.
FLAG = "--owner" + "-ack"


class CommandWordsTests(unittest.TestCase):
    def test_text_a_data_command_carries_is_removed(self):
        """Fails if: a heredoc body or a quoted argument of cat, printf, echo or gh pr comment is still matched as a command word."""
        for cmd in (f"cat > f <<'EOF'\npr_land {FLAG}\nEOF", f"gh pr comment 3 --body \"pr_land {FLAG}\"",
                    f"printf 'pr_land {FLAG}' > f", f"gh issue create --body 'ack-base'", f"cat > f <<EOF\nlane_land {FLAG}\nEOF"):
            with self.subTest(cmd=cmd):
                words = merge_guard.command_words(cmd)
                self.assertNotIn("pr_land", words)
                self.assertNotIn("lane_land", words)
                self.assertNotIn("ack-base", words)
                self.assertNotIn("owner-ack", words)

    def test_anything_that_could_run_its_text_is_kept(self):
        """Fails if: a shell string, eval, python -c, a substitution, or a heredoc or pipe into a shell or interpreter is stripped."""
        for cmd in (f"bash -c 'tools/pr_land.sh 1 {FLAG}'", f"eval 'pr_land {FLAG}'", f"python3 -c 'pr_land'",
                    f"echo \"$(pr_land {FLAG})\"", f"echo `pr_land`", "bash <<'EOF'\npr_land\nEOF", "bash <<EOF\npr_land\nEOF",
                    "echo pr_land | sh", "echo 'pr_land' | python3 -", "cat > f <<EOF\n$(pr_land)\nEOF",
                    "python3 <<'EOF'\npr_land\nEOF", "cat <<'EOF' | bash\npr_land\nEOF",
                    "echo pr_land |& sh", "echo pr_land | (sh)", "echo pr_land | { sh; }", "echo pr_land |\npython3 -",
                    "echo $'\\'' ; pr_land #'", "echo '<<EOF'\npr_land\nEOF",
                    "cat > f <<'EOF'\npr_land\nEOF\nbash f", "cat > f <<'EOF'\npr_land\nEOF\n. f", "printf -v X 'pr_land'"):
            with self.subTest(cmd=cmd):
                self.assertIn("pr_land", merge_guard.command_words(cmd))

    def test_the_command_after_the_data_command_is_kept(self):
        """Fails if: a command that follows a data command or heredoc is stripped with it."""
        self.assertIn("pr_land", merge_guard.command_words(f"echo 'x'; tools/pr_land.sh 5 {FLAG}"))
        self.assertIn("pr_land", merge_guard.command_words(f"cat > f <<'EOF'\nx\nEOF\ntools/pr_land.sh 5 {FLAG}"))

    def test_an_unreadable_command_is_kept_whole(self):
        """Fails if: an open quote or unclosed heredoc is stripped instead of kept whole."""
        for cmd in ("echo 'pr_land", "cat > f <<'EOF'\npr_land\n"):
            with self.subTest(cmd=cmd):
                self.assertIn("pr_land", merge_guard.command_words(cmd))


if __name__ == "__main__":
    unittest.main()
