"""Tests for the inert pull-request bridge. No network, subprocess or clock is used."""
from __future__ import annotations

import copy
import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import pr_bridge as bridge  # noqa: E402

REPO = "SFenton/native-home"
HEAD = "1" * 40
REVIEWED_HEAD = "2" * 40
MERGE_SHA = "3" * 40
BASE_SHA = "4" * 40
OTHER_SHA = "5" * 40


def open_pull(**changes):
    pull = {
        "number": 203,
        "state": "OPEN",
        "mergedAt": None,
        "mergeCommit": None,
        "headRefOid": HEAD,
        "headRefName": "agents/factory-owner-held",
        "baseRefName": "main",
        "isDraft": False,
        "isCrossRepository": False,
        "author": {"login": "sfenton-agent"},
        "reviewDecision": "REVIEW_REQUIRED",
        "mergeStateStatus": "BLOCKED",
        "mergeable": "MERGEABLE",
        "files": [{"path": "tools/triage/pr_bridge.py"}],
        "statusCheckRollup": [
            {
                "name": "pr-checks",
                "status": "COMPLETED",
                "conclusion": "SUCCESS",
                "startedAt": "2026-11-21T20:00:00Z",
            },
            {
                "name": "ai-review",
                "status": "COMPLETED",
                "conclusion": "SUCCESS",
                "startedAt": "2026-11-21T20:01:00Z",
            },
        ],
        "createdAt": "2026-11-21T19:00:00Z",
    }
    pull.update(changes)
    return pull


def closed_unmerged_pull(**changes):
    pull = open_pull(
        number=202,
        state="CLOSED",
        headRefName="agents/factory-closed",
        mergeStateStatus="DIRTY",
        statusCheckRollup=[],
    )
    pull.update(changes)
    return pull


def merged_pull(**changes):
    pull = open_pull(
        number=199,
        state="MERGED",
        mergedAt="2026-11-21T18:30:00Z",
        mergeCommit={"oid": MERGE_SHA},
        headRefOid=HEAD,
        headRefName="agents/factory-squash",
        reviewDecision="APPROVED",
        mergeStateStatus="CLEAN",
    )
    pull.update(changes)
    return pull


def web_flow_commit(**changes):
    commit = {
        "sha": MERGE_SHA,
        "parents": [{"sha": BASE_SHA}],
        "committer": {"login": "web-flow"},
        "commit": {
            "verification": {"verified": True, "reason": "valid"},
            "message": "Ship the bridge (#199)",
        },
    }
    commit.update(changes)
    return commit


def approval(head=HEAD, login="SFenton", state="APPROVED", index=1):
    return {
        "id": index,
        "user": {"login": login},
        "state": state,
        "commit_id": head,
        "submitted_at": f"2026-11-21T20:0{index}:00Z",
    }


class FakeReader:
    def __init__(self, pull=None, reviews=None, commit=None, associated_pulls=None):
        self.pull = copy.deepcopy(pull or open_pull())
        self.reviews = copy.deepcopy(reviews or [])
        self.commit = copy.deepcopy(commit or web_flow_commit())
        self.associated_pulls = copy.deepcopy(
            associated_pulls if associated_pulls is not None else [self.pull]
        )
        self.calls = []

    def __call__(self, argv):
        args = list(argv)
        self.calls.append(args)
        if args[:2] == ["pr", "view"]:
            return copy.deepcopy(self.pull)
        endpoint = args[1] if len(args) >= 2 else ""
        if args[-1:] == ["--paginate"] and "/reviews" in endpoint:
            return copy.deepcopy(self.reviews)
        if endpoint.endswith("/pulls"):
            return copy.deepcopy(self.associated_pulls)
        if "/commits/" in endpoint:
            return copy.deepcopy(self.commit)
        raise AssertionError("unexpected reader call: {!r}".format(args))


