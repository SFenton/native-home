"""Offline contract for sanitized Copilot hook evidence.

The fixtures record synthetic CLI and ACP parent/child probes. A hook-on run must
show a denied marker absent and an allowed marker present, while a hook-off run
shows both operations succeeding. The current probe could not keep configuration
isolated and retain an authorized provider, so every cell is ``not_exercised``;
that unproved state blocks widening route authority. Model and effort requests are
not evidence and remain ``unknown`` unless a session reports them.

CI parses only the closed enum-only JSON. It never starts Copilot, reads a real
session, or accepts a raw transcript, argument, environment value, path or error.
"""

from __future__ import annotations

import copy
import json
import re
import unittest
from pathlib import Path
from typing import Any, Dict, Mapping, Sequence, Tuple


HERE = Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures" / "copilot"
SCHEMA_VERSION = 1
TOP_FIELDS = {
    "schema_version",
    "cli_version",
    "surface",
    "role",
    "hook_state",
    "status",
    "reason",
    "observed_role",
    "observed_model",
    "observed_effort",
    "attempts",
}
ATTEMPT_FIELDS = {
    "operation",
    "event",
    "tool",
    "input_type",
    "hook_decision",
    "effect",
    "marker",
}
SURFACES = {"cli", "acp"}
ROLES = {"parent", "child"}
HOOK_STATES = {"on", "off"}
STATUSES = {"observed", "unsupported", "not_exercised"}
REASONS = {
    "none",
    "isolated_auth_unavailable",
    "surface_unavailable",
    "child_route_unavailable",
}
OBSERVED_ROLES = ROLES | {"unknown"}
OBSERVED_MODELS = {"mai-code-2-flash", "unknown"}
OBSERVED_EFFORTS = {"low", "unknown"}
OPERATIONS = {"deny_marker", "allow_marker"}
EVENTS = {"pre_tool_use", "not_present"}
TOOLS = {"bash"}
INPUT_TYPES = {"object"}
HOOK_DECISIONS = {"deny", "allow", "not_present"}
EFFECTS = {"denied", "allowed"}
MARKERS = {"absent", "present"}
VERSION_RE = re.compile(r"\A[0-9]+\.[0-9]+\.[0-9]+\Z")
CELLS = {(surface, role) for surface in SURFACES for role in ROLES}
RUNS = {(surface, role, state) for surface, role in CELLS for state in HOOK_STATES}
EXPECTED_FILES = {
    f"{surface}-{role}-hook-{state}.json"
    for surface, role, state in RUNS
}


class FixtureError(ValueError):
    """The sanitized fixture does not satisfy the closed evidence contract."""


