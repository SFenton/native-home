"""Pure pull-request bridge shapes for the triage runner.

This module has no runner wiring. Importing it reads no files, contacts no host and grants no authority. Callers explicitly invoke
the injected reader and then decide whether a result is usable.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

LANE_LIMIT = 5
PULL_FILES_CAP = 100
OWNER_LOGIN = "SFenton"
PR_REPOSITORY = "SFenton/native-home"
PULL_FIELDS = (
    "number,state,mergedAt,mergeCommit,headRefOid,headRefName,baseRefName,"
    "isDraft,isCrossRepository,author,reviewDecision,mergeStateStatus,mergeable,"
    "files,statusCheckRollup,createdAt"
)

_LANE_RE = re.compile(r"^agents/[A-Za-z0-9][A-Za-z0-9._/-]*$")
_BASE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")
_REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
_SHA_RE = re.compile(r"[0-9a-f]{40}")
_GOOD_CHECKS = frozenset(("SUCCESS", "NEUTRAL", "SKIPPED"))
_PENDING_CHECKS = frozenset(
    ("", "NONE", "QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED", "EXPECTED")
)


def canonical_lane(value: object) -> bool:
    """Whether ``value`` is accepted by the lander's lane checks and is canonical."""
    if not isinstance(value, str) or _LANE_RE.fullmatch(value) is None:
        return False
    if ".." in value or "//" in value or value.endswith(("/", ".lock", ".")):
        return False
    if any(component.startswith(".") for component in value.split("/")[1:]):
        return False
    return True


def _canonical_base(value: object) -> bool:
    return (
        isinstance(value, str)
        and _BASE_RE.fullmatch(value) is not None
        and ".." not in value
        and "//" not in value
        and not value.endswith(("/", ".", ".lock"))
    )


def _valid_sha(value: object) -> bool:
    return isinstance(value, str) and _SHA_RE.fullmatch(value) is not None


def _item_disposition(source: str, index: int, disposition: str, reason: str,
                      branch: Optional[str] = None) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "source": source,
        "index": index,
        "disposition": disposition,
        "reason": reason,
    }
    if branch is not None:
        result["branch"] = branch
    return result


def normalize_status(status: object) -> Dict[str, Any]:
    """Normalize legacy ``lanes`` strings and ``pulls`` objects into one stable inventory.

    Every malformed, conflicting and surplus source item has a visible disposition. The result is data only; it does not adopt a
    branch or pull request.
    """
    if not isinstance(status, dict):
        return {
            "records": [],
            "dispositions": [
                _item_disposition("status", 0, "invalid", "invalid_collection")
            ],
        }

    valid_items: List[Dict[str, Any]] = []
    decisions: Dict[int, Optional[Dict[str, Any]]] = {}
    sequence = 0

    def invalid(source: str, index: int, reason: str, branch: Optional[str] = None) -> None:
        nonlocal sequence
        decisions[sequence] = _item_disposition(source, index, "invalid", reason, branch)
        sequence += 1

    for source in ("lanes", "pulls"):
        if source not in status:
            continue
        collection = status[source]
        if not isinstance(collection, list):
            invalid(source, 0, "invalid_collection")
            continue
        for index, item in enumerate(collection):
            if source == "lanes":
                branch = item
                record: Optional[Dict[str, Any]] = None
                if not isinstance(item, str):
                    invalid(source, index, "invalid_item")
                elif not canonical_lane(item):
                    invalid(source, index, "invalid_branch")
                else:
                    record = {"branch": item}
            else:
                if not isinstance(item, dict):
                    invalid(source, index, "invalid_item")
                    continue
                if any(key not in ("branch", "pr", "head") for key in item):
                    invalid(source, index, "unknown_object_key",
                            item.get("branch") if isinstance(item.get("branch"), str) else None)
                    continue
                branch = item.get("branch")
                if not canonical_lane(branch):
                    invalid(source, index, "invalid_branch")
                    continue
                pr = item.get("pr")
                if "pr" in item and (type(pr) is not int or pr <= 0):
                    invalid(source, index, "invalid_pr", branch)
                    continue
                head = item.get("head")
                if "head" in item and not _valid_sha(head):
                    invalid(source, index, "invalid_head", branch)
                    continue
                record = {"branch": branch}
                if "pr" in item:
                    record["pr"] = pr
                if "head" in item:
                    record["head"] = head
            if record is not None:
                entry = {
                    "sequence": sequence,
                    "source": source,
                    "index": index,
                    "record": record,
                }
                valid_items.append(entry)
                decisions[sequence] = None
                sequence += 1

    groups: Dict[str, List[Dict[str, Any]]] = {}
    order: List[str] = []
    for entry in valid_items:
        branch = entry["record"]["branch"]
        if branch not in groups:
            groups[branch] = []
            order.append(branch)
        groups[branch].append(entry)

    records: List[Dict[str, Any]] = []
    accepted_count = 0
    for branch in order:
        entries = groups[branch]
        prs = {entry["record"]["pr"] for entry in entries if "pr" in entry["record"]}
        heads = {entry["record"]["head"] for entry in entries if "head" in entry["record"]}
        conflict = len(prs) > 1 or len(heads) > 1
        if conflict:
            for entry in entries:
                disposition = _item_disposition(
                    entry["source"], entry["index"], "conflict", "conflicting_hints", branch
                )
                _set_decision(decisions, entry["sequence"], disposition)
            continue
        if accepted_count >= LANE_LIMIT:
            for entry in entries:
                disposition = _item_disposition(
                    entry["source"], entry["index"], "surplus", "lane_limit", branch
                )
                _set_decision(decisions, entry["sequence"], disposition)
            continue

        record: Dict[str, Any] = {"branch": branch}
        if prs:
            record["pr"] = next(iter(prs))
        if heads:
            record["head"] = next(iter(heads))
        records.append(record)
        accepted_count += 1
        for offset, entry in enumerate(entries):
            disposition = _item_disposition(
                entry["source"],
                entry["index"],
                "accepted" if offset == 0 else "duplicate",
                "normalized" if offset == 0 else "consistent_duplicate",
                branch,
            )
            _set_decision(decisions, entry["sequence"], disposition)

    dispositions = [
        decisions[position] for position in sorted(decisions)
        if decisions[position] is not None
    ]
    return {"records": records, "dispositions": dispositions}


