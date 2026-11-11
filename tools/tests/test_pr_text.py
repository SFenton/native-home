"""``tools/pr_text.py``: plain pull request titles and bodies, the composer, the title from a Summary, and the labels.

The fixtures are the real titles of native-home PRs #53 to #68 and the worked examples from the pull-request timeline research.
"""

import contextlib
import importlib.util
import io
import json
import os
import re
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
spec = importlib.util.spec_from_file_location("pr_text", TOOLS / "pr_text.py")
pr_text = importlib.util.module_from_spec(spec)
sys.modules["pr_text"] = pr_text
spec.loader.exec_module(pr_text)

#: PR number to title, as listed by ``gh pr list -R SFenton/native-home --state all`` (public). #64 to #67 were not
#: pull requests in that listing, so they are left out.
REAL_TITLES = {
    53: "Triage: verify merged-PR base moves (with the (#N) fallback) and let agents run ack-verified",
    54: "lane_check: Jev and branch-change overlap checks before review",
    55: "ci_wait and pr_land name why a PR is blocked; owner-only landing steps",
    56: "Release health: one issue each for no tag in 7 days, a failed release and a certificate under 45 days",
    57: "pr-checks: shard core tool tests, skip them for app-only diffs, build once and Smoke three families in parallel",
    58: "Fix red main: tests race the 10 s command timeout when the full suite stalls",
    59: "Add the T3 launcher behind agent.launcher (default claude)",
    60: "Route orchestrators and Designer to Fable 5.2 medium",
    61: "Nightly certification on hosted macOS: scheduled journeys and coverage, self-hosted scripts retired",
    62: "Agent model hook: built-ins that inherit the parent model name one; research-note escalates on Fable",
    63: "pr-checks: full swift test for Core and Design, hosted changed-file coverage, main runs never cancelled, red-main issue closes itself",
    68: "Stop measuring UX line coverage: logic gate only",
}
#: Titles from the research note's worked examples, plus the plain real ones.
GOOD_TITLES = [
    "Make pull request checks faster for changes to the app only",
    "Page tools stay clear of the fold on iPhone Duo (#142)",
    REAL_TITLES[59],
    REAL_TITLES[60],
]

SUMMARY_57 = """Checks on a pull request now take about 19 minutes for an app change. They took 31 to 41.
The tool tests run in 4 parts at the same time. The app builds once, and the iPhone, iPhone Duo and iPad checks run together.
Tool tests do not run when only app files change.
"""
TESTS_57 = """- unit (tools): split of the tool tests into 4 parts, each about 1 minute (pass)
- CI (macOS): build once, then Smoke on iPhone, iPhone Duo and iPad (pass)
- review: passed in round 3 at 3297487
"""
SUMMARY_DUO = """On iPhone Duo, the Sort and Filter buttons no longer sit on the fold. They move to the free side when you open or close the phone.
Other phones and iPad look the same as before.
"""
TESTS_DUO = """- unit (HassUI): hinge policy for page tools (added, pass)
- UI (iPhone Duo): fold and unfold journey (added, pass)
- accessibility (iPhone Duo): reading order, 44 pt targets, largest text (added, pass)
"""
EVIDENCE_DUO = "| Before | After |\n|---|---|\n| ![Before: Sort crosses the fold. Demo data, iPhone Duo.](b.png) | ![After: Sort stays left. Demo data, iPhone Duo.](a.png) |\n"


def body(summary="Pages load faster on iPhone.", tests="- unit (HassCore): cache test (pass)"):
    return f"## Summary\n{summary}\n\n## Tests\n{tests}\n"


def errors_of(text):
    return pr_text.body_problems(text)[0]


def warnings_of(text):
    return pr_text.body_problems(text)[1]