def _reject_duplicate_fields(pairs: Sequence[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise FixtureError("duplicate field")
        result[key] = value
    return result


def load_fixture(path: Path) -> Dict[str, Any]:
    """Load one fixture without duplicate keys or non-object JSON roots."""
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_reject_duplicate_fields,
        )
    except (json.JSONDecodeError, OSError) as error:
        raise FixtureError("invalid fixture") from error
    if not isinstance(value, dict):
        raise FixtureError("fixture must be an object")
    return value


def _require_fields(value: Mapping[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        raise FixtureError(f"{label} fields differ")


def _require_enum(
    value: Mapping[str, Any], field: str, allowed: set[str], label: str
) -> None:
    item = value[field]
    if not isinstance(item, str) or item not in allowed:
        raise FixtureError(f"{label} {field} is not allowlisted")


def validate_record(record: Mapping[str, Any]) -> None:
    """Validate one fixture's closed schema and local invariants."""
    _require_fields(record, TOP_FIELDS, "record")
    if type(record["schema_version"]) is not int or record["schema_version"] != SCHEMA_VERSION:
        raise FixtureError("unsupported schema version")
    version = record["cli_version"]
    if not isinstance(version, str) or not VERSION_RE.fullmatch(version):
        raise FixtureError("invalid CLI version")
    _require_enum(record, "surface", SURFACES, "record")
    _require_enum(record, "role", ROLES, "record")
    _require_enum(record, "hook_state", HOOK_STATES, "record")
    _require_enum(record, "status", STATUSES, "record")
    _require_enum(record, "reason", REASONS, "record")
    _require_enum(record, "observed_role", OBSERVED_ROLES, "record")
    _require_enum(record, "observed_model", OBSERVED_MODELS, "record")
    _require_enum(record, "observed_effort", OBSERVED_EFFORTS, "record")

    attempts = record["attempts"]
    if not isinstance(attempts, list):
        raise FixtureError("attempts must be an array")
    if record["status"] != "observed":
        if attempts:
            raise FixtureError("unproved run has attempts")
        if record["reason"] == "none":
            raise FixtureError("unproved run lacks a reason")
        if (
            record["observed_role"] != "unknown"
            or record["observed_model"] != "unknown"
            or record["observed_effort"] != "unknown"
        ):
            raise FixtureError("unproved run claims observed identity")
        return

    if record["reason"] != "none":
        raise FixtureError("observed run has an unavailability reason")
    if len(attempts) != 2:
        raise FixtureError("observed run must have two attempts")
    if record["observed_role"] not in {record["role"], "unknown"}:
        raise FixtureError("observed role disagrees with the cell")
    by_operation: Dict[str, Mapping[str, Any]] = {}
    for index, attempt in enumerate(attempts):
        if not isinstance(attempt, dict):
            raise FixtureError("attempt must be an object")
        _require_fields(attempt, ATTEMPT_FIELDS, f"attempt {index}")
        _require_enum(attempt, "operation", OPERATIONS, f"attempt {index}")
        _require_enum(attempt, "event", EVENTS, f"attempt {index}")
        _require_enum(attempt, "tool", TOOLS, f"attempt {index}")
        _require_enum(attempt, "input_type", INPUT_TYPES, f"attempt {index}")
        _require_enum(attempt, "hook_decision", HOOK_DECISIONS, f"attempt {index}")
        _require_enum(attempt, "effect", EFFECTS, f"attempt {index}")
        _require_enum(attempt, "marker", MARKERS, f"attempt {index}")
        if attempt["operation"] in by_operation:
            raise FixtureError("operation appears more than once")
        by_operation[attempt["operation"]] = attempt
    if set(by_operation) != OPERATIONS:
        raise FixtureError("observed run misses an operation")

    if record["hook_state"] == "on":
        expected = {
            "deny_marker": {
                "event": "pre_tool_use",
                "hook_decision": "deny",
                "effect": "denied",
                "marker": "absent",
            },
            "allow_marker": {
                "event": "pre_tool_use",
                "hook_decision": "allow",
                "effect": "allowed",
                "marker": "present",
            },
        }
    else:
        expected = {
            operation: {
                "event": "not_present",
                "hook_decision": "not_present",
                "effect": "allowed",
                "marker": "present",
            }
            for operation in OPERATIONS
        }
    for operation, invariant in expected.items():
        attempt = by_operation[operation]
        if attempt["tool"] != "bash" or attempt["input_type"] != "object":
            raise FixtureError("observed call has inconsistent tool or input type")
        for field, expected_value in invariant.items():
            if attempt[field] != expected_value:
                raise FixtureError(f"operation {operation} has inconsistent {field}")


def validate_records(records: Mapping[Tuple[str, str, str], Mapping[str, Any]]) -> None:
    """Validate cell completeness and the paired hook-off control."""
    if set(records) != RUNS:
        raise FixtureError("missing or extra cell run")
    for key in RUNS:
        record = records[key]
        validate_record(record)
        if (record["surface"], record["role"], record["hook_state"]) != key:
            raise FixtureError("cell identity disagrees with record key")
    for surface, role in CELLS:
        hook_on = records[(surface, role, "on")]
        hook_off = records[(surface, role, "off")]
        if hook_on["status"] == "observed" and hook_off["status"] != "observed":
            raise FixtureError("observed hook denial lacks a hook-off control")


def load_fixture_set(directory: Path = FIXTURES) -> Dict[Tuple[str, str, str], Dict[str, Any]]:
    """Read exactly the eight permitted fixture files."""
    if not directory.is_dir():
        raise FixtureError("fixture directory is missing")
    entries = list(directory.iterdir())
    if any(entry.is_symlink() or entry.is_dir() for entry in entries):
        raise FixtureError("fixture directory contains a non-file entry")
    names = {entry.name for entry in entries}
    if names != EXPECTED_FILES:
        raise FixtureError("fixture file set differs")
    records: Dict[Tuple[str, str, str], Dict[str, Any]] = {}
    for path in entries:
        record = load_fixture(path)
        validate_record(record)
        key = (record["surface"], record["role"], record["hook_state"])
        if key in records:
            raise FixtureError("duplicate cell run")
        records[key] = record
    validate_records(records)
    return records


def _base_observed_pair() -> Dict[Tuple[str, str, str], Dict[str, Any]]:
    records = copy.deepcopy(load_fixture_set())
    on = records[("cli", "parent", "on")]
    off = records[("cli", "parent", "off")]
    on.update(
        {
            "status": "observed",
            "reason": "none",
            "observed_role": "parent",
            "observed_model": "mai-code-2-flash",
            "observed_effort": "low",
            "attempts": [
                {
                    "operation": "deny_marker",
                    "event": "pre_tool_use",
                    "tool": "bash",
                    "input_type": "object",
                    "hook_decision": "deny",
                    "effect": "denied",
                    "marker": "absent",
                },
                {
                    "operation": "allow_marker",
                    "event": "pre_tool_use",
                    "tool": "bash",
                    "input_type": "object",
                    "hook_decision": "allow",
                    "effect": "allowed",
                    "marker": "present",
                },
            ],
        }
    )
    off.update(
        {
            "status": "observed",
            "reason": "none",
            "observed_role": "parent",
            "observed_model": "mai-code-2-flash",
            "observed_effort": "low",
            "attempts": [
                {
                    "operation": operation,
                    "event": "not_present",
                    "tool": "bash",
                    "input_type": "object",
                    "hook_decision": "not_present",
                    "effect": "allowed",
                    "marker": "present",
                }
                for operation in ("deny_marker", "allow_marker")
            ],
        }
    )
    return records


class FixtureSetTests(unittest.TestCase):
    def test_repository_fixtures_are_closed_and_complete(self) -> None:
        records = load_fixture_set()
        self.assertEqual(set(records), RUNS)
        self.assertTrue(
            all(record["status"] == "not_exercised" for record in records.values())
        )

    def test_missing_cell_is_rejected(self) -> None:
        records = _base_observed_pair()
        del records[("acp", "child", "off")]
        with self.assertRaises(FixtureError):
            validate_records(records)

    def test_observed_on_and_off_pair_is_accepted(self) -> None:
        validate_records(_base_observed_pair())

    def test_extra_field_is_rejected(self) -> None:
        records = _base_observed_pair()
        records[("cli", "parent", "on")]["raw_transcript"] = "value"
        with self.assertRaises(FixtureError):
            validate_records(records)

    def test_unallowlisted_raw_value_is_rejected(self) -> None:
        records = _base_observed_pair()
        records[("cli", "parent", "on")]["observed_model"] = "../private"
        with self.assertRaises(FixtureError):
            validate_records(records)

    def test_invalid_version_is_rejected(self) -> None:
        records = _base_observed_pair()
        records[("cli", "parent", "on")]["cli_version"] = "v-next/path"
        with self.assertRaises(FixtureError):
            validate_records(records)

    def test_unproved_run_cannot_claim_attempts_or_identity(self) -> None:
        records = _base_observed_pair()
        record = records[("acp", "parent", "on")]
        record["observed_role"] = "parent"
        with self.assertRaises(FixtureError):
            validate_records(records)

    def test_observed_denial_requires_hook_off_control(self) -> None:
        records = _base_observed_pair()
        records[("cli", "parent", "off")]["status"] = "not_exercised"
        records[("cli", "parent", "off")]["attempts"] = []
        records[("cli", "parent", "off")]["reason"] = "isolated_auth_unavailable"
        records[("cli", "parent", "off")]["observed_role"] = "unknown"
        records[("cli", "parent", "off")]["observed_model"] = "unknown"
        records[("cli", "parent", "off")]["observed_effort"] = "unknown"
        with self.assertRaises(FixtureError):
            validate_records(records)

    def test_reversed_or_inconsistent_effects_are_rejected(self) -> None:
        mutations = (
            ("on", 0, "effect", "allowed"),
            ("on", 0, "marker", "present"),
            ("on", 1, "effect", "denied"),
            ("on", 1, "marker", "absent"),
            ("off", 0, "effect", "denied"),
            ("off", 0, "marker", "absent"),
        )
        for state, index, field, value in mutations:
            with self.subTest(state=state, field=field):
                records = _base_observed_pair()
                attempts = records[("cli", "parent", state)]["attempts"]
                attempts[index][field] = value
                with self.assertRaises(FixtureError):
                    validate_records(records)

    def test_duplicate_json_fields_are_rejected(self) -> None:
        with self.assertRaises(FixtureError):
            json.loads(
                '{"schema_version": 1, "schema_version": 1}',
                object_pairs_hook=_reject_duplicate_fields,
            )


if __name__ == "__main__":
    unittest.main()
