"""``tools/hooks/merge_guard.py``: text that merely mentions a merge command in a ``cat`` heredoc runs nothing (#370)."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "hooks"))
import merge_guard  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()