def _set_decision(decisions: Dict[int, Optional[Dict[str, Any]]],
                  sequence: int, disposition: Dict[str, Any]) -> None:
    if sequence in decisions and decisions[sequence] is None:
        decisions[sequence] = disposition


def normalise_status(status: object) -> Dict[str, Any]:
    """British spelling for :func:`normalize_status`."""
    return normalize_status(status)


def normalize_lane_records(status: object) -> Dict[str, Any]:
    """Compatibility name for normalizing a status inventory."""
    return normalize_status(status)


def normalize_lanes(lanes: object, pulls: object = None) -> Dict[str, Any]:
    """Normalize an explicit ``lanes``/``pulls`` pair, or one complete status mapping."""
    if pulls is None and isinstance(lanes, dict):
        return normalize_status(lanes)
    return normalize_status({"lanes": lanes, "pulls": [] if pulls is None else pulls})


def _held_facts(reason: str) -> Dict[str, Any]:
    return {
        "ok": False,
        "facts": None,
        "dispositions": [{"disposition": "held", "reason": reason}],
    }


def _decode_check(entry: object) -> Optional[Dict[str, Any]]:
    if not isinstance(entry, dict):
        return None
    name = entry.get("name") if isinstance(entry.get("name"), str) else entry.get("context")
    if not isinstance(name, str) or not name:
        return None
    state = entry.get("state")
    conclusion = entry.get("conclusion")
    status = entry.get("status")
    if state is not None and not isinstance(state, str):
        return None
    if conclusion is not None and not isinstance(conclusion, str):
        return None
    if status is not None and not isinstance(status, str):
        return None
    return {
        "name": name,
        "state": str(state or ""),
        "status": str(status or ""),
        "conclusion": str(conclusion or ""),
        "started_at": entry.get("startedAt") or entry.get("started_at") or "",
        "completed_at": entry.get("completedAt") or entry.get("completed_at") or "",
        "head_sha": entry.get("head_sha") or entry.get("headSha") or "",
        "app_id": ((entry.get("app") or {}).get("id")
                   if isinstance(entry.get("app"), dict) else entry.get("app_id")),
    }


