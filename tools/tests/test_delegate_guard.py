"""Subprocess coverage for the T3 delegate_task review-admission contract."""

import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / "tools" / "hooks" / "delegate_guard.py"
SHA = "0123456789abcdef0123456789abcdef01234567"
DECLARATION = "\n".join((
    "review-kind: advisory plan review",
    "only-write: build/plans/factory-review-1.md",
    "authority: advisory-only",
    f"read-commit: {SHA}",
    "return: status block",
))


class DelegateGuardTests(unittest.TestCase):
    """Exercise the real hook input, exit code and stderr."""

    def run_hook(self, prompt, role="review"):
        """Run the hook as Claude does, with a real JSON payload on stdin."""
        tool_input = {"task": prompt}
        if role is not None:
            tool_input["role"] = role
        payload = {
            "tool_name": "mcp__t3-code__delegate_task",
            "tool_input": tool_input,
        }
        return subprocess.run(
            [sys.executable, str(HOOK)],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            cwd=str(ROOT),
        )

    def assert_allowed(self, prompt, role="review"):
        done = self.run_hook(prompt, role)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stderr, "")

    def assert_blocked_field(self, prompt, field, role="review"):
        done = self.run_hook(prompt, role)
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn(f"`{field}`", done.stderr)

    def test_s2_3_full_advisory_review_is_allowed(self):
        """S2.3: the full advisory declaration admits role review."""
        self.assert_allowed("Read the cited plan and return an advisory note.\n" + DECLARATION)

    def test_s2_4_a_missing_review_kind_names_field(self):
        """S2.4.a: prose words do not grant a missing review-kind."""
        declaration = DECLARATION.replace("review-kind: advisory plan review\n", "")
        self.assert_blocked_field(
            "The review kind is advisory plan review.\n" + declaration,
            "review-kind",
        )

    def test_s2_4_b_missing_only_write_names_field(self):
        """S2.4.b: a read citation does not grant a missing only-write."""
        declaration = DECLARATION.replace("only-write: build/plans/factory-review-1.md\n", "")
        self.assert_blocked_field(
            "Read build/plans/factory-review-1.md as source evidence.\n" + declaration,
            "only-write",
        )

    def test_s2_4_c_missing_authority_names_field(self):
        """S2.4.c: a prohibition does not infer the authority field."""
        declaration = DECLARATION.replace("authority: advisory-only\n", "")
        self.assert_blocked_field(
            "Never run tools/review/record.py.\n" + declaration,
            "authority",
        )

    def test_s2_4_d_missing_read_commit_names_field(self):
        """S2.4.d: an unrelated SHA does not grant read-commit."""
        declaration = DECLARATION.replace(f"read-commit: {SHA}\n", "")
        self.assert_blocked_field(
            "An earlier source was ffffffffffffffffffffffffffffffffffffffff.\n" + declaration,
            "read-commit",
        )

    def test_s2_4_e_missing_return_names_field(self):
        """S2.4.e: a prose status mention does not grant return."""
        declaration = DECLARATION.replace("return: status block", "")
        self.assert_blocked_field(
            "Finish by returning the status block.\n" + declaration,
            "return",
        )

    def test_s2_5_a_duplicate_only_write_is_blocked(self):
        """S2.5.a: two only-write declarations are refused."""
        prompt = (
            "only-write: build/plans/older-review-2.md\n"
            "Review the cited source.\n"
            + DECLARATION
        )
        self.assert_blocked_field(prompt, "only-write")

    def test_s2_5_b_output_outside_plans_is_blocked(self):
        """S2.5.b: matching filename outside build/plans is refused."""
        declaration = DECLARATION.replace(
            "build/plans/factory-review-1.md",
            "build/review/factory-review-1.md",
        )
        self.assert_blocked_field("Review.\n" + declaration, "only-write")

    def test_s2_5_c_unstructured_markdown_output_is_blocked(self):
        """S2.5.c: an arbitrary Markdown path under build/plans is refused."""
        declaration = DECLARATION.replace(
            "build/plans/factory-review-1.md",
            "build/plans/notes.md",
        )
        self.assert_blocked_field("Review.\n" + declaration, "only-write")

    def test_s2_5_d_noncanonical_output_path_is_blocked(self):
        """S2.5.d: a path with a parent component is refused."""
        declaration = DECLARATION.replace(
            "build/plans/factory-review-1.md",
            "build/plans/../plans/factory-review-1.md",
        )
        self.assert_blocked_field("Review.\n" + declaration, "only-write")

    def test_s2_5_e_two_output_paths_are_blocked(self):
        """S2.5.e: two whitespace-delimited output paths are refused."""
        declaration = DECLARATION.replace(
            "build/plans/factory-review-1.md",
            "build/plans/factory-review-1.md build/plans/other-review-2.md",
        )
        self.assert_blocked_field("Review.\n" + declaration, "only-write")

    def test_s2_5_f_read_citations_are_not_write_grants(self):
        """S2.5.f: cited older review paths do not become extra grants."""
        prompt = (
            "Read build/plans/first-review-2.md and build/plans/second-review-3.md; "
            "write only the declaration below.\n"
            + DECLARATION
        )
        self.assert_allowed(prompt)

    def test_s2_6_a_record_py_mention_is_allowed(self):
        """S2.6.a: an honest record.py prohibition does not revoke a declaration."""
        self.assert_allowed("Never run tools/review/record.py.\n" + DECLARATION)

    def test_s2_6_b_review_directory_mention_is_allowed(self):
        """S2.6.b: an honest build/review prohibition does not revoke a declaration."""
        self.assert_allowed("Do not write build/review/.\n" + DECLARATION)

    def test_s2_6_c_ship_mention_is_allowed(self):
        """S2.6.c: an honest ship.sh prohibition does not revoke a declaration."""
        self.assert_allowed("Do not invoke tools/ship.sh.\n" + DECLARATION)

    def test_s2_6_d_gh_pr_mention_is_allowed(self):
        """S2.6.d: an honest gh pr prohibition does not revoke a declaration."""
        self.assert_allowed("You may not use gh pr.\n" + DECLARATION)

    def test_s2_6_e_git_push_mention_is_allowed(self):
        """S2.6.e: an honest git push prohibition does not revoke a declaration."""
        self.assert_allowed("No git push is permitted.\n" + DECLARATION)

    def test_s2_6_f_pr_land_mention_is_allowed(self):
        """S2.6.f: an honest pr_land prohibition does not revoke a declaration."""
        self.assert_allowed("Never invoke tools/pr_land.sh.\n" + DECLARATION)

    def test_s2_6_g_authority_requires_exact_equality(self):
        """S2.6.g: authority rejects a value with an extra suffix."""
        declaration = DECLARATION.replace(
            "authority: advisory-only",
            "authority: advisory-only,ship",
        )
        self.assert_blocked_field("Review.\n" + declaration, "authority")

    def test_s2_7_a_research_role_remains_blocked(self):
        """S2.7.a: research is not an alias for review."""
        done = self.run_hook("Research.\n" + DECLARATION, "research")
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("research", done.stderr)

    def test_s2_7_b_design_role_remains_blocked(self):
        """S2.7.b: design is not an alias for review."""
        done = self.run_hook("Design.\n" + DECLARATION, "design")
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("design", done.stderr)

    def test_s2_7_c_test_role_remains_blocked(self):
        """S2.7.c: test is not an alias for review."""
        done = self.run_hook("Test.\n" + DECLARATION, "test")
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("test", done.stderr)

    def test_s2_7_d_general_role_remains_blocked(self):
        """S2.7.d: general is not an alias for review."""
        done = self.run_hook("General.\n" + DECLARATION, "general")
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("general", done.stderr)

    def test_s2_7_e_missing_role_remains_blocked(self):
        """S2.7.e: a complete declaration cannot supply an absent role."""
        done = self.run_hook("Review.\n" + DECLARATION, None)
        self.assertEqual(done.returncode, 2, done.stderr)
        self.assertIn("None", done.stderr)

    def test_s2_13_nonhex_commit_is_blocked(self):
        """S2.13: a 40-character nonhex commit is refused."""
        declaration = DECLARATION.replace(SHA, "g" * 40)
        self.assert_blocked_field("Review.\n" + declaration, "read-commit")

    def test_s2_14_duplicate_read_commit_is_blocked(self):
        """S2.14: two valid read-commit declarations are refused."""
        prompt = (
            f"read-commit: {'a' * 40}\n"
            "Review the cited source.\n"
            + DECLARATION
        )
        self.assert_blocked_field(prompt, "read-commit")


if __name__ == "__main__":
    unittest.main()
