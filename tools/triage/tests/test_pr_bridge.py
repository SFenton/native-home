"""Tests for the inert pull-request bridge. No network, subprocess or clock is used."""
from __future__ import annotations

import copy
import importlib.util
import os
import socket
import subprocess
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
REVIEW_APP_ID = 5618837
ACTIONS_APP_ID = 15368
EXPECTED_PULL_FIELDS = (
    "number,state,mergedAt,mergeCommit,headRefOid,headRefName,baseRefName,"
    "isDraft,isCrossRepository,author,reviewDecision,mergeStateStatus,mergeable,"
    "files,statusCheckRollup,createdAt"
)


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


def check_runs(pull=None):
    value = pull or open_pull()
    app_ids = {
        "pr-checks": ACTIONS_APP_ID,
        "ai-review": REVIEW_APP_ID,
    }
    rows = []
    for index, item in enumerate(value["statusCheckRollup"]):
        name = item.get("name") or item.get("context")
        rows.append({
            "id": index + 1,
            "name": name,
            "status": str(item.get("status") or "").lower(),
            "conclusion": str(
                item.get("conclusion") or item.get("state") or ""
            ).lower(),
            "started_at": item.get("startedAt") or item.get("started_at") or "",
            "completed_at": item.get("completedAt") or item.get("completed_at") or "",
            "head_sha": value["headRefOid"],
            "app": {"id": app_ids.get(name)},
        })
    return {
        "check_runs": rows, "total_count": len(rows),
    }


def associated_pull(pull=None):
    value = pull or merged_pull()
    return {
        "number": value["number"],
        "base": {"ref": value["baseRefName"]},
        "merge_commit_sha": value["mergeCommit"]["oid"] if value["mergeCommit"] else None,
    }


class ForbiddenEnvironment:
    def __getitem__(self, key):
        raise AssertionError("environment read at import: {!r}".format(key))

    def __contains__(self, key):
        raise AssertionError("environment read at import: {!r}".format(key))

    def get(self, key, default=None):
        raise AssertionError("environment read at import: {!r}".format(key))

    def items(self):
        raise AssertionError("environment read at import")