def _decode_reviews(reviews: object) -> Tuple[List[Dict[str, Any]], bool]:
    if not isinstance(reviews, list):
        return [], False
    decoded: List[Dict[str, Any]] = []
    complete = True
    for index, review in enumerate(reviews):
        if not isinstance(review, dict):
            complete = False
            continue
        user = review.get("user")
        login = user.get("login") if isinstance(user, dict) else None
        state = review.get("state")
        head = review.get("commit_id") or review.get("commitId")
        if not isinstance(login, str) or not login or not isinstance(state, str):
            complete = False
            continue
        if head is not None and not _valid_sha(head):
            complete = False
            continue
        submitted = review.get("submitted_at") or review.get("submittedAt") or ""
        review_id = review.get("id")
        decoded.append({
            "login": login,
            "state": state,
            "head": head,
            "submitted_at": str(submitted or ""),
            "id": review_id if type(review_id) is int else 0,
            "index": index,
        })
    return decoded, complete


def _decode_commit(commit: object) -> Tuple[Optional[Dict[str, Any]], bool]:
    if not isinstance(commit, dict):
        return None, False
    sha = commit.get("sha")
    parents = commit.get("parents")
    committer = commit.get("committer")
    inner = commit.get("commit")
    if not _valid_sha(sha) or not isinstance(parents, list) or \
            not isinstance(committer, dict) or not isinstance(inner, dict):
        return None, False
    parent_shas = []
    complete = True
    for parent in parents:
        value = parent.get("sha") if isinstance(parent, dict) else None
        if not _valid_sha(value):
            complete = False
            continue
        parent_shas.append(value)
    verification = inner.get("verification")
    if not isinstance(verification, dict):
        verification = {}
        complete = False
    return {
        "sha": sha,
        "parents": parent_shas,
        "parent_count": len(parents),
        "committer_login": committer.get("login"),
        "verification": {
            "verified": verification.get("verified"),
            "reason": verification.get("reason"),
        },
    }, complete


def _decode_associated_pulls(rows: object) -> Tuple[List[Dict[str, Any]], bool]:
    if not isinstance(rows, list):
        return [], False
    result = []
    complete = True
    for row in rows:
        if not isinstance(row, dict):
            complete = False
            continue
        number = row.get("number")
        base_value = row.get("base")
        base = base_value.get("ref") if isinstance(base_value, dict) else row.get("baseRefName")
        merge_sha = row.get("merge_commit_sha")
        if merge_sha is None:
            merge_commit = row.get("mergeCommit")
            merge_sha = merge_commit.get("oid") if isinstance(merge_commit, dict) else None
        if type(number) is not int or number <= 0 or not isinstance(base, str):
            complete = False
            continue
        result.append({
            "number": number,
            "base": base,
            "merge_sha": merge_sha,
        })
    return result, complete