class PullShapeTests(unittest.TestCase):
    def test_b1_02_a_accepts_branch_only_pulls(self):
        result = bridge.normalize_status(
            {"lanes": [], "pulls": [{"branch": "agents/factory-branch-only"}]}
        )
        self.assertEqual(result["records"], [{"branch": "agents/factory-branch-only"}])
        self.assertEqual([item["disposition"] for item in result["dispositions"]],
                         ["accepted"])

    def test_b1_02_b_reports_unknown_object_keys(self):
        branch = "agents/factory-unknown-key"
        invalid = {"branch": branch, "pr": 7, "head": HEAD, "url": "https://example.test"}
        result = bridge.normalize_status({"pulls": [invalid, {"branch": branch}]})
        self.assertEqual(result["records"], [{"branch": branch}])
        self.assertEqual(result["dispositions"][0]["disposition"], "invalid")
        self.assertEqual(result["dispositions"][0]["reason"], "unknown_object_key")
        self.assertEqual(result["dispositions"][1]["disposition"], "accepted")

    def test_b1_02_c_rejects_noncanonical_branches(self):
        invalid = [
            "feature/not-an-agent",
            "agents/x..y",
            "agents/x.lock",
            "agents/x/",
            "agents//x",
        ]
        result = bridge.normalize_status({"lanes": invalid, "pulls": []})
        self.assertEqual(result["records"], [])
        self.assertTrue(all(item["disposition"] == "invalid"
                            for item in result["dispositions"]))
        green = bridge.normalize_status({"lanes": ["agents/factory-canonical"]})
        self.assertEqual(green["records"], [{"branch": "agents/factory-canonical"}])

    def test_b1_02_d_requires_full_lowercase_sha_heads(self):
        result = bridge.normalize_status({
            "pulls": [
                {"branch": "agents/factory-short", "head": "a" * 12},
                {"branch": "agents/factory-upper", "head": "A" * 40},
                {"branch": "agents/factory-head-ok", "head": "b" * 40},
            ]
        })
        self.assertEqual(result["records"], [
            {"branch": "agents/factory-head-ok", "head": "b" * 40},
        ])
        self.assertEqual([item["reason"] for item in result["dispositions"][:2]],
                         ["invalid_head", "invalid_head"])

    def test_b1_02_e_accepts_only_positive_integer_pr_hints(self):
        invalid = [True, False, 0, -1, "1", "https://github.com/SFenton/native-home/pull/1"]
        pulls = [
            {"branch": "agents/factory-pr-{}".format(index), "pr": value}
            for index, value in enumerate(invalid)
        ]
        pulls.append({"branch": "agents/factory-pr-ok", "pr": 7})
        result = bridge.normalize_status({"pulls": pulls})
        self.assertEqual(result["records"], [{"branch": "agents/factory-pr-ok", "pr": 7}])
        self.assertTrue(all(item["reason"] == "invalid_pr"
                            for item in result["dispositions"][:-1]))

    def test_b1_02_f_rejects_wrong_collection_types(self):
        lanes = bridge.normalize_status({"lanes": "agents/factory-string"})
        pulls = bridge.normalize_status({"pulls": {"branch": "agents/factory-object"}})
        self.assertEqual(lanes["records"], [])
        self.assertEqual(lanes["dispositions"][0]["reason"], "invalid_collection")
        self.assertEqual(pulls["records"], [])
        self.assertEqual(pulls["dispositions"][0]["reason"], "invalid_collection")
        green = bridge.normalize_status({"lanes": ["agents/factory-list"]})
        self.assertEqual(green["records"], [{"branch": "agents/factory-list"}])

    def test_b1_02_g_deduplicates_consistent_identities_in_order(self):
        result = bridge.normalize_status({
            "lanes": ["agents/factory-one", "agents/factory-two", "agents/factory-one"],
            "pulls": [
                {"branch": "agents/factory-one", "pr": 9},
                {"branch": "agents/factory-one", "head": HEAD},
                {"branch": "agents/factory-two", "pr": 10},
            ],
        })
        self.assertEqual(result["records"], [
            {"branch": "agents/factory-one", "pr": 9, "head": HEAD},
            {"branch": "agents/factory-two", "pr": 10},
        ])
        self.assertEqual(
            sum(item["disposition"] == "duplicate" for item in result["dispositions"]),
            4,
        )

    def test_b1_02_h_holds_contradictory_hints(self):
        result = bridge.normalize_status({
            "pulls": [
                {"branch": "agents/factory-conflict", "pr": 9, "head": HEAD},
                {"branch": "agents/factory-conflict", "pr": 10, "head": HEAD},
                {"branch": "agents/factory-clear", "pr": 11},
            ]
        })
        self.assertEqual(result["records"], [{"branch": "agents/factory-clear", "pr": 11}])
        conflicts = [item for item in result["dispositions"]
                     if item["disposition"] == "conflict"]
        self.assertEqual(len(conflicts), 2)
        self.assertTrue(all(item["reason"] == "conflicting_hints" for item in conflicts))

    def test_b1_02_i_applies_one_stable_five_lane_cap(self):
        lanes = ["agents/factory-{}".format(index) for index in range(4)]
        pulls = [{"branch": "agents/factory-4"}, {"branch": "agents/factory-5"}]
        result = bridge.normalize_status({"lanes": lanes, "pulls": pulls})
        self.assertEqual(
            [record["branch"] for record in result["records"]],
            lanes + ["agents/factory-4"],
        )
        self.assertEqual(result["dispositions"][-1]["disposition"], "surplus")
        self.assertEqual(result["dispositions"][-1]["reason"], "lane_limit")