class FakeReader:
    def __init__(self, pull=None, reviews=None, commit=None, associated_pulls=None,
                 checks=None, repo=REPO, request_number=None, fail=None, missing=None):
        self.pull = copy.deepcopy(pull or open_pull())
        self.reviews = copy.deepcopy(reviews or [])
        self.commit = copy.deepcopy(commit or web_flow_commit())
        self.checks = copy.deepcopy(
            checks if checks is not None else check_runs(self.pull)
        )
        self.associated_pulls = copy.deepcopy(
            associated_pulls if associated_pulls is not None else [associated_pull(self.pull)]
        )
        self.repo = repo
        self.request_number = request_number or self.pull["number"]
        self.fail = set(fail or ())
        self.missing = set(missing or ())
        self.calls, self.unexpected_calls = [], []

    def __call__(self, argv):
        args = list(argv)
        self.calls.append(args)
        expected = [
            "pr", "view", str(self.request_number), "-R", self.repo,
            "--json", EXPECTED_PULL_FIELDS,
        ]
        if args == expected:
            kind = "pull"
            response = self.pull
        elif args == [
            "api",
            "repos/{}/pulls/{}/reviews".format(self.repo, self.request_number),
            "--paginate",
        ]:
            kind = "reviews"
            response = self.reviews
        elif args == [
            "api",
            "repos/{}/commits/{}/check-runs".format(
                self.repo, self.pull["headRefOid"]
            ),
            "--paginate",
        ]:
            kind = "check_runs"
            response = self.checks
        elif args == [
            "api",
            "repos/{}/commits/{}".format(
                self.repo, self.pull["mergeCommit"]["oid"]
                if self.pull["mergeCommit"] else ""
            ),
        ]:
            kind = "commit"
            response = self.commit
        elif args == [
            "api",
            "repos/{}/commits/{}/pulls".format(
                self.repo, self.pull["mergeCommit"]["oid"]
                if self.pull["mergeCommit"] else ""
            ),
        ]:
            kind = "associated"
            response = self.associated_pulls
        else:
            raise AssertionError(self.unexpected_calls.append(args) or "unexpected reader call: {!r}".format(args))
        if kind in self.fail:
            raise RuntimeError("injected {} failure".format(kind))
        if kind in self.missing:
            return None
        return copy.deepcopy(response)


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
        self.assertEqual(result["records"], [])
        self.assertEqual(result["dispositions"][0]["disposition"], "invalid")
        self.assertEqual(result["dispositions"][0]["reason"], "unknown_object_key")
        self.assertEqual(result["dispositions"][1]["disposition"], "conflict")
        self.assertEqual(result["dispositions"][1]["reason"], "invalid_conflict")

    def test_b1_02_c_rejects_noncanonical_branches(self):
        invalid = [
            "feature/not-an-agent",
            "agents/x..y",
            "agents/x.lock",
            "agents/x/",
            "agents//x",
            "agents/a//b",
            "agents/a.",
            "agents/a/.b",
            "agents/a.lock/b",
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

    def test_b1_02_g_duplicates_across_sources_share_one_cap_slot(self):
        lanes = ["agents/factory-cap-{}".format(index) for index in range(5)]
        result = bridge.normalize_status({
            "lanes": lanes,
            "pulls": [{"branch": lanes[0], "pr": 9}],
        })
        self.assertEqual(
            [record["branch"] for record in result["records"]],
            lanes,
        )
        self.assertFalse(any(
            item["disposition"] == "surplus"
            for item in result["dispositions"]
        ))

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

    def test_b1_02_h_holds_head_only_conflicts(self):
        branch = "agents/factory-head-conflict"
        result = bridge.normalize_status({
            "pulls": [
                {"branch": branch, "head": HEAD},
                {"branch": branch, "head": OTHER_SHA},
            ]
        })
        self.assertEqual(result["records"], [])
        self.assertEqual(
            [item["disposition"] for item in result["dispositions"]],
            ["conflict", "conflict"],
        )

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
    def decoded_open(self, pull=None, reviews=None, checks=None):
        value = pull or open_pull()
        return bridge.decode_pull_facts(
            value,
            reviews=reviews or [],
            check_runs=checks if checks is not None else check_runs(value),
            repository=REPO,
        )

    def phase(self, value, **changes):
        arguments = {"owner_required": False, "owner_login": "SFenton"}
        arguments.update(changes)
        return bridge.classify_phase(value, **arguments)

    def test_b1_09_closed_unmerged_is_not_merged(self):
        reader = FakeReader(pull=closed_unmerged_pull())
        facts = bridge.read_pull_facts(reader, REPO, 202)
        phase = self.phase(facts)
        self.assertEqual(phase["phase"], "closed_unmerged")
        self.assertEqual(phase["reason"], "closed_without_merge")
        merged = bridge.read_pull_facts(
            FakeReader(
                pull=merged_pull(),
                commit=web_flow_commit(),
                associated_pulls=[associated_pull(merged_pull())],
            ),
            REPO,
            199,
        )
        self.assertEqual(
            self.phase(merged)["phase"],
            "merged",
        )

    def test_b1_13_a_draft_has_its_own_reason(self):
        facts = self.decoded_open(open_pull(isDraft=True, reviewDecision=""))
        phase = self.phase(facts)
        self.assertEqual(phase["phase"], "owner_wait")
        self.assertEqual(phase["reason"], "draft")
        ready = self.phase(
            self.decoded_open(open_pull(isDraft=False, reviewDecision="")),
        )
        self.assertEqual(ready["phase"], "awaiting_merge")

    def test_b1_13_b_conflict_wins_over_draft(self):
        facts = self.decoded_open(open_pull(
            isDraft=True,
            mergeable="CONFLICTING",
        ))
        phase = self.phase(facts, owner_required=True)
        self.assertEqual(phase["phase"], "actionable")
        self.assertEqual(phase["reason"], "merge_conflict")
        self.assertNotEqual(phase["reason"], "draft")
        draft = self.phase(
            self.decoded_open(open_pull(isDraft=True, reviewDecision="")),
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
        phase = self.phase(facts, owner_required=True)
        self.assertEqual(phase["phase"], "actionable")
        self.assertEqual(phase["reason"], "pr_checks_failed")
        green = self.phase(
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
        phase = self.phase(facts, owner_required=True)
        self.assertEqual(phase["phase"], "needs_review")
        self.assertEqual(phase["reason"], "ai_review_missing")
        green = self.phase(
            self.decoded_open(open_pull(reviewDecision="APPROVED"), [approval()]),
            owner_required=True,
        )
        self.assertEqual(green["phase"], "awaiting_merge")

    def assert_owner_wait(self, reviews):
        facts = self.decoded_open(open_pull(reviewDecision="APPROVED"), reviews)
        phase = self.phase(facts, owner_required=True)
        self.assertEqual(phase["phase"], "owner_wait")
        self.assertEqual(phase["reason"], "owner_review_required")

    def test_b1_13_e_rejects_owner_approval_for_another_head(self):
        self.assert_owner_wait([approval(OTHER_SHA)])

    def test_b1_13_e_rejects_non_owner_approval_for_head(self):
        self.assert_owner_wait([approval(HEAD, login="someone-else")])

    def test_b1_13_e_rejects_later_owner_changes_request(self):
        self.assert_owner_wait([
            approval(HEAD, index=1),
            approval(HEAD, state="CHANGES_REQUESTED", index=2),
        ])

    def test_b1_13_e_accepts_latest_owner_approval_for_exact_head(self):
        approved = self.phase(
            self.decoded_open(open_pull(reviewDecision="APPROVED"), [approval()]),
            owner_required=True,
        )
        self.assertEqual(approved["phase"], "awaiting_merge")

    def test_b1_13_f_incomplete_ownership_does_not_prove_unowned(self):
        incomplete = self.decoded_open(open_pull(
            files=[{"path": "path-{}".format(index)} for index in range(100)]
        ))
        held = self.phase(incomplete)
        self.assertEqual(held["phase"], "held")
        self.assertEqual(held["reason"], "ownership_unknown")
        unreadable = self.phase(
            self.decoded_open(),
            owner_required=None,
        )
        self.assertEqual(unreadable["reason"], "ownership_unknown")
        green = self.phase(
            self.decoded_open(open_pull(files=[{"path": "tools/triage/pr_bridge.py"}])),
        )
        self.assertEqual(green["phase"], "awaiting_merge")

    def test_check_identity_requires_expected_app_and_exact_head(self):
        cases = []
        wrong_app = check_runs()
        wrong_app["check_runs"][1]["app"]["id"] = ACTIONS_APP_ID
        cases.append(wrong_app)
        wrong_head = check_runs()
        wrong_head["check_runs"][1]["head_sha"] = OTHER_SHA
        cases.append(wrong_head)
        for runs in cases:
            with self.subTest(runs=runs):
                phase = self.phase(self.decoded_open(checks=runs))
                self.assertEqual(phase["reason"], "ai_review_missing")

    def test_check_identity_accepts_only_newest_expected_sources(self):
        completed = self.phase(self.decoded_open(checks=check_runs()))
        runs = check_runs()
        for run in runs["check_runs"]:
            if run["name"] == "pr-checks":
                run["completed_at"] = "2026-11-21T20:10:00Z"
        runs["check_runs"].append({
            "id": 3,
            "name": "pr-checks",
            "status": "IN_PROGRESS",
            "conclusion": "",
            "started_at": "2026-11-21T20:04:00Z",
            "head_sha": HEAD,
            "app": {"id": ACTIONS_APP_ID},
        })
        runs["total_count"] = len(runs["check_runs"])
        phase = self.phase(self.decoded_open(checks=runs))
        self.assertEqual(completed["phase"], "awaiting_merge")
        self.assertEqual(phase["phase"], "awaiting_checks")
        self.assertEqual(phase["reason"], "pr_checks_pending")

    def test_terminal_states_reject_identity_mismatches(self):
        closed = bridge.decode_pull_facts(
            closed_unmerged_pull(), repository=REPO
        )
        merged = bridge.decode_pull_facts(
            merged_pull(), repository=REPO
        )
        expectations = {
            "expected_repository": "SFenton/other",
            "expected_author": "other-agent",
            "expected_branch": "agents/other-branch",
            "expected_base": "release",
            "expected_head": OTHER_SHA,
        }
        for value in (closed, merged):
            for expectation, supplied in expectations.items():
                with self.subTest(state=value["facts"]["state"], field=expectation):
                    phase = self.phase(value, **{expectation: supplied})
                    self.assertEqual(phase["phase"], "held")
                    self.assertTrue(phase["reason"].endswith("_mismatch"))

    def test_terminal_states_reject_reviewed_head_mismatch(self):
        for value in (
            bridge.decode_pull_facts(
                closed_unmerged_pull(), repository=REPO
            ),
            bridge.decode_pull_facts(
                merged_pull(), repository=REPO
            ),
        ):
            with self.subTest(state=value["facts"]["state"]):
                phase = self.phase(value, reviewed_head=OTHER_SHA)
                self.assertEqual(
                    phase,
                    {"phase": "held", "reason": "head_mismatch"},
                )

    def test_validated_fact_envelope_is_required(self):
        bare = bridge.decode_pull_facts(
            open_pull(), repository=REPO, check_runs=check_runs()
        )["facts"]
        malformed = {
            "state": "OPEN",
            "checks": [1],
        }
        self.assertEqual(
            self.phase(bare),
            {"phase": "held", "reason": "invalid_facts"},
        )
        self.assertEqual(
            self.phase(malformed),
            {"phase": "held", "reason": "invalid_facts"},
        )

    def test_reviews_not_supplied_are_incomplete(self):
        facts = bridge.decode_pull_facts(
            open_pull(), check_runs=check_runs(), repository=REPO
        )
        self.assertFalse(facts["facts"]["reviews_complete"])
        phase = self.phase(facts, owner_required=True)
        self.assertEqual(phase["reason"], "owner_review_unreadable")

    def test_reader_failures_are_never_negative_evidence(self):
        cases = [
            ("pull", {"pull": open_pull()}, 203),
            ("reviews", {"pull": open_pull()}, 203),
            ("check_runs", {"pull": open_pull()}, 203),
            ("commit", {"pull": merged_pull()}, 199),
            ("associated", {"pull": merged_pull()}, 199),
        ]
        for kind, values, number in cases:
            with self.subTest(kind=kind):
                reader = FakeReader(fail=[kind], **values)
                facts = bridge.read_pull_facts(
                    reader,
                    REPO,
                    number,
                )
                phase = self.phase(facts, owner_required=True)
                self.assertEqual(phase["phase"], "held")
                self.assertFalse(facts["ok"])
                self.assertEqual(reader.unexpected_calls, [])
                expected_call = {
                    "pull": [
                        "pr", "view", str(number), "-R", REPO,
                        "--json", EXPECTED_PULL_FIELDS,
                    ],
                    "reviews": [
                        "api",
                        f"repos/{REPO}/pulls/{number}/reviews",
                        "--paginate",
                    ],
                    "check_runs": [
                        "api",
                        f"repos/{REPO}/commits/{HEAD}/check-runs",
                        "--paginate",
                    ],
                    "commit": [
                        "api",
                        f"repos/{REPO}/commits/{MERGE_SHA}",
                    ],
                    "associated": [
                        "api",
                        f"repos/{REPO}/commits/{MERGE_SHA}/pulls",
                    ],
                }[kind]
                self.assertEqual(reader.calls[-1], expected_call)

    def test_wrong_pull_number_answer_is_held(self):
        reader = FakeReader(pull=merged_pull(number=199), request_number=200)
        facts = bridge.read_pull_facts(reader, REPO, 200)
        self.assertEqual(
            facts["dispositions"],
            [{"disposition": "held", "reason": "wrong_pull_request"}],
        )
        self.assertEqual(reader.calls, [[
            "pr", "view", "200", "-R", REPO, "--json", EXPECTED_PULL_FIELDS,
        ]])


class AccountingTests(unittest.TestCase):
    def decoded_merged(self, pull=None, commit=None, associated_pulls=None):
        value = pull or merged_pull()
        commit_value = commit or web_flow_commit()
        associated = associated_pulls if associated_pulls is not None else [associated_pull(value)]
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
            "expected_author": "sfenton-agent",
            "expected_branch": "agents/factory-squash",
            "expected_head": HEAD,
            "reviewed_head": REVIEWED_HEAD,
        }
        arguments.update(changes)
        return bridge.build_accounting_record(facts, **arguments)

    def test_b1_14_a_accounts_only_an_actual_server_merge(self):
        open_record = self.record(
            bridge.read_pull_facts(FakeReader(pull=open_pull(number=199)), REPO, 199),
            expected_branch="agents/factory-owner-held",
        )
        self.assertEqual(open_record["disposition"], "held")
        self.assertEqual(open_record["reason"], "not_merged")
        merged_record = self.record(self.decoded_merged())
        self.assertEqual(merged_record["disposition"], "accounted")
        self.assertEqual(merged_record["key"], (REPO, 199, MERGE_SHA))

    def test_b1_14_b_rejects_wrong_expected_pull_number(self):
        facts = self.decoded_merged(associated_pulls=[
            associated_pull(merged_pull(number=200)),
        ])
        wrong_pr = self.record(facts, expected_pr=200)
        self.assertEqual(wrong_pr["disposition"], "held")
        self.assertEqual(wrong_pr["reason"], "wrong_pull_request")

    def test_b1_14_b_rejects_wrong_base(self):
        wrong_base = self.record(
            self.decoded_merged(),
            expected_base="release",
        )
        self.assertEqual(wrong_base["disposition"], "held")
        self.assertEqual(wrong_base["reason"], "wrong_base")

    def test_b1_14_b_rejects_wrong_pull_association(self):
        wrong_association = self.record(
            self.decoded_merged(
                associated_pulls=[associated_pull(merged_pull(number=200))],
            )
        )
        self.assertEqual(wrong_association["disposition"], "held")
        self.assertEqual(wrong_association["reason"], "pull_association_mismatch")

    def test_b1_14_b_accepts_exact_rest_pr_base_and_merge_sha(self):
        self.assertEqual(
            self.record(self.decoded_merged())["disposition"],
            "accounted",
        )

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

    def test_b1_14_g_rejects_verified_false(self):
        unverified = web_flow_commit(commit={
            "verification": {"verified": False, "reason": "valid"},
            "message": "Ship the bridge (#199)",
        })
        held = self.record(self.decoded_merged(commit=unverified))
        self.assertEqual(held["disposition"], "held")
        self.assertEqual(held["reason"], "signature_unverified")

    def test_b1_14_g_rejects_unsigned_reason(self):
        unsigned = web_flow_commit(commit={
            "verification": {"verified": True, "reason": "unsigned"},
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

    def test_identity_is_bound_in_accounting(self):
        cases = [
            ("repo", "SFenton/other", "wrong_repository"),
            ("expected_author", "other-agent", "wrong_author"),
            (
                "expected_branch",
                "agents/other-branch",
                "wrong_branch",
            ),
            ("expected_head", OTHER_SHA, "wrong_head"),
        ]
        facts = self.decoded_merged()
        for field, supplied, reason in cases:
            with self.subTest(field=field):
                held = self.record(facts, **{field: supplied})
                self.assertEqual(held["disposition"], "held")
                self.assertEqual(held["reason"], reason)

    def test_cross_repository_is_never_accounted(self):
        held = self.record(self.decoded_merged(
            pull=merged_pull(isCrossRepository=True),
        ))
        self.assertEqual(held["disposition"], "held")
        self.assertEqual(held["reason"], "cross_repository")

    def test_accounting_requires_validated_fact_envelope(self):
        bare = self.decoded_merged()["facts"]
        malformed = {"state": "MERGED"}
        for value in (bare, malformed):
            with self.subTest(value=value):
                held = self.record(value)
                self.assertEqual(held["disposition"], "held")
                self.assertEqual(held["reason"], "invalid_facts")


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

    def test_b1_18_revert_of_revert_is_manual(self):
        choice = bridge.revert_choice(1, kind="revert")
        self.assertEqual(choice["disposition"], "held")
        self.assertEqual(choice["reason"], "manual_revert_of_revert")


class CompatibilityTests(unittest.TestCase):
    def test_b1_32_import_is_inert_and_compatible(self):
        module_path = HERE.parents[0] / "pr_bridge.py"
        spec = importlib.util.spec_from_file_location("pr_bridge_inert", module_path)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        forbidden_environment = ForbiddenEnvironment()
        with mock.patch("subprocess.run", side_effect=AssertionError("subprocess at import")), \
                mock.patch.object(subprocess, "Popen", side_effect=AssertionError("process at import")), \
                mock.patch("os.system", side_effect=AssertionError("system at import")), \
                mock.patch("builtins.open", side_effect=AssertionError("file open at import")), \
                mock.patch.object(socket, "socket", side_effect=AssertionError("socket at import")), \
                mock.patch.object(os, "getenv", side_effect=AssertionError("environment at import")), \
                mock.patch.object(os, "environ", forbidden_environment), \
                mock.patch("urllib.request.urlopen", side_effect=AssertionError("network at import")):
            spec.loader.exec_module(module)
        self.assertTrue(callable(module.normalize_status))
        self.assertTrue(callable(module.read_pull_facts))


class ReviewRoundTwoTests(unittest.TestCase):
    def phase(self, value, **changes):
        arguments = {"owner_required": False, "owner_login": "SFenton"}
        arguments.update(changes)
        return bridge.classify_phase(value, **arguments)

    def record(self, value):
        return bridge.build_accounting_record(
            value,
            repo=REPO,
            expected_pr=199,
            expected_base="main",
            expected_author="sfenton-agent",
            expected_branch="agents/factory-squash",
            expected_head=HEAD,
            reviewed_head=REVIEWED_HEAD,
        )

    def test_decoded_fact_mapping_is_read_only(self):
        decoded = bridge.decode_pull_facts(
            open_pull(), check_runs=check_runs(), repository=REPO
        )
        with self.assertRaises(TypeError):
            decoded["facts"]["state"] = "MERGED"

    def test_success_shaped_dict_is_not_a_valid_phase_envelope(self):
        decoded = bridge.decode_pull_facts(
            open_pull(), check_runs=check_runs(), repository=REPO
        )
        forged = {
            "ok": True,
            "facts": type(decoded["facts"])(dict(decoded["facts"])),
            "dispositions": [],
        }
        self.assertEqual(
            self.phase(forged),
            {"phase": "held", "reason": "invalid_facts"},
        )
        self.assertEqual(self.phase(decoded)["phase"], "awaiting_merge")

    def test_success_shaped_dict_is_not_valid_accounting_envelope(self):
        decoded = bridge.read_pull_facts(
            FakeReader(pull=merged_pull()),
            REPO,
            199,
        )
        forged = {
            "ok": True,
            "facts": type(decoded["facts"])(dict(decoded["facts"])),
            "dispositions": [],
        }
        self.assertEqual(self.record(forged)["reason"], "invalid_facts")
        self.assertEqual(self.record(decoded)["disposition"], "accounted")

    def test_check_run_total_count_must_match_rows(self):
        for total_count in (None, "2", True, 1, 3):
            with self.subTest(total_count=total_count):
                runs = check_runs()
                if total_count is None:
                    del runs["total_count"]
                else:
                    runs["total_count"] = total_count
                decoded = bridge.decode_pull_facts(
                    open_pull(), check_runs=runs, repository=REPO
                )
                self.assertFalse(decoded["facts"]["checks_complete"])
                self.assertEqual(
                    self.phase(decoded)["reason"],
                    "checks_unverified",
                )

    def test_missing_open_supplemental_answers_are_incomplete(self):
        cases = (
            ("reviews", "owner_review_unreadable"),
            ("check_runs", "checks_unverified"),
        )
        for missing, reason in cases:
            with self.subTest(missing=missing):
                reader = FakeReader(pull=open_pull(), missing=[missing])
                decoded = bridge.read_pull_facts(reader, REPO, 203)
                self.assertEqual(reader.unexpected_calls, [])
                if missing == "check_runs":
                    self.assertFalse(decoded["facts"]["checks_complete"])
                self.assertEqual(
                    self.phase(decoded, owner_required=True)["reason"],
                    reason,
                )

    def test_missing_merged_supplemental_answers_are_unreadable(self):
        cases = (
            ("commit", "commit_unreadable"),
            ("associated", "pull_association_unreadable"),
        )
        for missing, reason in cases:
            with self.subTest(missing=missing):
                reader = FakeReader(pull=merged_pull(), missing=[missing])
                decoded = bridge.read_pull_facts(reader, REPO, 199)
                self.assertEqual(reader.unexpected_calls, [])
                self.assertEqual(self.record(decoded)["reason"], reason)

    def test_swallowed_unexpected_reader_call_is_recorded(self):
        reader = FakeReader(repo=REPO)
        decoded = bridge.read_pull_facts(reader, "SFenton/other", 203)
        self.assertFalse(decoded["ok"])
        self.assertEqual(
            decoded["dispositions"],
            [{"disposition": "held", "reason": "pull_read_failed"}],
        )
        self.assertEqual(reader.unexpected_calls, [[
            "pr", "view", "203", "-R", "SFenton/other",
            "--json", EXPECTED_PULL_FIELDS,
        ]])


if __name__ == "__main__":
    unittest.main()