def decode_pull_facts(pull: object, reviews: object = None, commit: object = None,
                      associated_pulls: object = None) -> Dict[str, Any]:
    """Validate a pull-request answer and return its normalized facts or a held disposition."""
    if not isinstance(pull, dict):
        return _held_facts("malformed_pull")
    number = pull.get("number")
    if type(number) is not int or number <= 0:
        return _held_facts("invalid_pull_number")
    state = pull.get("state")
    if state not in ("OPEN", "CLOSED", "MERGED"):
        return _held_facts("invalid_pull_state")
    head = pull.get("headRefOid")
    if not _valid_sha(head):
        return _held_facts("invalid_head")
    branch = pull.get("headRefName")
    if not canonical_lane(branch):
        return _held_facts("invalid_branch")
    base = pull.get("baseRefName")
    if not _canonical_base(base):
        return _held_facts("invalid_base")
    if type(pull.get("isDraft")) is not bool or type(pull.get("isCrossRepository")) is not bool:
        return _held_facts("invalid_pull_flags")
    author = pull.get("author")
    author_login = author.get("login") if isinstance(author, dict) else None
    if not isinstance(author_login, str) or not author_login:
        return _held_facts("invalid_author")
    for field in ("reviewDecision", "mergeStateStatus", "mergeable"):
        if not isinstance(pull.get(field), str):
            return _held_facts("invalid_" + field.lower())
    files = pull.get("files")
    if not isinstance(files, list):
        return _held_facts("invalid_file_list")
    paths = []
    for item in files:
        path = item.get("path") if isinstance(item, dict) else item
        if not isinstance(path, str) or not path:
            return _held_facts("invalid_file_list")
        paths.append(path)
    checks_raw = pull.get("statusCheckRollup")
    if not isinstance(checks_raw, list):
        return _held_facts("invalid_check_rollup")
    checks = []
    for item in checks_raw:
        decoded = _decode_check(item)
        if decoded is None:
            return _held_facts("invalid_check_rollup")
        checks.append(decoded)
    merged_at = pull.get("mergedAt")
    if merged_at is not None and not isinstance(merged_at, str):
        return _held_facts("invalid_merged_at")
    merge_commit = pull.get("mergeCommit")
    merge_sha = None
    if merge_commit is not None:
        if not isinstance(merge_commit, dict) or not _valid_sha(merge_commit.get("oid")):
            return _held_facts("invalid_merge_commit")
        merge_sha = merge_commit.get("oid")
    if state == "MERGED" and (not merged_at or merge_sha is None):
        return _held_facts("incomplete_merged_pull")
    if state == "CLOSED" and (merged_at is not None or merge_sha is not None):
        return _held_facts("inconsistent_closed_pull")

    decoded_reviews, reviews_complete = _decode_reviews([] if reviews is None else reviews)
    decoded_commit: Optional[Dict[str, Any]] = None
    commit_complete = True
    if commit is not None:
        decoded_commit, commit_complete = _decode_commit(commit)
    associated, associated_complete = _decode_associated_pulls(
        [] if associated_pulls is None else associated_pulls
    )
    return {
        "ok": True,
        "facts": {
            "number": number,
            "state": state,
            "merged_at": merged_at,
            "merge_sha": merge_sha,
            "head": head,
            "branch": branch,
            "base": base,
            "draft": pull["isDraft"],
            "cross_repository": pull["isCrossRepository"],
            "author": author_login,
            "review_decision": pull["reviewDecision"],
            "merge_state_status": pull["mergeStateStatus"],
            "mergeable": pull["mergeable"],
            "files": paths,
            "files_complete": len(paths) < PULL_FILES_CAP,
            "checks": checks,
            "reviews": decoded_reviews,
            "reviews_complete": reviews_complete,
            "commit": decoded_commit,
            "commit_complete": commit_complete,
            "associated_pulls": associated,
            "associated_pulls_complete": associated_complete,
        },
        "dispositions": [],
    }


def read_pull_facts(reader: Any, repo: str, number: int) -> Dict[str, Any]:
    """Read pull-request facts through an injected ``gh``-style callable.

    ``reader(argv)`` returns decoded JSON for each argument list. It performs no operation inside this module; failures become
    held facts with a fixed reason.
    """
    if not callable(reader):
        return _held_facts("reader_unavailable")
    if not isinstance(repo, str) or _REPO_RE.fullmatch(repo) is None or type(number) is not int or number <= 0:
        return _held_facts("invalid_reader_input")
    try:
        pull = reader([
            "pr", "view", str(number), "-R", repo, "--json", PULL_FIELDS,
        ])
    except Exception:  # noqa: BLE001 - the injected host seam is an explicit fail-closed boundary
        return _held_facts("pull_read_failed")
    preliminary = decode_pull_facts(pull)
    if not preliminary["ok"]:
        return preliminary
    facts = preliminary["facts"]
    if facts["number"] != number:
        return _held_facts("wrong_pull_request")
    reviews = []
    commit = None
    associated = []
    try:
        if facts["state"] == "OPEN":
            reviews = reader([
                "api",
                f"repos/{repo}/pulls/{number}/reviews",
                "--paginate",
            ])
        elif facts["state"] == "MERGED":
            commit = reader(["api", f"repos/{repo}/commits/{facts['merge_sha']}"])
            associated = reader(["api", f"repos/{repo}/commits/{facts['merge_sha']}/pulls"])
    except Exception:  # noqa: BLE001 - a missing supplemental fact cannot establish a result
        return _held_facts("supplemental_read_failed")
    return decode_pull_facts(pull, reviews, commit, associated)


def _as_facts(value: object) -> Optional[Dict[str, Any]]:
    if not isinstance(value, dict):
        return None
    if "ok" in value:
        return value.get("facts") if value.get("ok") is True else None
    if "headRefOid" in value:
        decoded = decode_pull_facts(value)
        return decoded.get("facts") if decoded.get("ok") else None
    return value