class PullPhaseTests(unittest.TestCase):
    def decoded_open(self, pull=None, reviews=None):
        return bridge.decode_pull_facts(pull or open_pull(), reviews or [])

    def test_b1_09_closed_unmerged_is_not_merged(self):
        reader = FakeReader(pull=closed_unmerged_pull())
        facts = bridge.read_pull_facts(reader, REPO, 202)
        phase = bridge.classify_phase(facts, owner_required=False)
        self.assertEqual(phase["phase"], "closed_unmerged")
        self.assertEqual(phase["reason"], "closed_without_merge")
        merged = bridge.read_pull_facts(
            FakeReader(
                pull=merged_pull(),
                commit=web_flow_commit(),
                associated_pulls=[merged_pull()],
            ),
            REPO,
            199,
        )
        self.assertEqual(
            bridge.classify_phase(merged, owner_required=False)["phase"],
            "merged",
        )

    def test_b1_13_a_draft_has_its_own_reason(self):
        facts = self.decoded_open(open_pull(isDraft=True, reviewDecision=""))
        phase = bridge.classify_phase(facts, owner_required=False)
        self.assertEqual(phase["phase"], "owner_wait")
        self.assertEqual(phase["reason"], "draft")
        ready = bridge.classify_phase(
            self.decoded_open(open_pull(isDraft=False, reviewDecision="")),
            owner_required=False,
        )
        self.assertEqual(ready["phase"], "awaiting_merge")

    def test_b1_13_b_conflict_wins_over_draft(self):
        facts = self.decoded_open(open_pull(
            isDraft=True,
            mergeable="CONFLICTING",
        ))
        phase = bridge.classify_phase(facts, owner_required=True)
        self.assertEqual(phase["phase"], "actionable")
        self.assertEqual(phase["reason"], "merge_conflict")
        self.assertNotEqual(phase["reason"], "draft")
        draft = bridge.classify_phase(
            self.decoded_open(open_pull(isDraft=True, reviewDecision="")),
            owner_required=False,
        )
        self.assertEqual(draft["reason"], "draft")

    def test_b1_13_c_failed_pr_checks_are_not_owner_wait(self):
        failed = [
            {
                "name": "pr-checks",
                "status": "COMPLETED",
                "conclusion": "FAILURE",
                "startedAt": "2026-11-21T20:02:00Z",
            },
            {
                "name": "ai-review",
                "status": "COMPLETED",
                "conclusion": "SUCCESS",
                "startedAt": "2026-11-21T20:03:00Z",
            },
        ]
        facts = self.decoded_open(open_pull(statusCheckRollup=failed))
        phase = bridge.classify_phase(facts, owner_required=True)
        self.assertEqual(phase["phase"], "actionable")
        self.assertEqual(phase["reason"], "pr_checks_failed")
        green = bridge.classify_phase(
            self.decoded_open(),
            owner_required=True,
            reviews=[approval()],
        )
        self.assertEqual(green["phase"], "awaiting_merge")

    def test_b1_13_d_missing_ai_review_is_not_approved_awaiting_merge(self):
        facts = self.decoded_open(
            open_pull(
                reviewDecision="APPROVED",
                statusCheckRollup=[open_pull()["statusCheckRollup"][0]],
            ),
            [approval()],
        )
        phase = bridge.classify_phase(facts, owner_required=True)
        self.assertEqual(phase["phase"], "needs_review")
        self.assertEqual(phase["reason"], "ai_review_missing")
        green = bridge.classify_phase(
            self.decoded_open(open_pull(reviewDecision="APPROVED"), [approval()]),
            owner_required=True,
        )
        self.assertEqual(green["phase"], "awaiting_merge")

    def test_b1_13_e_only_latest_exact_owner_approval_counts(self):
        wrong = [
            approval(OTHER_SHA, index=1),
            approval(HEAD, login="someone-else", index=2),
            approval(HEAD, state="CHANGES_REQUESTED", index=3),
        ]
        facts = self.decoded_open(open_pull(reviewDecision="APPROVED"), wrong)
        phase = bridge.classify_phase(facts, owner_required=True)
        self.assertEqual(phase["phase"], "owner_wait")
        self.assertEqual(phase["reason"], "owner_review_required")
        approved = bridge.classify_phase(
            self.decoded_open(open_pull(reviewDecision="APPROVED"), [approval()]),
            owner_required=True,
        )
        self.assertEqual(approved["phase"], "awaiting_merge")

    def test_b1_13_f_incomplete_ownership_does_not_prove_unowned(self):
        incomplete = self.decoded_open(open_pull(
            files=[{"path": "path-{}".format(index)} for index in range(100)]
        ))
        held = bridge.classify_phase(incomplete, owner_required=False)
        self.assertEqual(held["phase"], "held")
        self.assertEqual(held["reason"], "ownership_unknown")
        unreadable = bridge.classify_phase(
            self.decoded_open(),
            owner_required=None,
        )
        self.assertEqual(unreadable["reason"], "ownership_unknown")
        green = bridge.classify_phase(
            self.decoded_open(open_pull(files=[{"path": "tools/triage/pr_bridge.py"}])),
            owner_required=False,
        )
        self.assertEqual(green["phase"], "awaiting_merge")