def run_cli(*argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = pr_text.main(list(argv))
        except SystemExit as exit_:
            code = exit_.code
    return code, out.getvalue(), err.getvalue()


class TitleTests(unittest.TestCase):
    def test_long_tool_style_real_titles_fail(self):
        """Fails if: a real changelog-style title (#53 to #57, #61 to #63, #68) passes the title check."""
        for number in (53, 54, 55, 56, 57, 61, 62, 63, 68):
            with self.subTest(pr=number):
                self.assertTrue(pr_text.title_problems(REAL_TITLES[number]), REAL_TITLES[number])

    def test_plain_titles_pass(self):
        """Fails if: a plain one-sentence title (the research examples, #59, #60) is refused."""
        for title in GOOD_TITLES:
            with self.subTest(title=title):
                self.assertEqual(pr_text.title_problems(title), [])

    def test_length_limit_is_seventy(self):
        """Fails if: 70 characters is refused, or 71 is allowed."""
        self.assertEqual(pr_text.title_problems("a" * 70), [])
        self.assertTrue(any("71 characters" in p for p in pr_text.title_problems("a" * 71)))

    def test_prefix_semicolon_and_commas(self):
        """Fails if: a 'word:' prefix, a semicolon, or a second comma is allowed."""
        self.assertTrue(any("prefix" in p for p in pr_text.title_problems("tools: make it faster")))
        self.assertTrue(any("semicolon" in p for p in pr_text.title_problems("Fix the bar; fix the baz")))
        self.assertTrue(any("comma" in p for p in pr_text.title_problems("Fix a, fix b, fix c")))
        self.assertEqual(pr_text.title_problems("Fix a, then fix b"), [])

    def test_banned_words_labels_backticks_paths(self):
        """Fails if: a banned word, an internal label, a backtick or a file path in a title is allowed."""
        for title in ("Leverage the cache", "We ensure it works", "Phase 4 cleanup of tiles", "Lane P4c lands tiles",
                      "Close T-gh-native-gate for good", "Use `cache` for tiles", "Edit tools/ship.sh to retry",
                      "Make ship.sh retry"):
            with self.subTest(title=title):
                self.assertTrue(pr_text.title_problems(title), title)

    def test_request_suffix_allowed_and_empty_refused(self):
        """Fails if: a trailing (#N) is refused, or an empty title passes."""
        self.assertEqual(pr_text.title_problems("Tiles keep their size (#12)"), [])
        self.assertEqual(pr_text.title_problems("  "), ["title is empty"])

    def test_cli_exit_codes_and_one_line_per_problem(self):
        """Fails if: title-check exits 0 on a bad title, or prints other than one 'error:' line per problem."""
        code, out, _ = run_cli("title-check", "tools: a; b, c, d")
        self.assertEqual(code, 1)
        self.assertEqual(len(out.splitlines()), len(pr_text.title_problems("tools: a; b, c, d")))
        self.assertTrue(all(line.startswith("error: ") for line in out.splitlines()))
        self.assertEqual(run_cli("title-check", GOOD_TITLES[0])[0], 0)


class BodyTests(unittest.TestCase):
    def test_bare_old_template_fails(self):
        """Fails if: the old pull request template, unfilled, passes body-check."""
        template = REPO / ".github" / "pull_request_template.md"
        if not template.exists():
            self.skipTest("template not present")
        text = template.read_text(encoding="utf-8")
        if "[" not in text and "## Summary" in text and "## Tests" in text:
            self.skipTest("template already replaced by a plain one")
        self.assertTrue(errors_of(text))
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.md"
            path.write_text(text, encoding="utf-8")
            self.assertEqual(run_cli("body-check", str(path))[0], 1)

    def test_old_template_text_embedded_in_a_body_fails(self):
        """Fails if: a body with both headings but the old template's instruction strings or [..] fields passes."""
        text = body("[What and why, rung-0 note link]", "- tests [tests]") + "<!-- Commands and results. -->"
        problems = errors_of(text)
        self.assertTrue(any("square brackets" in p for p in problems))
        self.assertTrue(any("Commands and results." in p for p in problems))

    def test_links_checkboxes_and_code_are_not_placeholders(self):
        """Fails if: a markdown link, a checkbox or bracketed text in code is read as a placeholder."""
        text = body("See the [note](build/n.md) for why.", "- [x] unit (tools): checks (pass)\n- run `a[0]` once")
        self.assertEqual(errors_of(text), [])

    def test_missing_and_empty_sections(self):
        """Fails if: a missing or empty Summary or Tests is not an error."""
        self.assertTrue(any("missing section: ## Tests" in p for p in errors_of("## Summary\nIt works.\n")))
        self.assertTrue(any("empty section: ## Summary" in p for p in errors_of("## Summary\n\n## Tests\n- a (pass)\n")))
        self.assertTrue(any("empty section: ## Tests" in p for p in errors_of("## Summary\nIt works.\n\n## Tests\n<!-- x -->\n")))

    def test_first_sentence_labels_paths_backticks(self):
        """Fails if: Phase N, a path or a backtick in the first Summary sentence is not an error, or one in sentence two is."""
        for first in ("Phase 4 lands the cache.", "Lane P4c lands the cache.", "T-pr-timeline lands the cache.",
                      "The change edits tools/ship.sh.", "The `cache` is faster."):
            with self.subTest(first=first):
                self.assertTrue(errors_of(body(first + " It helps.")), first)
        self.assertEqual(errors_of(body("The cache is faster. It lives in `tools/ship.sh`.")), [])

    def test_long_summary_paragraph_is_an_error(self):
        """Fails if: a 7-sentence Summary paragraph is allowed, or 6 sentences are refused."""
        six = " ".join(f"Point {i} is clear." for i in range(6))
        self.assertEqual(errors_of(body(six)), [])
        self.assertTrue(any("7 sentences" in p for p in errors_of(body(six + " Point 7 is clear."))))

    def test_style_rules_warn_and_do_not_error(self):
        """Fails if: a long sentence, passive voice, progressive tense, 'and then' or a banned word is missed, or is an error."""
        cases = {
            "long": " ".join(["word"] * 26) + ".",
            "passive": "The cache was cleared by the app.",
            "progressive": "The app is running the check.",
            "then": "Open the page and then tap Save.",
            "banned": "This makes the tiles robust.",
        }
        for name, text in cases.items():
            with self.subTest(rule=name):
                self.assertEqual(errors_of(body(text)), [])
                self.assertTrue(warnings_of(body(text)), name)

    def test_list_items_use_the_shorter_limit(self):
        """Fails if: 21 words in a list item pass, or 21 words in prose warn."""
        twenty_one = " ".join(["word"] * 21)
        self.assertTrue(any("limit is 20" in w for w in warnings_of(body(tests="- " + twenty_one + "."))))
        self.assertEqual([w for w in warnings_of(body(twenty_one + ".")) if "words" in w], [])

    def test_strict_turns_warnings_into_failure(self):
        """Fails if: --strict exits 0 with a warning, or no flag exits non-zero with only a warning."""
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.md"
            path.write_text(body("Open the page and then tap Save."), encoding="utf-8")
            code, out, _ = run_cli("body-check", str(path))
            self.assertEqual(code, 0)
            self.assertIn("warning:", out)
            self.assertEqual(run_cli("body-check", str(path), "--strict")[0], 1)

    def test_unlinted_regions_are_skipped(self):
        """Fails if: text in details, a code fence, an HTML comment or a marker block is style-linted."""
        bad = "This is robust and then it was cleared by the app."
        text = (body("Pages load faster. They use a cache.") + f"\n<details><summary>More</summary>\n\n{bad}\n\n</details>\n\n```\n{bad}\n```\n\n<!-- {bad} -->\n"
                + f"<!-- sh-status:start -->\n{bad}\n<!-- sh-status:end -->\n<!-- review:start -->\n{bad}\n<!-- review:end -->\n")
        self.assertEqual(warnings_of(text), [])
        self.assertEqual(errors_of(text), [])

    def test_fenced_heading_does_not_count(self):
        """Fails if: a '## Tests' line inside a code fence satisfies the Tests section."""
        text = "## Summary\nIt works.\n\n```\n## Tests\n- x\n```\n"
        self.assertTrue(any("missing section: ## Tests" in p for p in errors_of(text)))


class ReviewRound1Tests(unittest.TestCase):
    def test_extra_visible_sections_are_errors(self):
        """Fails if: a body with a visible 'Why and how (for engineers)' or 'Checklist' section passes body-check."""
        text = body("It works now. It is faster.") + "\n## Why and how (for engineers)\nDetails.\n\n## Checklist\n- [ ] done\n"
        problems = errors_of(text)
        self.assertTrue(any("Why and how" in p for p in problems))
        self.assertTrue(any("Checklist" in p for p in problems))

    def test_extra_sections_inside_exempt_regions_are_fine(self):
        """Fails if: a '##' heading inside details, a fence, a comment or a marker block is refused, or Evidence is."""
        text = (body("It works now. It is faster.") + "\n## Evidence\n![a](a.png)\n\n<details><summary>x</summary>\n\n## Notes\n\n</details>\n\n"
                "```\n## Code\n```\n\n<!-- ## Hidden -->\n<!-- sh-status:start -->\n## Status\n<!-- sh-status:end -->\n")
        self.assertEqual(errors_of(text), [])

    def test_wrapped_first_sentence_is_read_whole(self):
        """Fails if: a Summary sentence wrapped over two lines is cut at the break, or its label on line two is missed."""
        text = body("Checks on a pull request now take\nabout 19 minutes in Phase 4. It helps.")
        self.assertEqual(pr_text.first_summary_sentence(text), "Checks on a pull request now take about 19 minutes in Phase 4.")
        self.assertTrue(any("internal label" in p for p in errors_of(text)))
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.md"
            path.write_text(body("Tiles keep their size when you\nrotate the phone. It helps."), encoding="utf-8")
            self.assertEqual(run_cli("title-from", str(path)), (0, "Tiles keep their size when you rotate the phone\n", ""))

    def test_title_from_prints_only_a_passing_title_without_emphasis(self):
        """Fails if: title-from prints a title that title-check refuses, keeps '**', or leaves a trailing '?' or '!'."""
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.md"
            path.write_text(body("Pages: the **new** layout, with tiles, wins. It helps."), encoding="utf-8")
            code, out, err = run_cli("title-from", str(path))
            self.assertEqual((code, out), (1, ""))
            self.assertIn("error:", err)
            path.write_text(body("The **new** layout keeps tiles in place! It helps."), encoding="utf-8")
            self.assertEqual(run_cli("title-from", str(path))[1], "The new layout keeps tiles in place\n")

    def test_code_fences_and_alerts_are_not_placeholders(self):
        """Fails if: TODO in a code span or fence, a GitHub alert, or a reference link is read as placeholder text."""
        text = body("Tiles keep size. See [the note][ref] for why.\n\n> [!NOTE]\n> The `TODO` marker stays.\n\n```\nTODO\n```",
                    "- unit (tools): checks (pass)")
        self.assertEqual(errors_of(text), [])
        self.assertTrue(errors_of(body("TODO write this. It helps.")))

    def test_tests_section_without_words_is_empty(self):
        """Fails if: a Tests section of a bare dash or empty bullets counts as filled."""
        for tests in ("-", "- \n-", "* "):
            with self.subTest(tests=tests):
                self.assertTrue(any("empty section: ## Tests" in p for p in errors_of(body(tests=tests))))

    def test_summary_sentence_count_is_a_warning(self):
        """Fails if: 1 or 5 Summary sentences give no warning, 2 to 4 give one, or it is an error."""
        for count, warns in ((1, True), (2, False), (4, False), (5, True)):
            text = body(" ".join(f"Point {i} holds." for i in range(count)))
            with self.subTest(count=count):
                self.assertEqual(any("Summary has" in w for w in warnings_of(text)), warns)
                self.assertEqual(errors_of(text), [])


class ComposeTests(unittest.TestCase):
    def test_worked_examples_have_no_errors(self):
        """Fails if: a composed worked example (PR #57 rewrite, the Duo visual PR) has any body-check error."""
        for summary, tests, evidence in ((SUMMARY_57, TESTS_57, ""), (SUMMARY_DUO, TESTS_DUO, EVIDENCE_DUO)):
            text = pr_text.compose(summary, tests, evidence)
            self.assertEqual(errors_of(text), [])

    def test_shape_headings_and_markers(self):
        """Fails if: Evidence appears without a file, a hidden marker pair other tools find is missing, or placeholder text appears."""
        text = pr_text.compose(SUMMARY_57, TESTS_57)
        self.assertEqual(text.count("\n## "), 1)
        self.assertTrue(text.startswith("## Summary\n"))
        self.assertNotIn("## Evidence", text)
        for pair in ("<!-- sh-timeline:start -->\n<!-- sh-timeline:end -->", "<!-- sh-status:start -->\n<!-- sh-status:end -->",
                     "<!-- review:start -->\n<!-- review:end -->"):
            self.assertIn(pair, text)
        self.assertNotIn("- [ ]", text)
        self.assertEqual(pr_text.placeholder_problems(text, pr_text.load_words()), [])
        self.assertIn("## Evidence", pr_text.compose(SUMMARY_DUO, TESTS_DUO, EVIDENCE_DUO))

    def test_no_status_text_and_no_review_block_is_shown(self):
        """Fails if: a composed body shows status text ("Drafting" or any other), a "Review verdict" details block or anything
        else below Tests, ``compose`` still takes a status, or a body without those is refused by body-check."""
        for evidence in ("", EVIDENCE_DUO):
            text = pr_text.compose(SUMMARY_DUO, TESTS_DUO, evidence)
            seen = re.sub(r"<!--.*?-->", "", text, flags=re.S)
            for word in ("Drafting", "Review verdict", "<details", "Status", "Waiting on"):
                self.assertNotIn(word, seen)
            self.assertEqual(seen.split("## Tests\n")[1].split("## Evidence\n")[0].strip(), TESTS_DUO.strip())
            self.assertEqual(errors_of(text), [])
        with self.assertRaises(TypeError):
            pr_text.compose(SUMMARY_57, TESTS_57, status="Ready")
        with TemporaryDirectory() as tmp:
            s, t = Path(tmp) / "s.md", Path(tmp) / "t.md"
            s.write_text(SUMMARY_57, encoding="utf-8")
            t.write_text(TESTS_57, encoding="utf-8")
            with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
                pr_text.main(["compose", "--summary-file", str(s), "--tests-file", str(t), "--status", "Drafting"])

    def test_evidence_needs_a_picture_of_its_own(self):
        """Fails if: an ``## Evidence`` section that only links to pictures in the comments (or holds only words, or a picture
        only inside an HTML comment) passes body-check or is composed, or one with an image, an ``<img>`` tag, a ``<video>``
        tag or an uploaded asset on its own line is refused."""
        linked = ["See the pictures in [the Verifier's comment](https://github.com/o/r/pull/7#issuecomment-1).",
                  "- Before and after are in the comments.", "<!-- ![hidden](a.png) -->\nPictures are in the comments."]
        own = [EVIDENCE_DUO, '<img src="https://github.com/user-attachments/assets/ab-1" alt="After, iPhone" width="280">',
               '<video src="https://github.com/user-attachments/assets/ab-2" width="280" controls></video>',
               "https://github.com/user-attachments/assets/ab-3"]
        for evidence in linked:
            text = body() + f"\n## Evidence\n{evidence}\n"
            self.assertTrue(any("holds no picture of its own" in e for e in errors_of(text)), evidence)
        for evidence in own:
            self.assertEqual(errors_of(body() + f"\n## Evidence\n{evidence}\n"), [], evidence)
        self.assertEqual(errors_of(body()), [])
        with TemporaryDirectory() as tmp:
            s, t, e = Path(tmp) / "s.md", Path(tmp) / "t.md", Path(tmp) / "e.md"
            s.write_text(SUMMARY_57, encoding="utf-8")
            t.write_text(TESTS_57, encoding="utf-8")
            e.write_text(linked[0], encoding="utf-8")
            code, out, _ = run_cli("compose", "--summary-file", str(s), "--tests-file", str(t), "--evidence-file", str(e))
            self.assertEqual((code, out), (1, ""))
            e.write_text(own[1], encoding="utf-8")
            code, out, _ = run_cli("compose", "--summary-file", str(s), "--tests-file", str(t), "--evidence-file", str(e))
            self.assertEqual(code, 0)
            self.assertIn("## Evidence\n" + own[1], out)

    def test_request_lines_match_what_the_gate_reads(self):
        """Fails if: the quote or trailer lines do not match lane_land's OWNER_QUOTE and OWNER_REQUEST patterns."""
        spec_ = importlib.util.spec_from_file_location("lane_land_for_pr_text", TOOLS / "lane_land.py")
        lane_land = importlib.util.module_from_spec(spec_)
        sys.modules["lane_land_for_pr_text"] = lane_land
        spec_.loader.exec_module(lane_land)
        text = pr_text.compose(SUMMARY_DUO, TESTS_DUO, request="142", quote="keep the page tools off the fold on the Duo")
        self.assertEqual(lane_land.OWNER_REQUEST.findall(text), ["#142"])
        self.assertEqual([q.strip() for q in lane_land.OWNER_QUOTE.findall(text)], ['"keep the page tools off the fold on the Duo"'])
        self.assertEqual(errors_of(text), [])
        self.assertNotIn("Owner", pr_text.compose(SUMMARY_DUO, TESTS_DUO))

    def test_cli_compose_refuses_empty_input(self):
        """Fails if: compose prints a body from an empty tests file."""
        with TemporaryDirectory() as tmp:
            s, t = Path(tmp) / "s.md", Path(tmp) / "t.md"
            s.write_text(SUMMARY_57, encoding="utf-8")
            t.write_text("\n", encoding="utf-8")
            code, out, _ = run_cli("compose", "--summary-file", str(s), "--tests-file", str(t))
            self.assertEqual((code, out), (1, ""))
            t.write_text(TESTS_57, encoding="utf-8")
            code, out, _ = run_cli("compose", "--summary-file", str(s), "--tests-file", str(t), "--request", "#7")
            self.assertEqual(code, 0)
            self.assertIn("Owner-Request: #7", out)


class TitleFromTests(unittest.TestCase):
    def test_first_sentence_without_final_period(self):
        """Fails if: the title keeps the period, takes the second sentence, or comes from outside Summary."""
        text = pr_text.compose(SUMMARY_57, TESTS_57)
        self.assertEqual(pr_text.first_summary_sentence(text), "Checks on a pull request now take about 19 minutes for an app change.")
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.md"
            path.write_text("## Summary\nTiles keep their size.\nThey did not before.\n\n## Tests\n- a (pass)\n", encoding="utf-8")
            code, out, _ = run_cli("title-from", str(path))
            self.assertEqual((code, out), (0, "Tiles keep their size\n"))

    def test_over_seventy_characters_exits_one(self):
        """Fails if: a first sentence over 70 characters becomes a title."""
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.md"
            path.write_text(f"## Summary\n{'Word ' * 20}ends here.\n\n## Tests\n- a (pass)\n", encoding="utf-8")
            code, out, err = run_cli("title-from", str(path))
            self.assertEqual((code, out), (1, ""))
            self.assertIn("limit is 70", err)

    def test_no_summary_exits_one(self):
        """Fails if: a body with no Summary yields a title."""
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.md"
            path.write_text("## Tests\n- a (pass)\n", encoding="utf-8")
            self.assertEqual(run_cli("title-from", str(path))[0], 1)


class LabelTests(unittest.TestCase):
    def test_area_for_real_paths(self):
        """Fails if: a real repo path maps to the wrong area."""
        table = pr_text.load_words()["areas"]
        expected = {
            "apple/Sources/HassUI/UIKitPort/Foo.swift": "uikit",
            "apple/Sources/HassCore/Rooms/Rooms.swift": "core",
            "apple/Sources/HassDesign/HassModal.swift": "design",
            "apple/Apps/Widgets/FentonHomeWidgets.swift": "widgets",
            "apple/Sources/FentonActivityViews/ActivityBar.swift": "widgets",
            "apple/Apps/watchOS/FentonHomeWatchApp.swift": "watch",
            "apple/Apps/iOSTests/UKHostedGridTests.swift": "uikit",
            "tools/pr_text.py": "tools",
            "tools/ci_shard.py": "ci",
            "tools/apple_coverage.sh": "ci",
            ".github/workflows/pr-checks.yml": "ci",
            ".agents/workflow/ci.md": "agents",
            ".claude/agents/reviewer.md": "agents",
            "AGENTS.md": "agents",
            "README.md": "docs",
            "contracts/patterns.json": "docs",
        }
        for path, area in expected.items():
            with self.subTest(path=path):
                self.assertEqual(pr_text.area_for(path, table), area)
        self.assertIsNone(pr_text.area_for("apple/Apps/iOSX/a.swift", [["apple/Apps/iOS", "uikit"]]))
        self.assertIsNone(pr_text.area_for("LICENSE", table))

    def test_at_most_three_areas_most_files_first(self):
        """Fails if: more than 3 area labels appear, or the order is not most files first with ties by name."""
        paths = (["tools/a.py", "tools/b.py", "tools/c.py"] + ["apple/Sources/HassCore/x.swift", "apple/Sources/HassCore/y.swift"]
                 + ["apple/Sources/HassDesign/z.swift", ".agents/a.md", ".github/w.yml", "LICENSE"])
        self.assertEqual(pr_text.area_labels(paths), ["area:tools", "area:core", "area:agents"])

    def test_device_labels(self):
        """Fails if: a device maps to the wrong label, a duplicate repeats, or a Mac or unknown token is accepted."""
        self.assertEqual(pr_text.device_labels("iphone,duo,ipad,iphone"), ["iPhone", "iPhone Duo", "iPad"])
        self.assertEqual(pr_text.device_labels(""), [])
        for bad in ("mac", "macos", "watch"):
            with self.assertRaises(ValueError):
                pr_text.device_labels(bad)

    def test_cli_labels_from_a_real_git_diff(self):
        """Fails if: labels does not print type, devices, then areas from `git diff base...head`, one per line."""
        with TemporaryDirectory() as tmp:
            env = {**os.environ, "HOME": tmp, "XDG_CONFIG_HOME": tmp, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                   "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
            work = Path(tmp) / "repo"
            work.mkdir()

            def git(*args):
                subprocess.run(["git", *args], cwd=work, env=env, capture_output=True, text=True, check=True)

            git("init", "-q", "-b", "main")
            (work / "README.md").write_text("x", encoding="utf-8")
            git("add", "-A")
            git("commit", "-q", "-m", "base")
            git("checkout", "-q", "-b", "topic")
            for rel in ("tools/a.py", "tools/b.py", "apple/Sources/HassUI/UIKitPort/V.swift"):
                (work / rel).parent.mkdir(parents=True, exist_ok=True)
                (work / rel).write_text("x", encoding="utf-8")
            git("add", "-A")
            git("commit", "-q", "-m", "change")
            old = os.getcwd()
            os.chdir(work)
            try:
                code, out, _ = run_cli("labels", "--base", "main", "--type", "Feature", "--devices", "duo,ipad")
                bad, _, err = run_cli("labels", "--base", "nope")
            finally:
                os.chdir(old)
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines(), ["Feature", "iPhone Duo", "iPad", "area:tools", "area:uikit"])
        self.assertEqual(bad, 2)
        self.assertIn("error:", err)


class DataFileTests(unittest.TestCase):
    def test_data_file_has_every_table_and_valid_regexes(self):
        """Fails if: the owner-edited data file loses a key, holds a pattern that does not compile, or maps a Mac area."""
        words = json.loads((TOOLS / "pr_text_words.json").read_text(encoding="utf-8"))
        for key in ("banned_stems", "banned_phrases", "internal_labels", "areas", "placeholder_strings", "marker_blocks",
                    "path_roots", "path_extensions", "irregular_participles", "progressive_allow"):
            self.assertTrue(words[key], key)
        for pattern in words["internal_labels"]:
            re.compile(pattern)
        self.assertNotIn("mac", json.dumps([a for _, a in words["areas"]]).lower())

    def test_edited_word_list_changes_the_result(self):
        """Fails if: title_problems ignores the words dict it is given."""
        words = {**pr_text.load_words(), "banned_stems": ["tile"]}
        self.assertTrue(pr_text.title_problems("Tiles keep their size", words))
        self.assertEqual(pr_text.title_problems("Tiles keep their size"), [])


if __name__ == "__main__":
    unittest.main()