def _check_result(facts: Mapping[str, Any], name: str) -> str:
    found = [
        (index, check) for index, check in enumerate(facts.get("checks") or [])
        if check.get("name") == name
    ]
    if not found:
        return "missing"
    _index, newest = max(
        found,
        key=lambda pair: (
            str(pair[1].get("completed_at") or pair[1].get("started_at") or ""),
            pair[0],
        ),
    )
    result = str(newest.get("conclusion") or newest.get("state") or "").upper()
    if newest.get("status") not in ("", "COMPLETED") or result in _PENDING_CHECKS:
        return "pending"
    return "success" if result in _GOOD_CHECKS else "failure"


def _owner_approved(facts: Mapping[str, Any], owner_login: str) -> bool:
    latest: Dict[str, Dict[str, Any]] = {}
    for review in facts.get("reviews") or []:
        login = str(review.get("login") or "").lower()
        if not login:
            continue
        candidate = review
        previous = latest.get(login)
        if previous is None or (
            str(candidate.get("submitted_at") or ""),
            int(candidate.get("id") or 0),
            int(candidate.get("index") or 0),
        ) > (
            str(previous.get("submitted_at") or ""),
            int(previous.get("id") or 0),
            int(previous.get("index") or 0),
        ):
            latest[login] = candidate
    owner = latest.get(owner_login.lower())
    return bool(
        owner
        and owner.get("state") == "APPROVED"
        and owner.get("head") == facts.get("head")
    )


def classify_phase(value: object, *, owner_required: Optional[bool] = None,
                   owner_login: str = OWNER_LOGIN, reviewed_head: Optional[str] = None,
                   expected_branch: Optional[str] = None, expected_base: Optional[str] = None,
                   reviews: object = None) -> Dict[str, str]:
    """Classify a validated pull request without acting on it."""
    facts = _as_facts(value)
    if facts is None:
        return {"phase": "held", "reason": "invalid_facts"}
    if reviews is not None:
        decoded_reviews, complete = _decode_reviews(reviews)
        facts = dict(facts)
        facts["reviews"] = decoded_reviews
        facts["reviews_complete"] = complete
    state = facts.get("state")
    if state == "MERGED":
        return {"phase": "merged", "reason": "server_merge"}
    if state == "CLOSED":
        if facts.get("merged_at") is None and facts.get("merge_sha") is None:
            return {"phase": "closed_unmerged", "reason": "closed_without_merge"}
        return {"phase": "held", "reason": "inconsistent_closed_pull"}
    if state != "OPEN":
        return {"phase": "held", "reason": "invalid_pull_state"}
    if facts.get("cross_repository") is True:
        return {"phase": "held", "reason": "cross_repository"}
    if expected_branch is not None and facts.get("branch") != expected_branch:
        return {"phase": "held", "reason": "branch_mismatch"}
    if expected_base is not None and facts.get("base") != expected_base:
        return {"phase": "held", "reason": "base_mismatch"}
    if reviewed_head is not None and (
        not _valid_sha(reviewed_head) or facts.get("head") != reviewed_head
    ):
        return {"phase": "needs_review", "reason": "head_moved"}
    if facts.get("mergeable") == "CONFLICTING":
        return {"phase": "actionable", "reason": "merge_conflict"}
    pr_checks = _check_result(facts, "pr-checks")
    ai_review = _check_result(facts, "ai-review")
    if pr_checks == "failure":
        return {"phase": "actionable", "reason": "pr_checks_failed"}
    if ai_review == "failure":
        return {"phase": "actionable", "reason": "ai_review_failed"}
    if pr_checks == "pending":
        return {"phase": "awaiting_checks", "reason": "pr_checks_pending"}
    if pr_checks == "missing":
        return {"phase": "awaiting_checks", "reason": "pr_checks_missing"}
    if ai_review == "pending":
        return {"phase": "needs_review", "reason": "ai_review_pending"}
    if ai_review == "missing":
        return {"phase": "needs_review", "reason": "ai_review_missing"}
    if owner_required is None or type(owner_required) is not bool or (
        owner_required is False and facts.get("files_complete") is not True
    ):
        return {"phase": "held", "reason": "ownership_unknown"}
    if owner_required:
        if facts.get("reviews_complete") is not True:
            return {"phase": "owner_wait", "reason": "owner_review_unreadable"}
        if not _owner_approved(facts, owner_login):
            return {"phase": "owner_wait", "reason": "owner_review_required"}
    if facts.get("draft") is True:
        return {"phase": "owner_wait", "reason": "draft"}
    return {"phase": "awaiting_merge", "reason": "approved_and_green"}