class AccountingTests(unittest.TestCase):
    def decoded_merged(self, pull=None, commit=None, associated_pulls=None):
        value = pull or merged_pull()
        commit_value = commit or web_flow_commit()
        associated = associated_pulls if associated_pulls is not None else [value]
        return bridge.read_pull_facts(
            FakeReader(
                pull=value,
                commit=commit_value,
                associated_pulls=associated,
            ),
            REPO,
            value["number"],
        )

    def record(self, facts, **changes):
        arguments = {
            "repo": REPO,
            "expected_pr": 199,
            "expected_base": "main",
            "reviewed_head": REVIEWED_HEAD,
        }
        arguments.update(changes)
        return bridge.build_accounting_record(facts, **arguments)

    def test_b1_14_a_accounts_only_an_actual_server_merge(self):
        open_record = self.record(
            bridge.read_pull_facts(FakeReader(pull=open_pull(number=199)), REPO, 199)
        )
        self.assertEqual(open_record["disposition"], "held")
        self.assertEqual(open_record["reason"], "not_merged")
        merged_record = self.record(self.decoded_merged())
        self.assertEqual(merged_record["disposition"], "accounted")
        self.assertEqual(merged_record["key"], (REPO, 199, MERGE_SHA))

    def test_b1_14_b_matches_exact_pr_and_base(self):
        facts = self.decoded_merged()
        wrong_pr = self.record(facts, expected_pr=200)
        self.assertEqual(wrong_pr["disposition"], "held")
        self.assertEqual(wrong_pr["reason"], "wrong_pull_request")
        wrong_base = self.record(facts, expected_base="release")
        self.assertEqual(wrong_base["disposition"], "held")
        self.assertEqual(wrong_base["reason"], "wrong_base")
        wrong_association = self.record(
            self.decoded_merged(associated_pulls=[merged_pull(number=200)])
        )
        self.assertEqual(wrong_association["disposition"], "held")
        self.assertEqual(wrong_association["reason"], "wrong_pull_request")
        self.assertEqual(self.record(facts)["disposition"], "accounted")

    def test_b1_14_c_keeps_reviewed_and_merge_heads_independent(self):
        record = self.record(self.decoded_merged())
        self.assertEqual(record["record"]["reviewed_head"], REVIEWED_HEAD)
        self.assertEqual(record["record"]["head_at_merge"], HEAD)
        self.assertNotEqual(
            record["record"]["reviewed_head"],
            record["record"]["head_at_merge"],
        )

    def test_b1_14_d_rejects_two_parent_squash_claims(self):
        two_parents = web_flow_commit(
            parents=[{"sha": BASE_SHA}, {"sha": OTHER_SHA}],
        )
        held = self.record(self.decoded_merged(commit=two_parents))
        self.assertEqual(held["disposition"], "held")
        self.assertEqual(held["reason"], "parent_count")
        self.assertEqual(self.record(self.decoded_merged())["disposition"], "accounted")

    def test_b1_14_f_requires_web_flow_committer_login(self):
        wrong_login = web_flow_commit(committer={"login": "GitHub"})
        held = self.record(self.decoded_merged(commit=wrong_login))
        self.assertEqual(held["disposition"], "held")
        self.assertEqual(held["reason"], "committer_not_github")
        self.assertEqual(self.record(self.decoded_merged())["disposition"], "accounted")

    def test_b1_14_g_requires_valid_signature_verification(self):
        unsigned = web_flow_commit(commit={
            "verification": {"verified": False, "reason": "unsigned"},
            "message": "Ship the bridge (#199)",
        })
        held = self.record(self.decoded_merged(commit=unsigned))
        self.assertEqual(held["disposition"], "held")
        self.assertEqual(held["reason"], "signature_unverified")
        valid = web_flow_commit()
        self.assertEqual(
            self.record(self.decoded_merged(commit=valid))["disposition"],
            "accounted",
        )