def build_accounting_record(value: object, *, repo: str, expected_pr: int,
                            expected_base: str, reviewed_head: Optional[str] = None) -> Dict[str, Any]:
    """Build an explicit accounting disposition for a verified GitHub squash."""
    facts = _as_facts(value)

    def held(reason: str) -> Dict[str, Any]:
        return {"disposition": "held", "reason": reason, "key": None, "record": None}

    if facts is None:
        return held("invalid_facts")
    if facts.get("state") != "MERGED" or facts.get("merged_at") is None:
        return held("not_merged")
    if type(expected_pr) is not int or expected_pr <= 0 or facts.get("number") != expected_pr:
        return held("wrong_pull_request")
    if not _canonical_base(expected_base) or facts.get("base") != expected_base:
        return held("wrong_base")
    if not isinstance(repo, str) or _REPO_RE.fullmatch(repo) is None:
        return held("invalid_repository")
    merge_sha = facts.get("merge_sha")
    if not _valid_sha(merge_sha):
        return held("merge_sha_missing")
    head = facts.get("head")
    if not _valid_sha(head):
        return held("merge_head_missing")
    if not _valid_sha(reviewed_head):
        return held("reviewed_head_missing")
    commit = facts.get("commit")
    if commit is None or facts.get("commit_complete") is not True:
        return held("commit_unreadable")
    if commit.get("sha") != merge_sha:
        return held("commit_mismatch")
    if commit.get("parent_count") != 1:
        return held("parent_count")
    if commit.get("committer_login") != "web-flow":
        return held("committer_not_github")
    verification = commit.get("verification") or {}
    if verification.get("verified") is not True or verification.get("reason") != "valid":
        return held("signature_unverified")
    associated = facts.get("associated_pulls") or []
    if associated and not any(
        item.get("number") == expected_pr
        and item.get("base") == expected_base
        and item.get("merge_sha") == merge_sha
        for item in associated
    ):
        return held("wrong_pull_request")
    key = (repo, expected_pr, merge_sha)
    record = {
        "repo": repo,
        "pr": expected_pr,
        "merge_sha": merge_sha,
        "reviewed_head": reviewed_head,
        "head_at_merge": head,
        "base": expected_base,
        "kind": "squash",
        "merged_at": facts.get("merged_at"),
    }
    return {
        "disposition": "accounted",
        "reason": "verified_github_squash",
        "key": key,
        "record": record,
    }


def accounting_key(value: object, *, repo: str, expected_pr: int, expected_base: str,
                   reviewed_head: Optional[str] = None) -> Optional[Tuple[str, int, str]]:
    """Return the verified accounting key, or ``None`` while its disposition is held."""
    result = build_accounting_record(
        value,
        repo=repo,
        expected_pr=expected_pr,
        expected_base=expected_base,
        reviewed_head=reviewed_head,
    )
    return result["key"]


def revert_choice(parent_count: object, kind: Optional[str] = None) -> Dict[str, Any]:
    """Choose plain or mainline revert syntax from a verified commit's parent count."""
    if type(parent_count) is not int or parent_count not in (1, 2):
        return {
            "disposition": "held",
            "reason": "unexpected_parent_count",
            "arguments": None,
            "mainline": None,
        }
    if kind not in (None, "", "merge", "squash"):
        return {
            "disposition": "held",
            "reason": "unexpected_kind",
            "arguments": None,
            "mainline": None,
        }
    if parent_count == 1:
        return {
            "disposition": "ready",
            "reason": "single_parent",
            "arguments": (),
            "mainline": None,
        }
    if kind == "squash":
        return {
            "disposition": "held",
            "reason": "inconsistent_squash_parents",
            "arguments": None,
            "mainline": None,
        }
    return {
        "disposition": "ready",
        "reason": "legacy_merge_mainline",
        "arguments": ("-m", "1"),
        "mainline": 1,
    }


def revert_arguments(parent_count: object, kind: Optional[str] = None) -> Optional[Tuple[str, ...]]:
    """Return ready revert arguments, or ``None`` for a held parent shape."""
    choice = revert_choice(parent_count, kind)
    return choice["arguments"] if choice["disposition"] == "ready" else None