class RevertChoiceTests(unittest.TestCase):
    def test_b1_18_a_one_parent_reverts_without_mainline(self):
        choice = bridge.revert_choice(1, kind="squash")
        self.assertEqual(choice["disposition"], "ready")
        self.assertEqual(choice["arguments"], ())
        self.assertIsNone(
            choice["mainline"],
        )

    def test_b1_18_b_legacy_two_parent_merge_uses_mainline_one(self):
        choice = bridge.revert_choice(2)
        self.assertEqual(choice["disposition"], "ready")
        self.assertEqual(choice["arguments"], ("-m", "1"))
        self.assertEqual(choice["mainline"], 1)
        changed = bridge.revert_choice(1)
        self.assertEqual(changed["arguments"], ())

    def test_b1_18_c_unexpected_parent_count_is_held(self):
        for parents in (True, 0, 3, -1, "2"):
            with self.subTest(parents=parents):
                choice = bridge.revert_choice(parents)
                self.assertEqual(choice["disposition"], "held")
                self.assertEqual(choice["reason"], "unexpected_parent_count")
        self.assertEqual(bridge.revert_choice(2, kind="merge")["disposition"], "ready")


class CompatibilityTests(unittest.TestCase):
    def test_b1_32_import_is_inert_and_compatible(self):
        module_path = HERE.parents[0] / "pr_bridge.py"
        spec = importlib.util.spec_from_file_location("pr_bridge_inert", module_path)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        with mock.patch("subprocess.run", side_effect=AssertionError("subprocess at import")), \
                mock.patch("urllib.request.urlopen", side_effect=AssertionError("network at import")):
            spec.loader.exec_module(module)
        self.assertTrue(callable(module.normalize_status))
        self.assertTrue(callable(module.read_pull_facts))


if __name__ == "__main__":
    unittest.main()
