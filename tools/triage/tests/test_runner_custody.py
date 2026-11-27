"""Load, admission, durable-save, containment and status tests for runner stores."""
from __future__ import annotations

import contextlib
import errno
import gc
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import test_hass_triage as t

ht = t.ht
FakeGitHub = t.FakeGitHub

ELIDED_PROMPT_ARGUMENTS = {
    "scheduled researcher": mock.ANY,
    "manual researcher": mock.ANY,
    "retro": mock.ANY,
    "request 71": mock.ANY,
    "request 70": mock.ANY,
    "request 81": mock.ANY,
}

_PA_ABSENT = object()
_PA_HEALTHY_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)
_PA_QUEUE_ERROR_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "queue: #None \n",
    "",
)
_PA_MALFORMED_NIGHTLY_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store nightly: parse (exists yes)\n"
    "queue: #None \n",
    "",
)
_PA_INVALID_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store request: phase (exists yes, scope record, version 1, "
    'key {"repository":"sfenton/native-home","intake":"request",'
    '"producer":"request:42","generation":"request-42-g1"})\n'
    "state store nightly: type (exists yes)\n"
    "queue: empty\n",
    "",
)
_PA_HEALTHY_JSON_FIELDS = {
    "queue": [],
    "nightly_queue": [],
    "state_loads": [],
    "retro_queue": [],
}
_PA_QUEUE_ERROR_JSON_FIELDS = {
    "queue": [{"error": "synthetic queue failure"}],
    "nightly_queue": [],
    "state_loads": [],
    "retro_queue": [],
}
_PA_MALFORMED_NIGHTLY_JSON_FIELDS = {
    "queue": [{"error": "synthetic queue failure"}],
    "nightly_queue": [],
    "state_loads": [{
        "store": "nightly",
        "kind": "parse",
        "exists": "yes",
    }],
    "retro_queue": [],
}
_PA_INVALID_JSON_FIELDS = {
    "queue": [],
    "nightly_queue": [],
    "state_loads": [
        {
            "store": "request",
            "kind": "phase",
            "exists": "yes",
            "scope": "record",
            "version": 1,
            "key": {
                "repository": "sfenton/native-home",
                "intake": "request",
                "producer": "request:42",
                "generation": "request-42-g1",
            },
        },
        {
            "store": "nightly",
            "kind": "type",
            "exists": "yes",
        },
    ],
    "retro_queue": [],
}
_PA_LEGACY_REPORT_KEYS = {
    "claude_logged_in",
    "launcher",
    "t3_ready",
    "t3_thread",
    "jobs",
    "parked",
    "nightly_queue",
    "paused",
    "self_changes",
    "installed",
    "lock_holder",
    "current",
    "merging",
    "queue",
    "ha_changes_unreachable_since",
    "ha_changes_unfiled",
    "archive_holds",
    "recent",
    "retro_queue",
    "state_loads",
}
_PA_DONE_OUTCOME = {
    "trust": "clean_end",
    "exit_code": 0,
    "state": "done",
}
_PA_UNKNOWN_NEXT = {"kind": "unknown"}
_PA_REQUEST_42_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "request",
    "producer": "request:42",
    "generation": "request-42-g1",
    "phase": "release_authorized",
    "original_outcome": _PA_DONE_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [],
    "notices": [],
}
_PA_NIGHTLY_52_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "nightly",
    "producer": "nightly:52",
    "generation": "nightly-52-g1",
    "phase": "release_authorized",
    "original_outcome": _PA_DONE_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [],
    "notices": [],
}
_PA_REQUEST_72_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "request",
    "producer": "request:72",
    "generation": "request-72-g1",
    "phase": "release_authorized",
    "original_outcome": _PA_DONE_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [],
    "notices": [],
}
_PA_NIGHTLY_72_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "nightly",
    "producer": "nightly:72",
    "generation": "nightly-72-g1",
    "phase": "release_authorized",
    "original_outcome": _PA_DONE_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [],
    "notices": [],
}
_PA_JOB_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "request",
    "producer": "job:researcher",
    "generation": "job-researcher-g1",
    "phase": "release_authorized",
    "original_outcome": _PA_DONE_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [],
    "notices": [],
}
_PA_RETRO_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "request",
    "producer": "retro:job-researcher-2026-11-23",
    "generation": "retro-job-researcher-2026-11-23-g1",
    "phase": "release_authorized",
    "original_outcome": _PA_DONE_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [],
    "notices": [],
}
_PA_REQUEST_42_PHASE_FAULT = {
    "store": "request",
    "kind": "phase",
    "scope": "record",
    "version": 1,
    "key": {
        "repository": "sfenton/native-home",
        "intake": "request",
        "producer": "request:42",
        "generation": "request-42-g1",
    },
    "exists": "yes",
}
_PA_EMPTY_CUSTODY = {
    "version": 1,
    "records": [],
    "faults": [],
}
_PA_REQUEST_42_CUSTODY = {
    "version": 1,
    "records": [_PA_REQUEST_42_RECORD],
    "faults": [],
}
_PA_NIGHTLY_52_CUSTODY = {
    "version": 1,
    "records": [_PA_NIGHTLY_52_RECORD],
    "faults": [],
}
_PA_SAME_NUMBER_72_CUSTODY = {
    "version": 1,
    "records": [
        _PA_NIGHTLY_72_RECORD,
        _PA_REQUEST_72_RECORD,
    ],
    "faults": [],
}
_PA_INTEGRATED_CUSTODY = {
    "version": 1,
    "records": [
        _PA_JOB_RECORD,
        _PA_RETRO_RECORD,
    ],
    "faults": [],
}
_PA_RETAINED_NIGHTLY_CUSTODY = {
    "version": 1,
    "records": [
        _PA_NIGHTLY_52_RECORD,
        _PA_REQUEST_42_RECORD,
    ],
    "faults": [],
}
_PA_REQUEST_72_CUSTODY = {
    "version": 1,
    "records": [_PA_REQUEST_72_RECORD],
    "faults": [],
}
_PA_INVALID_42_CUSTODY = {
    "version": 1,
    "records": [],
    "faults": [_PA_REQUEST_42_PHASE_FAULT],
}

_CT_REQUEST_42 = (
    "custody record sfenton/native-home request request:42 "
    "request-42-g1: phase release_authorized; original outcome "
    "clean_end/0/done; since 2026-11-23T12:00:00Z; age 0s; "
    "attempts unknown; reason unknown; next unknown; "
    "tree exists unknown\n"
)
_CT_NIGHTLY_52 = (
    "custody record sfenton/native-home nightly nightly:52 "
    "nightly-52-g1: phase release_authorized; original outcome "
    "clean_end/0/done; since 2026-11-23T12:00:00Z; age 0s; "
    "attempts unknown; reason unknown; next unknown; "
    "tree exists unknown\n"
)
_CT_REQUEST_72 = (
    "custody record sfenton/native-home request request:72 "
    "request-72-g1: phase release_authorized; original outcome "
    "clean_end/0/done; since 2026-11-23T12:00:00Z; age 0s; "
    "attempts unknown; reason unknown; next unknown; "
    "tree exists unknown\n"
)
_CT_NIGHTLY_72 = (
    "custody record sfenton/native-home nightly nightly:72 "
    "nightly-72-g1: phase release_authorized; original outcome "
    "clean_end/0/done; since 2026-11-23T12:00:00Z; age 0s; "
    "attempts unknown; reason unknown; next unknown; "
    "tree exists unknown\n"
)
_CT_JOB = (
    "custody record sfenton/native-home request job:researcher "
    "job-researcher-g1: phase release_authorized; original outcome "
    "clean_end/0/done; since 2026-11-23T12:00:00Z; age 0s; "
    "attempts unknown; reason unknown; next unknown; "
    "tree exists unknown\n"
)
_CT_RETRO = (
    "custody record sfenton/native-home request "
    "retro:job-researcher-2026-11-23 "
    "retro-job-researcher-2026-11-23-g1: phase release_authorized; "
    "original outcome clean_end/0/done; since 2026-11-23T12:00:00Z; "
    "age 0s; attempts unknown; reason unknown; next unknown; "
    "tree exists unknown\n"
)
_CT_TWO_BINDINGS_RECORD = (
    "custody record sfenton/native-home request request:42 "
    "request-42-g1: phase pending; original outcome clean_end/0/done; "
    "since 2026-11-23T12:00:00Z; age 0s; attempts 0; reason reserved; "
    "next human; tree exists unknown\n"
)
_CT_ALPHA_BINDING = (
    "custody binding sfenton/native-home request request:42 "
    "request-42-g1 agents/alpha [refs/heads/agents/alpha]: disposition "
    "owner_wait; tip aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; pull 7; "
    "reviewed head bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; reason "
    "non_owner_stall; since 2026-11-23T11:58:00Z; age 120s; attempts 2; "
    "next retry at 2026-11-23T13:00:00Z\n"
)
_CT_BETA_BINDING = (
    "custody binding sfenton/native-home request request:42 "
    "request-42-g1 agents/beta [refs/heads/agents/beta]: disposition "
    "needs_pr; tip absent; pull unknown; reviewed head unknown; reason "
    "ai_review_failed; since 2026-11-23T11:59:00Z; age 60s; attempts "
    "unknown; next retry\n"
)
_CT_SIGNED_RECORD_0 = (
    "custody record sfenton/native-home request request:42 "
    "request-42-g1: phase pending; original outcome "
    "untrusted/-7/unknown; since 2026-11-23T12:00:00Z; age 0s; "
    "attempts unknown; reason unknown; next unknown; "
    "tree exists unknown\n"
)
_CT_SIGNED_RECORD_3600 = (
    "custody record sfenton/native-home request request:42 "
    "request-42-g1: phase pending; original outcome "
    "untrusted/-7/unknown; since 2026-11-23T12:00:00Z; age 3600s; "
    "attempts unknown; reason unknown; next unknown; "
    "tree exists unknown\n"
)
_CT_REVIEW_BINDING_90 = (
    "custody binding sfenton/native-home request request:42 "
    "request-42-g1 agents/review [refs/heads/agents/review]: "
    "disposition awaiting_review_wiring; tip unreadable; pull unknown; "
    "reviewed head unknown; reason pr_checks_failed; since "
    "2026-11-23T11:58:00Z; age 90s; attempts 0; next unknown\n"
)
_CT_REVIEW_BINDING_120 = (
    "custody binding sfenton/native-home request request:42 "
    "request-42-g1 agents/review [refs/heads/agents/review]: "
    "disposition awaiting_review_wiring; tip unreadable; pull unknown; "
    "reviewed head unknown; reason pr_checks_failed; since "
    "2026-11-23T11:58:00Z; age 120s; attempts 0; next unknown\n"
)
_CT_REVIEW_BINDING_3720 = (
    "custody binding sfenton/native-home request request:42 "
    "request-42-g1 agents/review [refs/heads/agents/review]: "
    "disposition awaiting_review_wiring; tip unreadable; pull unknown; "
    "reviewed head unknown; reason pr_checks_failed; since "
    "2026-11-23T11:58:00Z; age 3720s; attempts 0; next unknown\n"
)
_CT_UNCERTAIN_NOTICE_30 = (
    "custody notice sfenton/native-home agents/review "
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb needs_pr: state uncertain; "
    "since 2026-11-23T11:59:00Z; age 30s; remote identity unknown "
    "(delivery uncertain)\n"
)
_CT_UNCERTAIN_NOTICE_60 = (
    "custody notice sfenton/native-home agents/review "
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb needs_pr: state uncertain; "
    "since 2026-11-23T11:59:00Z; age 60s; remote identity unknown "
    "(delivery uncertain)\n"
)
_CT_UNCERTAIN_NOTICE_3660 = (
    "custody notice sfenton/native-home agents/review "
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb needs_pr: state uncertain; "
    "since 2026-11-23T11:59:00Z; age 3660s; remote identity unknown "
    "(delivery uncertain)\n"
)
_CT_CONFIRMED_NOTICE_150 = (
    "custody notice sfenton/native-home agents/review "
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb non_owner_stall: state "
    "confirmed; since 2026-11-23T11:57:00Z; age 150s; remote identity "
    "private/issues#17\n"
)
_CT_CONFIRMED_NOTICE_180 = (
    "custody notice sfenton/native-home agents/review "
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb non_owner_stall: state "
    "confirmed; since 2026-11-23T11:57:00Z; age 180s; remote identity "
    "private/issues#17\n"
)
_CT_CONFIRMED_NOTICE_3780 = (
    "custody notice sfenton/native-home agents/review "
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb non_owner_stall: state "
    "confirmed; since 2026-11-23T11:57:00Z; age 3780s; remote identity "
    "private/issues#17\n"
)
_CT_SAFE_JAN_NOTICE = (
    "custody notice sfenton/native-home agents/safe "
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa needs_pr: state intent; "
    "since 2026-01-01T00:00:00Z; age 28209600s; remote identity unknown\n"
)
_CT_SAFE_NOON_NOTICE = (
    "custody notice sfenton/native-home agents/safe "
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa needs_pr: state intent; "
    "since 2026-11-23T11:59:00Z; age 60s; remote identity unknown\n"
)
_CT_UNBOUND_RECORD = (
    "custody record example/product request request:7 g1: phase unknown; "
    "original outcome unknown; since 2026-11-23T12:00:00Z; age 3600s; "
    "attempts unknown; reason unknown; next unknown; tree exists unknown\n"
)
_CT_UNBOUND_SAFE_NOTICE = (
    "custody notice example/product agents/safe "
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa needs_pr: state intent; "
    "since 2026-11-23T12:59:00Z; age 60s; remote identity unknown\n"
)
_CT_REQUEST_42_PHASE_FAULT = (
    "custody fault request: phase (exists yes, scope record, version 1, "
    'key {"repository":"sfenton/native-home","intake":"request",'
    '"producer":"request:42","generation":"request-42-g1"})\n'
)
_CT_REQUEST_43_PHASE_FAULT = (
    "custody fault request: phase (exists yes, scope record, version 1, "
    'key {"repository":"sfenton/native-home","intake":"request",'
    '"producer":"request:43","generation":"request-43-g1"})\n'
)
_CT_NIGHTLY_53_PHASE_FAULT = (
    "custody fault nightly: phase (exists yes, scope record, version 1, "
    'key {"repository":"sfenton/native-home","intake":"nightly",'
    '"producer":"nightly:53","generation":"nightly-53-g1"})\n'
)
_CT_REQUEST_NOTICE_FAULT = (
    "custody fault request: type (exists yes, scope notice, version 1, "
    'key {"repository":"sfenton/native-home","intake":"request",'
    '"producer":"request:42","generation":"request-42-g1",'
    '"lane":"agents/bad",'
    '"head":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",'
    '"fault_class":"needs_pr"})\n'
)
_CT_NIGHTLY_NOTICE_FAULT = (
    "custody fault nightly: type (exists yes, scope notice, version 1, "
    'key {"repository":"sfenton/native-home","intake":"nightly",'
    '"producer":"nightly:52","generation":"nightly-52-g1",'
    '"lane":"agents/bad",'
    '"head":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",'
    '"fault_class":"needs_pr"})\n'
)
_CT_RETRO_NAMESPACE_FAULT = (
    "custody fault retro: namespace (exists yes, scope store, "
    "version unknown, key unknown)\n"
)
_CT_REQUEST_43_TYPE_FAULT = (
    "custody fault request: type (exists yes, scope record, version 1, "
    'key {"repository":"sfenton/native-home","intake":"request",'
    '"producer":"request:43","generation":"request-43-g1"})\n'
)
_CT_SCOPED_STORE_TYPE_FAULT = (
    "custody fault request: type (exists yes, scope store, version 1, "
    "key unknown)\n"
)
_CT_UNSUPPORTED_REQUEST_VERSION_FAULT = (
    "custody fault request: version (exists yes, scope store, "
    "version unknown, key unknown)\n"
)
_CT_UNBOUND_NOTICE_FAULT = (
    "custody fault request: type (exists yes, scope notice, version 1, "
    'key {"repository":"example/product","intake":"request",'
    '"producer":"request:7","generation":"g1","lane":"agents/bad"})\n'
)
_CT_REPOSITORY_NAMESPACE_FAULT = (
    "custody fault request: namespace (exists yes, scope store, "
    "version 1, key unknown)\n"
)
_CT_GENERATION_KEY_FAULT = (
    "custody fault request: key (exists yes, scope record, version 1, "
    'key {"repository":"sfenton/native-home","intake":"request",'
    '"producer":"request:42"})\n'
)
_CT_L3_RECORD_1 = (
    "custody record sfenton/native-home request request:42 "
    "request-42-l3-g1: phase pending; original outcome "
    "untrusted/unknown/unknown; since 2026-11-23T12:00:00Z; age 0s; "
    "attempts 0; reason reserved; next human; tree exists unknown\n"
)
_CT_L3_BINDING_1 = (
    "custody binding sfenton/native-home request request:42 "
    "request-42-l3-g1 agents/review [refs/heads/agents/review]: "
    "disposition owner_wait; tip "
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; pull 7; reviewed head "
    "unknown; reason unknown; since 2026-11-23T11:59:00Z; age 60s; "
    "attempts 0; next retry at 2026-11-23T13:00:00Z\n"
)
_CT_L3_UNSENT_NOTICE = (
    "custody notice sfenton/native-home agents/review "
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb needs_pr: state unsent; "
    "since 2026-11-23T11:59:00Z; age 60s; remote identity unknown\n"
)
_CT_L3_RECORD_2 = (
    "custody record sfenton/native-home request request:42 "
    "request-42-l3-g2: phase pending; original outcome unknown; since "
    "2026-11-23T12:00:00Z; age 0s; attempts unknown; reason unknown; "
    "next unknown; tree exists unknown\n"
)
_CT_L3_BINDING_2 = (
    "custody binding sfenton/native-home request request:42 "
    "request-42-l3-g2 agents/review [refs/heads/agents/review]: "
    "disposition needs_pr; tip "
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; pull unknown; reviewed "
    "head unknown; reason ai_review_failed; since "
    "2026-11-23T11:59:00Z; age 60s; attempts unknown; next retry\n"
)
_CT_L3_INTENT_NOTICE = (
    "custody notice sfenton/native-home agents/review "
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb needs_pr: state intent; "
    "since 2026-11-23T11:59:00Z; age 60s; remote identity unknown\n"
)
_CT_L3_NIGHTLY_VERSION_FAULT = (
    "custody fault nightly: version (exists yes, scope store, "
    "version unknown, key unknown)\n"
)
_L3_CUSTODY = {
    "version": 1,
    "records": [
        {
            "repository": "sfenton/native-home",
            "intake": "request",
            "producer": "request:42",
            "generation": "request-42-l3-g1",
            "phase": "pending",
            "original_outcome": {"trust": "untrusted"},
            "since": "2026-11-23T12:00:00Z",
            "age_seconds": 0,
            "attempts": 0,
            "reason": "reserved",
            "next": {"kind": "human"},
            "tree_exists": None,
            "bindings": [{
                "lane": "agents/review",
                "branch": "refs/heads/agents/review",
                "disposition": "owner_wait",
                "tip": "a" * 40,
                "pull": 7,
                "reviewed_head": None,
                "reason": None,
                "since": "2026-11-23T11:59:00Z",
                "age_seconds": 60,
                "attempts": 0,
                "next": {
                    "kind": "retry",
                    "at": "2026-11-23T13:00:00Z",
                },
            }],
            "notices": [{
                "repository": "sfenton/native-home",
                "lane": "agents/review",
                "head": "b" * 40,
                "fault_class": "needs_pr",
                "state": "unsent",
                "since": "2026-11-23T11:59:00Z",
                "age_seconds": 60,
                "remote_identity": None,
            }],
        },
        {
            "repository": "sfenton/native-home",
            "intake": "request",
            "producer": "request:42",
            "generation": "request-42-l3-g2",
            "phase": "pending",
            "original_outcome": None,
            "since": "2026-11-23T12:00:00Z",
            "age_seconds": 0,
            "attempts": None,
            "reason": None,
            "next": {"kind": "unknown"},
            "tree_exists": None,
            "bindings": [{
                "lane": "agents/review",
                "branch": "refs/heads/agents/review",
                "disposition": "needs_pr",
                "tip": "a" * 40,
                "pull": None,
                "reviewed_head": None,
                "reason": "ai_review_failed",
                "since": "2026-11-23T11:59:00Z",
                "age_seconds": 60,
                "attempts": None,
                "next": {"kind": "retry"},
            }],
            "notices": [{
                "repository": "sfenton/native-home",
                "lane": "agents/review",
                "head": "b" * 40,
                "fault_class": "needs_pr",
                "state": "intent",
                "since": "2026-11-23T11:59:00Z",
                "age_seconds": 60,
                "remote_identity": None,
            }],
        },
    ],
    "faults": [{
        "store": "nightly",
        "kind": "version",
        "scope": "store",
        "version": None,
        "key": None,
        "exists": "yes",
    }],
}
_L3_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store nightly: version (exists yes, scope store, "
    "version unknown, key unknown)\n"
    "post-mortems queued: R-60\n"
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)


def with_custody_text(expected_text, custody_text):
    stdout = expected_text[1]
    lines = stdout.splitlines(True)
    marker = "post-mortems queued:"
    if not any(line.startswith(marker) for line in lines):
        marker = "queue: "
    positions = [
        index for index, line in enumerate(lines)
        if line.startswith(marker)
    ]
    if len(positions) != 1:
        raise AssertionError("custody text insertion marker is not unique")
    position = sum(len(line) for line in lines[:positions[0]])
    return (
        expected_text[0],
        stdout[:position] + custody_text + stdout[position:],
        expected_text[2],
    )

_PB_SIGNED_OUTCOME = {
    "trust": "untrusted",
    "exit_code": -7,
}
_PB_RETRY_AT = {
    "kind": "retry",
    "at": "2026-11-23T13:00:00Z",
}
_PB_RETRY = {
    "kind": "retry",
}
_PB_HUMAN_NEXT = {
    "kind": "human",
}
_PB_ALPHA_BINDING = {
    "lane": "agents/alpha",
    "branch": "refs/heads/agents/alpha",
    "disposition": "owner_wait",
    "tip": "a" * 40,
    "pull": 7,
    "reviewed_head": "b" * 40,
    "reason": "non_owner_stall",
    "since": "2026-11-23T11:58:00Z",
    "age_seconds": 120,
    "attempts": 2,
    "next": _PB_RETRY_AT,
}
_PB_BETA_BINDING = {
    "lane": "agents/beta",
    "branch": "refs/heads/agents/beta",
    "disposition": "needs_pr",
    "tip": "absent",
    "pull": None,
    "reviewed_head": None,
    "reason": "ai_review_failed",
    "since": "2026-11-23T11:59:00Z",
    "age_seconds": 60,
    "attempts": None,
    "next": _PB_RETRY,
}
_PB_REVIEW_BINDING = {
    "lane": "agents/review",
    "branch": "refs/heads/agents/review",
    "disposition": "awaiting_review_wiring",
    "tip": "unreadable",
    "pull": None,
    "reviewed_head": None,
    "reason": "pr_checks_failed",
    "since": "2026-11-23T11:58:00Z",
    "age_seconds": 120,
    "attempts": 0,
    "next": _PA_UNKNOWN_NEXT,
}
_PB_UNCERTAIN_NOTICE = {
    "repository": "sfenton/native-home",
    "lane": "agents/review",
    "head": "b" * 40,
    "fault_class": "needs_pr",
    "state": "uncertain",
    "since": "2026-11-23T11:59:00Z",
    "age_seconds": 60,
    "remote_identity": None,
}
_PB_CONFIRMED_NOTICE = {
    "repository": "sfenton/native-home",
    "lane": "agents/review",
    "head": "b" * 40,
    "fault_class": "non_owner_stall",
    "state": "confirmed",
    "since": "2026-11-23T11:57:00Z",
    "age_seconds": 180,
    "remote_identity": {
        "repository": "private/issues",
        "number": 17,
    },
}
_PB_TWO_BINDINGS_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "request",
    "producer": "request:42",
    "generation": "request-42-g1",
    "phase": "pending",
    "original_outcome": _PA_DONE_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": 0,
    "reason": "reserved",
    "next": _PB_HUMAN_NEXT,
    "tree_exists": None,
    "bindings": [
        _PB_ALPHA_BINDING,
        _PB_BETA_BINDING,
    ],
    "notices": [],
}
_PB_TWO_NOTICE_CLASSES_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "request",
    "producer": "request:42",
    "generation": "request-42-g1",
    "phase": "pending",
    "original_outcome": _PB_SIGNED_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [_PB_REVIEW_BINDING],
    "notices": [
        _PB_UNCERTAIN_NOTICE,
        _PB_CONFIRMED_NOTICE,
    ],
}
_PB_TWO_BINDINGS_CUSTODY = {
    "version": 1,
    "records": [_PB_TWO_BINDINGS_RECORD],
    "faults": [],
}
_PB_TWO_NOTICE_CLASSES_CUSTODY = {
    "version": 1,
    "records": [_PB_TWO_NOTICE_CLASSES_RECORD],
    "faults": [],
}
_PB_SAFE_JAN_NOTICE = {
    "repository": "sfenton/native-home",
    "lane": "agents/safe",
    "head": "a" * 40,
    "fault_class": "needs_pr",
    "state": "intent",
    "since": "2026-01-01T00:00:00Z",
    "age_seconds": 28209600,
    "remote_identity": None,
}
_PB_REQUEST_43_PHASE_FAULT = {
    "store": "request",
    "kind": "phase",
    "scope": "record",
    "version": 1,
    "key": {
        "repository": "sfenton/native-home",
        "intake": "request",
        "producer": "request:43",
        "generation": "request-43-g1",
    },
    "exists": "yes",
}
_PB_NIGHTLY_53_PHASE_FAULT = {
    "store": "nightly",
    "kind": "phase",
    "scope": "record",
    "version": 1,
    "key": {
        "repository": "sfenton/native-home",
        "intake": "nightly",
        "producer": "nightly:53",
        "generation": "nightly-53-g1",
    },
    "exists": "yes",
}
_PB_REQUEST_NOTICE_FAULT = {
    "store": "request",
    "kind": "type",
    "scope": "notice",
    "version": 1,
    "key": {
        "repository": "sfenton/native-home",
        "intake": "request",
        "producer": "request:42",
        "generation": "request-42-g1",
        "lane": "agents/bad",
        "head": "b" * 40,
        "fault_class": "needs_pr",
    },
    "exists": "yes",
}
_PB_NIGHTLY_NOTICE_FAULT = {
    "store": "nightly",
    "kind": "type",
    "scope": "notice",
    "version": 1,
    "key": {
        "repository": "sfenton/native-home",
        "intake": "nightly",
        "producer": "nightly:52",
        "generation": "nightly-52-g1",
        "lane": "agents/bad",
        "head": "b" * 40,
        "fault_class": "needs_pr",
    },
    "exists": "yes",
}
_PB_RETRO_NAMESPACE_FAULT = {
    "store": "retro",
    "kind": "namespace",
    "scope": "store",
    "version": None,
    "key": None,
    "exists": "yes",
}
_PB_BAD_REQUEST_PHASE_CUSTODY = {
    "version": 1,
    "records": [_PA_REQUEST_42_RECORD],
    "faults": [_PB_REQUEST_43_PHASE_FAULT],
}
_PB_BAD_NIGHTLY_PHASE_CUSTODY = {
    "version": 1,
    "records": [_PA_NIGHTLY_52_RECORD],
    "faults": [_PB_NIGHTLY_53_PHASE_FAULT],
}
_PB_REQUEST_NOTICE_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "request",
    "producer": "request:42",
    "generation": "request-42-g1",
    "phase": "release_authorized",
    "original_outcome": _PA_DONE_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [],
    "notices": [_PB_SAFE_JAN_NOTICE],
}
_PB_NIGHTLY_NOTICE_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "nightly",
    "producer": "nightly:52",
    "generation": "nightly-52-g1",
    "phase": "release_authorized",
    "original_outcome": _PA_DONE_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [],
    "notices": [_PB_SAFE_JAN_NOTICE],
}
_PB_BAD_REQUEST_NOTICE_CUSTODY = {
    "version": 1,
    "records": [_PB_REQUEST_NOTICE_RECORD],
    "faults": [_PB_REQUEST_NOTICE_FAULT],
}
_PB_BAD_NIGHTLY_NOTICE_CUSTODY = {
    "version": 1,
    "records": [_PB_NIGHTLY_NOTICE_RECORD],
    "faults": [_PB_NIGHTLY_NOTICE_FAULT],
}
_PB_PRIMARY_RETRO_CUSTODY = {
    "version": 1,
    "records": [
        _PA_JOB_RECORD,
        _PA_RETRO_RECORD,
    ],
    "faults": [_PB_RETRO_NAMESPACE_FAULT],
}
_PB_BAD_REQUEST_PHASE_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store request: phase (exists yes, scope record, version 1, "
    'key {"repository":"sfenton/native-home","intake":"request",'
    '"producer":"request:43","generation":"request-43-g1"})\n'
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)
_PB_BAD_NIGHTLY_PHASE_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store nightly: phase (exists yes, scope record, version 1, "
    'key {"repository":"sfenton/native-home","intake":"nightly",'
    '"producer":"nightly:53","generation":"nightly-53-g1"})\n'
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)
_PB_BAD_REQUEST_NOTICE_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store request: type (exists yes, scope notice, version 1, "
    'key {"repository":"sfenton/native-home","intake":"request",'
    '"producer":"request:42","generation":"request-42-g1",'
    '"lane":"agents/bad","head":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",'
    '"fault_class":"needs_pr"})\n'
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)
_PB_BAD_NIGHTLY_NOTICE_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store nightly: type (exists yes, scope notice, version 1, "
    'key {"repository":"sfenton/native-home","intake":"nightly",'
    '"producer":"nightly:52","generation":"nightly-52-g1",'
    '"lane":"agents/bad","head":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",'
    '"fault_class":"needs_pr"})\n'
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)
_PB_RETRO_NAMESPACE_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store retro: namespace (exists yes, scope store, "
    "version unknown, key unknown)\n"
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)
_PB_REQUEST_43_TYPE_FAULT = {
    "store": "request",
    "kind": "type",
    "scope": "record",
    "version": 1,
    "key": {
        "repository": "sfenton/native-home",
        "intake": "request",
        "producer": "request:43",
        "generation": "request-43-g1",
    },
    "exists": "yes",
}
_PB_BAD_BINDING_CUSTODY = {
    "version": 1,
    "records": [_PA_REQUEST_42_RECORD],
    "faults": [_PB_REQUEST_43_TYPE_FAULT],
}
_PB_SAFE_NOON_NOTICE = {
    "repository": "sfenton/native-home",
    "lane": "agents/safe",
    "head": "a" * 40,
    "fault_class": "needs_pr",
    "state": "intent",
    "since": "2026-11-23T11:59:00Z",
    "age_seconds": 60,
    "remote_identity": None,
}
_PB_SAFE_NOON_RECORD = {
    "repository": "sfenton/native-home",
    "intake": "request",
    "producer": "request:42",
    "generation": "request-42-g1",
    "phase": "release_authorized",
    "original_outcome": _PA_DONE_OUTCOME,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 0,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [],
    "notices": [_PB_SAFE_NOON_NOTICE],
}
_PB_BAD_NOON_NOTICE_CUSTODY = {
    "version": 1,
    "records": [_PB_SAFE_NOON_RECORD],
    "faults": [_PB_REQUEST_NOTICE_FAULT],
}
_PB_SCOPED_STORE_TYPE_FAULT = {
    "store": "request",
    "kind": "type",
    "scope": "store",
    "version": 1,
    "key": None,
    "exists": "yes",
}
_PB_MIXED_TYPE_CUSTODY = {
    "version": 1,
    "records": [],
    "faults": [_PB_SCOPED_STORE_TYPE_FAULT],
}
_PB_UNSUPPORTED_VERSION_FAULT = {
    "store": "request",
    "kind": "version",
    "scope": "store",
    "version": None,
    "key": None,
    "exists": "yes",
}
_PB_UNSUPPORTED_VERSION_CUSTODY = {
    "version": 1,
    "records": [],
    "faults": [_PB_UNSUPPORTED_VERSION_FAULT],
}
_PB_UNBOUND_SAFE_NOTICE = {
    "repository": "example/product",
    "lane": "agents/safe",
    "head": "a" * 40,
    "fault_class": "needs_pr",
    "state": "intent",
    "since": "2026-11-23T12:59:00Z",
    "age_seconds": 60,
    "remote_identity": None,
}
_PB_UNBOUND_NOTICE_FAULT = {
    "store": "request",
    "kind": "type",
    "scope": "notice",
    "version": 1,
    "key": {
        "repository": "example/product",
        "intake": "request",
        "producer": "request:7",
        "generation": "g1",
        "lane": "agents/bad",
    },
    "exists": "yes",
}
_PB_UNBOUND_RECORD = {
    "repository": "example/product",
    "intake": "request",
    "producer": "request:7",
    "generation": "g1",
    "phase": "unknown",
    "original_outcome": None,
    "since": "2026-11-23T12:00:00Z",
    "age_seconds": 3600,
    "attempts": None,
    "reason": None,
    "next": _PA_UNKNOWN_NEXT,
    "tree_exists": None,
    "bindings": [],
    "notices": [_PB_UNBOUND_SAFE_NOTICE],
}
_PB_UNBOUND_CUSTODY = {
    "version": 1,
    "records": [_PB_UNBOUND_RECORD],
    "faults": [_PB_UNBOUND_NOTICE_FAULT],
}
_PB_REPOSITORY_NAMESPACE_FAULT = {
    "store": "request",
    "kind": "namespace",
    "scope": "store",
    "version": 1,
    "key": None,
    "exists": "yes",
}
_PB_GENERATION_KEY_FAULT = {
    "store": "request",
    "kind": "key",
    "scope": "record",
    "version": 1,
    "key": {
        "repository": "sfenton/native-home",
        "intake": "request",
        "producer": "request:42",
    },
    "exists": "yes",
}
_PB_UNBOUNDED_CUSTODY = {
    "version": 1,
    "records": [_PA_REQUEST_42_RECORD],
    "faults": [
        _PB_REPOSITORY_NAMESPACE_FAULT,
        _PB_GENERATION_KEY_FAULT,
    ],
}
_PB_BAD_BINDING_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store request: type (exists yes, scope record, version 1, "
    'key {"repository":"sfenton/native-home","intake":"request",'
    '"producer":"request:43","generation":"request-43-g1"})\n'
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)
_PB_MIXED_TYPE_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store request: type (exists yes)\n"
    "state store request: type (exists yes, scope store, version 1, "
    "key unknown)\n"
    "queue: empty\n",
    "",
)
_PB_UNSUPPORTED_VERSION_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store request: version (exists yes, scope store, "
    "version unknown, key unknown)\n"
    "queue: empty\n",
    "",
)
_PB_UNBOUND_NOTICE_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store request: type (exists yes, scope notice, version 1, "
    'key {"repository":"example/product","intake":"request",'
    '"producer":"request:7","generation":"g1","lane":"agents/bad"})\n'
    "queue: empty\n",
    "",
)
_PB_REQUEST_PARSE_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store request: parse (exists yes)\n"
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)
_PB_MISSING_NIGHTLY_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store nightly: not found (exists no, installation unknown)\n"
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)
_PB_UNBOUNDED_STATUS_TEXT = (
    0,
    "paused: False   installed: False   running: no\n"
    "self-changes: running\n"
    "auth: claude logged in\n"
    "state store request: namespace (exists yes, scope store, "
    "version 1, key unknown)\n"
    "state store request: key (exists yes, scope record, version 1, "
    'key {"repository":"sfenton/native-home","intake":"request",'
    '"producer":"request:42"})\n'
    "queue: empty\n"
    "nightly queue: empty\n",
    "",
)


class CustodyTreeLayout:
    def __init__(self, owner, name, root="directory",
                 worktrees="directory"):
        physical_home = Path(owner.home).resolve()
        self.area = physical_home / "tree-observer" / name
        self.area.mkdir(parents=True)
        runner_parent = self.area / "runner-parent"
        runner_parent.mkdir()
        configured_root = runner_parent / "runner"
        if root == "directory":
            configured_root.mkdir()
        elif root == "file":
            configured_root.write_text("not a directory")
        elif root == "link":
            target = self.area / "linked-root-target"
            target.mkdir()
            configured_root.symlink_to(target, target_is_directory=True)
        elif root == "linked_parent":
            target_parent = self.area / "linked-parent-target"
            target_parent.mkdir()
            (target_parent / "runner").mkdir()
            linked_parent = self.area / "linked-parent"
            linked_parent.symlink_to(target_parent, target_is_directory=True)
            configured_root = linked_parent / "runner"
        elif root != "absent":
            raise AssertionError(f"unknown root kind {root}")
        cfg = dict(owner.cfg)
        cfg["root"] = str(configured_root)
        self.paths = ht.Paths(cfg, owner.home)
        if root not in ("directory", "link", "linked_parent"):
            return
        if worktrees == "directory":
            self.paths.worktrees.mkdir()
        elif worktrees == "file":
            self.paths.worktrees.write_text("not a directory")
        elif worktrees == "link":
            target = self.area / "linked-worktrees-target"
            target.mkdir()
            self.paths.worktrees.symlink_to(
                target, target_is_directory=True
            )
        elif worktrees != "absent":
            raise AssertionError(f"unknown worktrees kind {worktrees}")

    def leaf(self, basename, kind="directory"):
        path = self.paths.worktrees / basename
        if kind == "directory":
            path.mkdir()
        elif kind == "file":
            path.write_text("leaf")
        elif kind == "inside_link":
            target = self.paths.worktrees / "inside-target"
            target.mkdir()
            path.symlink_to(target, target_is_directory=True)
        elif kind == "outside_link":
            target = self.area / "outside-target"
            target.mkdir()
            path.symlink_to(target, target_is_directory=True)
        elif kind == "dangling_link":
            path.symlink_to(
                self.area / "absent-target", target_is_directory=True
            )
        elif kind == "fifo":
            os.mkfifo(path)
        else:
            raise AssertionError(f"unknown leaf kind {kind}")
        return path


class CustodyTreeTrace:
    _FLAGS = (
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    )

    def __init__(self, inject=None, close_failure=None):
        self.inject = inject
        self.close_failure = close_failure
        self.probes = []
        self.events = []
        self.injections = 0
        self.open_ordinal = 0
        self.live = {}
        self.acquired = []
        self.closed = []
        self._next_symbol = 0
        self._observer_code = None
        self._stack = None

    def __enter__(self):
        observer = getattr(ht, "_observe_custody_tree", None)
        if observer is not None:
            self._observer_code = observer.__code__
            self._original_observer = observer
        self._original_open = os.open
        self._original_stat = os.stat
        self._original_close = os.close
        self._stack = contextlib.ExitStack()
        self._stack.__enter__()
        if observer is not None:
            self._stack.enter_context(mock.patch.object(
                ht, "_observe_custody_tree",
                new=self._observe,
            ))
        self._stack.enter_context(
            mock.patch.object(os, "open", new=self._open)
        )
        self._stack.enter_context(
            mock.patch.object(os, "stat", new=self._stat)
        )
        self._stack.enter_context(
            mock.patch.object(os, "close", new=self._close)
        )
        for owner, names in (
            (Path, (
                "resolve", "readlink", "stat", "lstat", "exists",
                "is_dir", "is_file", "open", "read_bytes", "iterdir",
                "read_text", "glob", "rglob", "cwd", "absolute",
            )),
            (
                os,
                (
                    "lstat", "scandir", "listdir", "readlink", "access",
                    "fstat", "getcwd",
                ),
            ),
        ):
            for name in names:
                if hasattr(owner, name):
                    original = getattr(owner, name)
                    self._stack.enter_context(mock.patch.object(
                        owner, name,
                        new=self._reject(name, original),
                    ))
        return self

    def __exit__(self, exc_type, exc, traceback):
        return self._stack.__exit__(exc_type, exc, traceback)

    def _observe(self, paths, producer):
        self.probes.append((
            "observe", os.fspath(paths.root), producer,
        ))
        return self._original_observer(paths, producer)

    def _attributed(self):
        frame = sys._getframe(2)
        while frame is not None:
            if frame.f_code is self._observer_code:
                return True
            frame = frame.f_back
        return False

    def _reject(self, label, original):
        def rejected(*args, **kwargs):
            if self._attributed():
                raise AssertionError(
                    f"unexpected observer access {label}"
                )
            return original(*args, **kwargs)
        return rejected

    def _parent(self, fd):
        if fd is None:
            return None
        if fd not in self.live:
            raise AssertionError("observer used an fd outside its live set")
        return self.live[fd]

    def _should_inject(self, operation, path, ordinal=None):
        if self.injections or self.inject is None:
            return None
        expected_operation, expected_target, error = self.inject
        matches_target = (
            ordinal == expected_target
            if isinstance(expected_target, int)
            else path == expected_target
        )
        if operation == expected_operation and matches_target:
            self.injections += 1
            return error
        return None

    def _open(self, path, flags, *args, **kwargs):
        if not self._attributed():
            return self._original_open(path, flags, *args, **kwargs)
        dir_fd = kwargs.get("dir_fd")
        parent = self._parent(dir_fd)
        self.assert_supported_open(path, flags, args)
        ordinal = self.open_ordinal
        self.open_ordinal += 1
        injected = self._should_inject("open", path, ordinal)
        if injected is not None:
            self.events.append((
                "open", path, flags, parent, "error", injected
            ))
            raise OSError(injected, "trace canary")
        try:
            fd = self._original_open(path, flags, *args, **kwargs)
        except OSError as exc:
            self.events.append((
                "open", path, flags, parent, "error", exc.errno
            ))
            raise
        symbol = f"fd{self._next_symbol}"
        self._next_symbol += 1
        self.live[fd] = symbol
        self.acquired.append(symbol)
        self.events.append((
            "open", path, flags, parent, "ok", symbol
        ))
        return fd

    @staticmethod
    def assert_supported_open(path, flags, positional):
        if positional:
            raise AssertionError("observer supplied an open mode")
        expected = (
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        )
        if flags != expected:
            raise AssertionError(f"observer open flags changed for {path}")

    def _stat(self, path, *args, **kwargs):
        if not self._attributed():
            return self._original_stat(path, *args, **kwargs)
        if args:
            raise AssertionError("observer used positional stat arguments")
        dir_fd = kwargs.get("dir_fd")
        parent = self._parent(dir_fd)
        follow = kwargs.get("follow_symlinks")
        if follow is not False:
            raise AssertionError("observer followed the leaf link")
        injected = self._should_inject("stat", path)
        if injected is not None:
            self.events.append((
                "stat", path, parent, False, "error", injected
            ))
            raise OSError(injected, "trace canary")
        try:
            result = self._original_stat(path, *args, **kwargs)
        except OSError as exc:
            self.events.append((
                "stat", path, parent, False, "error", exc.errno
            ))
            raise
        self.events.append((
            "stat", path, parent, False, "ok"
        ))
        return result

    def _close(self, fd):
        if not self._attributed():
            return self._original_close(fd)
        symbol = self._parent(fd)
        self._original_close(fd)
        del self.live[fd]
        self.closed.append(symbol)
        close_ordinal = len(self.closed)
        failure_target = self.close_failure
        should_fail = (
            failure_target is True and close_ordinal == 1
            or isinstance(failure_target, str)
            and symbol == failure_target
            or isinstance(failure_target, int)
            and not isinstance(failure_target, bool)
            and close_ordinal == failure_target
        )
        if should_fail:
            self.injections += 1
            self.events.append((
                "close", symbol, "ok", "injected-error", errno.EIO
            ))
            raise OSError(errno.EIO, "trace canary")
        self.events.append(("close", symbol, "ok"))

    def assert_owned_once(self, testcase):
        testcase.assertCountEqual(self.acquired, self.closed)
        testcase.assertEqual(self.live, {})

    def assert_fired(self, testcase):
        testcase.assertEqual(self.injections, 1)


@dataclass(frozen=True)
class CustodySeed:
    repository: str
    intake: str
    producer: str
    generation: str
    branch: str
    archive_name: str
    archive_session: str
    source_repository: str = ""
    source_archive: str = ""
    source_queued: str = ""
    outcome: str = "done"

    def aggregate(self):
        target = {
            "branch": self.branch,
            "archive_name": self.archive_name,
            "archive_session": self.archive_session,
        }
        if self.source_repository:
            target["source_repository"] = self.source_repository
        if self.source_archive:
            target["source_archive"] = self.source_archive
            target["source_queued"] = self.source_queued
        record = {
            "phase": "release_authorized",
            "since": "2026-11-23T12:00:00Z",
            "target": target,
            "pre_refs": {self.branch: "absent"},
            "bindings": {},
            "original_outcome": {
                "trust": "clean_end",
                "exit_code": 0,
                "state": self.outcome,
            },
            "release_proof": {
                "inventory": "positive_empty",
                "unlanded": "verified_none",
                "archive_name": self.archive_name,
                "archive_session": self.archive_session,
                "archive_disposition": "archived",
            },
        }
        return {
            "version": 1,
            "records": {
                self.repository: {
                    self.intake: {
                        self.producer: {
                            self.generation: record,
                        },
                    },
                },
            },
        }


@dataclass(frozen=True)
class CustodySeeds:
    items: tuple

    def aggregate(self):
        result = {"version": 1, "records": {}}
        for seed in self.items:
            aggregate = seed.aggregate()
            for repository, intakes in aggregate["records"].items():
                repos = result["records"].setdefault(repository, {})
                for intake, producers in intakes.items():
                    entries = repos.setdefault(intake, {})
                    for producer, generations in producers.items():
                        values = entries.setdefault(producer, {})
                        for generation, record in generations.items():
                            if generation in values:
                                raise AssertionError(
                                    "duplicate custody seed generation"
                                )
                            values[generation] = record
        return result


@dataclass(frozen=True)
class CustodyAggregateSeed:
    value: dict

    def aggregate(self):
        return json.loads(json.dumps(self.value))


def seeded_expected(expected, seed):
    value = json.loads(json.dumps(expected))
    if seed is None:
        return value
    aggregate = seed.aggregate()
    existing = value.get("custody")
    if existing is not None and existing != aggregate:
        raise AssertionError("seed does not match the expected custody fixture")
    value["custody"] = aggregate
    return value


class StoreTestBase(t.Base):
    def write_raw(self, path: Path, value) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value if isinstance(value, str) else json.dumps(value))

    def legacy(self, **extra) -> dict:
        value = ht.State._empty_data()
        value.update(extra)
        return value

    def custody_seed(
            self, intake, producer, generation, branch, archive_name,
            archive_session, source_archive="", source_queued="",
            outcome="done",
    ):
        source_repository = ""
        if producer.startswith("request:"):
            source_repository = self.cfg["request_repo"].lower()
        elif producer.startswith("nightly:"):
            source_repository = self.cfg["nightly"]["repo"].lower()
        seed = CustodySeed(
            repository=self.cfg["product_repo"].lower(),
            intake=intake,
            producer=producer,
            generation=generation,
            branch=branch,
            archive_name=archive_name,
            archive_session=archive_session,
            source_repository=source_repository,
            source_archive=source_archive,
            source_queued=source_queued,
            outcome=outcome,
        )
        if producer.startswith(("job:", "retro:")):
            target = seed.aggregate()["records"][seed.repository][
                intake
            ][producer][generation]["target"]
            self.assertNotIn("source_repository", target)
        return seed

    def request_seed(self, number, outcome="done"):
        return self.custody_seed(
            "request",
            f"request:{number}",
            f"request-{number}-g1",
            f"refs/heads/report/{number}",
            f"request-{number}",
            f"request-{number}-seed",
            outcome=outcome,
        )

    def job_seed(self):
        return self.custody_seed(
            "request",
            "job:researcher",
            "job-researcher-g1",
            "refs/heads/agents/researcher-261123",
            "job-researcher-2026-11-23",
            "job-researcher-seed",
        )

    def nightly_seed(self, number=52):
        return self.custody_seed(
            "nightly",
            f"nightly:{number}",
            f"nightly-{number}-g1",
            f"refs/heads/nightly/{number}",
            f"nightly-{number}",
            f"nightly-{number}-seed",
        )

    def maintenance_seeds(self):
        return CustodySeeds(tuple(
            self.request_seed(number)
            for number in range(62, 68)
        ))

    def stopped_retro_seed(self):
        return self.retro_seed(
            "held-retro",
            "refs/heads/agents/retro-held-retro-261123",
            "held-input",
            "2026-11-22T12:00:00Z",
            "retro-held-retro",
            "retro-held-retro-seed",
        )

    def old_retro_seed(self):
        return self.retro_seed(
            "old-retro",
            "refs/heads/agents/retro-old-retro-261123",
            "old-input",
            "2026-11-22T12:00:00Z",
            "retro-old-input",
            "retro-old-retro-seed",
        )

    def custody_fixtures(self):
        return {
            "quiet request": (
                "primary", self.request_seed(42), (), (),
            ),
            "priority request": (
                "primary", self.request_seed(42), (), (),
            ),
            "priority nightly": (
                "nightly", self.nightly_seed(), (), (),
            ),
            "drained request": (
                "primary", self.request_seed(42), (), (),
            ),
            "drained nightly": (
                "nightly", self.nightly_seed(), (), (),
            ),
            "self-change pause": (
                "primary", self.request_seed(42), (), (),
            ),
            "valid acknowledgement": (
                "primary", self.request_seed(42), (), (),
            ),
            "maintenance": (
                "primary",
                self.maintenance_seeds(),
                (),
                ("request-64-fixed",),
            ),
            "integrated job and retro": (
                "primary",
                self.integrated_job_seeds(),
                ((
                    "job-researcher-2026-11-23",
                    "job-researcher-2026-11-23",
                    "2026-11-23T12:00:00Z",
                ),),
                (
                    "job-researcher-897aded5543e",
                    "retro-job-researcher-2026-11-23-e6789b1f72f7",
                ),
            ),
            "tamper 71": (
                "primary",
                self.request_seed(71, outcome="done"),
                (),
                ("request-71-a2d9ced85f6f",),
            ),
            "ordinary request 70": (
                "primary",
                self.request_seed(70, outcome="no_changes"),
                (),
                (),
            ),
            "manual controls 72": (
                "primary", self.request_seed(72), (), (),
            ),
            "locked status 72": (
                "primary", self.request_seed(72), (), (),
            ),
            "post-launch request 81": (
                "primary",
                self.request_seed(81, outcome="done"),
                (),
                ("request-81-10cf3364c1d1",),
            ),
            "classic reviewer": (
                "primary", self.job_seed(), (), (),
            ),
            "worker reviewer callback": (
                "primary", self.job_seed(), (), (),
            ),
            "identified stopped retro pair": (
                "primary",
                self.stopped_retro_seed(),
                ((
                    "held-retro",
                    "held-input",
                    "2026-11-22T12:00:00Z",
                ),),
                (),
            ),
            "request 63 path absent": (
                "primary",
                self.request_seed(63),
                (),
                ("request-63-installed",),
            ),
            "old retro pre-drop": (
                "primary",
                self.old_retro_seed(),
                ((
                    "old-retro",
                    "old-input",
                    "2026-11-22T12:00:00Z",
                ),),
                (
                    "retro-old-input-prior",
                    "retro-old-retro-bc9b9b0ea1cf",
                ),
            ),
        }

    def custody_fixture(self, name):
        return self.custody_fixtures()[name][1]

    @staticmethod
    def fixture_record(aggregate, seed):
        return aggregate["records"][seed.repository][seed.intake][
            seed.producer
        ][seed.generation]

    @staticmethod
    def fixture_records(aggregate):
        return [
            record
            for intakes in aggregate["records"].values()
            for producers in intakes.values()
            for generations in producers.values()
            for record in generations.values()
        ]

    def custody_variants(self, seed):
        cases = []
        for phase in ("unknown", "pending", "release_authorized"):
            aggregate = seed.aggregate()
            for record in self.fixture_records(aggregate):
                record["phase"] = phase
                if phase == "unknown":
                    for name in (
                        "target", "pre_refs", "original_outcome",
                        "release_proof",
                    ):
                        record.pop(name, None)
                elif phase == "pending":
                    record.pop("release_proof")
                    record["bindings"] = {
                        "agents/test": {
                            "disposition": "owner_wait",
                            "tip": "a" * 40,
                            "since": "2026-01-01T00:00:00Z",
                        },
                    }
            cases.append((f"phase {phase}", CustodyAggregateSeed(aggregate)))
        for notice_state in (
            "unsent", "intent", "uncertain", "confirmed",
        ):
            aggregate = seed.aggregate()
            payload = {
                "state": notice_state,
                "since": "2026-01-01T00:00:00Z",
            }
            if notice_state == "confirmed":
                payload["remote_identity"] = {
                    "repository": "private/issues",
                    "number": 1,
                }
            for record in self.fixture_records(aggregate):
                record["notices"] = {
                    "agents/test": {
                        "b" * 40: {
                            "needs_pr": payload,
                        },
                    },
                }
            cases.append((
                f"notice {notice_state}",
                CustodyAggregateSeed(aggregate),
            ))
        return cases

    def integrated_job_seeds(self):
        return CustodySeeds((
            self.job_seed(),
            self.retro_seed(
                "job-researcher-2026-11-23",
                "refs/heads/agents/"
                "retro-job-researcher-2026-11-23-261123",
                "job-researcher-2026-11-23",
                "2026-11-23T12:00:00Z",
                "retro-job-researcher-2026-11-23",
                "retro-job-researcher-2026-11-23-seed",
            ),
        ))

    def retro_seed(
            self, task, branch, source_archive, source_queued,
            archive_name, archive_session,
    ):
        return self.custody_seed(
            "request",
            f"retro:{task}",
            f"retro-{task}-g1",
            branch,
            archive_name,
            archive_session,
            source_archive=source_archive,
            source_queued=source_queued,
        )

    @contextlib.contextmanager
    def seeded_golden(self, primary_seed, nightly_seed=None):
        original_legacy = self.legacy
        original_write_raw = self.write_raw

        def legacy_seed(extra):
            if "queue" in extra or "done" in extra:
                return None
            marker = (extra.get("opaque_extension") or {}).get("preserve")
            if nightly_seed is not None and marker and marker[-1] == 2:
                return nightly_seed
            return primary_seed

        def legacy(**extra):
            return seeded_expected(original_legacy(**extra), legacy_seed(extra))

        def write_raw(path, value):
            if isinstance(value, dict):
                if path.name == "state-retro.json":
                    seed = None
                elif path.name == "state-nightly.json":
                    seed = nightly_seed
                else:
                    seed = primary_seed
                value = seeded_expected(value, seed)
            original_write_raw(path, value)

        with mock.patch.object(self, "legacy", side_effect=legacy), \
                mock.patch.object(self, "write_raw", side_effect=write_raw):
            yield
            reopened = ht.State(self.paths.state)
            self.assertEqual(
                reopened.data["custody"],
                primary_seed.aggregate(),
            )
            if nightly_seed is not None:
                nightly_path = ht.Paths(
                    self.cfg, self.home, "nightly-"
                ).state
                reopened_nightly = ht.State(nightly_path)
                self.assertEqual(
                    reopened_nightly.data["custody"],
                    nightly_seed.aggregate(),
                )

    def main_with(self, argv, cfg=None, gh=None):
        with mock.patch.object(ht, "load_config", return_value=cfg or self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh or FakeGitHub([])), \
                mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            result = ht.main(argv, home=self.home)
        return result, out.getvalue(), err.getvalue()

    def logical_path(self, store: str) -> Path:
        return {
            "primary": self.paths.state,
            "nightly": ht.Paths(self.cfg, self.home, "nightly-").state,
            "retro": ht.Paths(self.cfg, self.home, "retro-").state,
        }[store]

    def quiet_tick_patches(self, events):
        return (
            mock.patch.object(ht.Runner, "readable_base_map",
                              side_effect=lambda: events.append("base-map") or {}),
            mock.patch.object(ht.Runner, "refresh_clone",
                              side_effect=lambda: events.append("refresh")),
            mock.patch.object(ht.Runner, "check_base",
                              side_effect=lambda _when: events.append("base") or True),
            mock.patch.object(ht.Runner, "check_ha_changes",
                              side_effect=lambda: events.append("ha")),
            mock.patch.object(ht.Runner, "check_merging",
                              side_effect=lambda: events.append("merging")),
            mock.patch.object(ht.Runner, "check_parked",
                              side_effect=lambda: events.append("parked")),
            mock.patch.object(ht.Runner, "requeue",
                              side_effect=lambda: events.append("requeue")),
            mock.patch.object(ht.Runner, "recover",
                              side_effect=lambda: events.append("recover")),
        )

    def main_golden(
        self, argv, cfg, gh, boundaries, observe_saves=False,
        custody_clock=None, clock_calls=None,
    ):
        fixed = custody_clock or datetime(
            2026, 11, 23, 12, 0, tzinfo=timezone.utc
        )

        def sampled_now():
            if clock_calls is not None:
                clock_calls.append(fixed)
            return fixed

        original_save = ht.State.save

        def save(state):
            boundaries.persistence_events.append(("save", state.path.name))
            return original_save(state)

        save_patch = (
            mock.patch.object(ht.State, "save", autospec=True, side_effect=save)
            if observe_saves else mock.patch.dict(os.environ, {}, clear=False)
        )
        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh), \
                mock.patch.object(
                    ht.Runner, "_run", autospec=True,
                    side_effect=boundaries.run,
                ), \
                mock.patch.object(
                    ht.Runner, "_launch", autospec=True,
                    side_effect=boundaries.launch,
                ), \
                mock.patch.object(
                    ht.lane_land, "git", side_effect=boundaries.land_git,
                ), \
                mock.patch.object(
                    ht.lane_land, "land", side_effect=boundaries.land,
                ), \
                mock.patch.object(
                    ht.t3launch, "forget", side_effect=boundaries.forget
                ), \
                mock.patch.object(ht, "claude_logged_in", return_value=True), \
                mock.patch.object(ht, "iso", return_value="2026-11-23T12:00:00Z"), \
                mock.patch.object(ht, "now", side_effect=sampled_now), \
                mock.patch.object(ht.time, "time", return_value=1795435200.0), \
                mock.patch.object(ht.time, "time_ns", return_value=1795435200000000000), \
                mock.patch.object(ht.os, "getpid", return_value=4242), \
                mock.patch.dict(
                    os.environ,
                    {"FENTON_HEADLESS": "", "HASS_TRIAGE_ISSUE": ""},
                ), \
                save_patch, \
                mock.patch("sys.stdin.isatty", return_value=True), \
                mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            result = ht.main(argv, home=self.home)
        return result, out.getvalue(), err.getvalue()

    def assert_pa_json_value(self, actual, expected, path="custody"):
        self.assertIs(
            type(actual),
            type(expected),
            f"custody JSON type at {path}",
        )
        if isinstance(expected, dict):
            self.assertEqual(set(actual), set(expected))
            for key, value in expected.items():
                self.assert_pa_json_value(
                    actual[key], value, f"{path}.{key}"
                )
        elif isinstance(expected, list):
            self.assertEqual(len(actual), len(expected))
            for index, (item, value) in enumerate(zip(actual, expected)):
                self.assert_pa_json_value(
                    item, value, f"{path}[{index}]"
                )
        else:
            self.assertEqual(actual, expected, f"custody JSON value at {path}")

    def assert_pa_custody_loader(
        self, cfg, expected_custody, expected_state_loads,
        storage_facts=_PA_ABSENT,
    ):
        if storage_facts is not _PA_ABSENT:
            self.assertLessEqual(
                set(storage_facts),
                {"without_target", "stored_unknown_next"},
            )
        encoded = json.dumps(expected_custody)
        round_trip = json.loads(encoded)
        self.assertEqual(round_trip, expected_custody)
        self.assert_pa_json_value(round_trip, expected_custody)
        self.assertEqual(
            set(expected_custody), {"version", "records", "faults"}
        )
        self.assert_pa_json_value(expected_custody["version"], 1)
        for record in expected_custody["records"]:
            self.assertEqual(set(record), {
                "repository", "intake", "producer", "generation", "phase",
                "original_outcome", "since", "age_seconds", "attempts",
                "reason", "next", "tree_exists", "bindings", "notices",
            })
            if record["original_outcome"] is not None:
                self.assertIn("trust", record["original_outcome"])
                self.assertLessEqual(
                    set(record["original_outcome"]),
                    {"trust", "exit_code", "state"},
                )
            self.assertIn("kind", record["next"])
            self.assertIn(
                set(record["next"]),
                ({"kind"}, {"kind", "at"}),
            )
            if "at" in record["next"]:
                self.assertEqual(record["next"]["kind"], "retry")
            self.assert_pa_json_value(record["tree_exists"], None)
            self.assertIs(type(record["age_seconds"]), int)
            if storage_facts is _PA_ABSENT:
                self.assertIs(
                    type(record["age_seconds"]), int,
                    "custody record age_seconds type",
                )
                self.assertEqual(
                    record["age_seconds"],
                    0,
                    "custody record age_seconds",
                )
                self.assertEqual(
                    set(record["original_outcome"]),
                    {"trust", "exit_code", "state"},
                )
                self.assertEqual(set(record["next"]), {"kind"})
                self.assert_pa_json_value(record["bindings"], [])
                self.assert_pa_json_value(record["notices"], [])
            else:
                for binding in record["bindings"]:
                    self.assertEqual(set(binding), {
                        "lane", "branch", "disposition", "tip", "pull",
                        "reviewed_head", "reason", "since", "age_seconds",
                        "attempts", "next",
                    })
                    self.assertIs(type(binding["age_seconds"]), int)
                    self.assertIn("kind", binding["next"])
                    self.assertIn(
                        set(binding["next"]),
                        ({"kind"}, {"kind", "at"}),
                    )
                    if "at" in binding["next"]:
                        self.assertEqual(binding["next"]["kind"], "retry")
                for notice in record["notices"]:
                    self.assertEqual(set(notice), {
                        "repository", "lane", "head", "fault_class",
                        "state", "since", "age_seconds", "remote_identity",
                    })
                    self.assertEqual(
                        notice["repository"], record["repository"]
                    )
                    self.assertIs(type(notice["age_seconds"]), int)
                    if notice["state"] == "confirmed":
                        self.assertEqual(
                            set(notice["remote_identity"]),
                            {"repository", "number"},
                        )
                    else:
                        self.assertIsNone(notice["remote_identity"])
            self.assertNotIn("target", record)
        for fault in expected_custody["faults"]:
            self.assertEqual(
                set(fault),
                {"store", "kind", "scope", "version", "key", "exists"},
            )

        primary = ht.State(self.paths.state)
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        nightly = ht.State(nightly_path)
        retro_path = ht.Paths(cfg, self.home, "retro-").state
        retro = ht.State(retro_path)
        sampled = [("request", primary)]
        if cfg.get("nightly") or nightly_path.exists():
            sampled.append(("nightly", nightly))
        if retro_path.exists():
            sampled.append(("retro", retro))
        actual_state_loads = [
            result
            for store, state in sampled
            for result in state.load_projection(store)
        ]
        self.assertEqual(actual_state_loads, expected_state_loads)

        expected_by_store = {
            "request": [],
            "nightly": [],
            "retro": [],
        }
        for record in expected_custody["records"]:
            expected_by_store[record["intake"]].append(record)
        expected_faults = {
            store: [
                fault for fault in expected_custody["faults"]
                if fault["store"] == store
            ]
            for store in expected_by_store
        }
        if storage_facts is not _PA_ABSENT:
            sampled_stores = {store for store, _state in sampled}
            expected_stores = {
                record["intake"]
                for record in expected_custody["records"]
            }
            expected_stores.update(
                fault["store"]
                for fault in expected_custody["faults"]
            )
            self.assertLessEqual(expected_stores, sampled_stores)
        for store, state in sampled:
            projection = state.load_projection(store)
            scoped = [fault for fault in projection if "scope" in fault]
            self.assert_pa_json_value(scoped, expected_faults[store])
            expected_records = expected_by_store[store]
            if storage_facts is _PA_ABSENT:
                self.assertEqual(
                    [item[0] for item in state.vetted_custody_records],
                    [
                        (
                            record["repository"],
                            record["intake"],
                            record["producer"],
                            record["generation"],
                        )
                        for record in expected_records
                    ],
                )
                self.assertEqual(
                    len(state.vetted_custody_records),
                    len(expected_records),
                )
                for (_key, body, notices), expected in zip(
                    state.vetted_custody_records, expected_records
                ):
                    self.assertEqual(set(body), {
                        "phase", "since", "bindings", "original_outcome",
                        "target",
                    })
                    self.assert_pa_json_value(
                        body["phase"], expected["phase"]
                    )
                    self.assert_pa_json_value(
                        body["since"], expected["since"]
                    )
                    self.assert_pa_json_value(
                        dict(body["original_outcome"]),
                        expected["original_outcome"],
                    )
                    self.assertEqual(dict(body["bindings"]), {})
                    self.assertEqual(len(expected["bindings"]), 0)
                    self.assertEqual(
                        len(notices), len(expected["notices"])
                    )
                    self.assert_pa_json_value(tuple(notices), ())
                    self.assertNotIn("attempts", body)
                    self.assertNotIn("reason", body)
                    self.assertNotIn("next", body)
                    self.assertIn("target", body)
                continue

            expected_by_key = {
                (
                    record["repository"],
                    record["intake"],
                    record["producer"],
                    record["generation"],
                ): record
                for record in expected_records
            }
            actual_keys = [
                item[0] for item in state.vetted_custody_records
            ]
            self.assertCountEqual(actual_keys, expected_by_key)
            self.assertEqual(len(actual_keys), len(set(actual_keys)))
            self.assertEqual(len(expected_by_key), len(expected_records))
            without_target = set(storage_facts.get("without_target", ()))
            stored_unknown_next = set(
                storage_facts.get("stored_unknown_next", ())
            )
            actual_by_key = {
                key: (body, notices)
                for key, body, notices in state.vetted_custody_records
            }
            for key, expected in expected_by_key.items():
                body, notices = actual_by_key[key]
                expected_body_keys = {"phase", "since", "bindings"}
                if key not in without_target:
                    expected_body_keys.add("target")
                    self.assertIn("target", body)
                else:
                    self.assertNotIn("target", body)
                for name in ("original_outcome", "attempts", "reason"):
                    if expected[name] is None:
                        self.assertNotIn(name, body)
                    else:
                        expected_body_keys.add(name)
                        self.assertIn(name, body)
                expected_next = expected["next"]
                next_is_stored = (
                    expected_next["kind"] != "unknown"
                    or key in stored_unknown_next
                )
                if next_is_stored:
                    expected_body_keys.add("next")
                    self.assertIn("next", body)
                    self.assert_pa_json_value(
                        dict(body["next"]), expected_next
                    )
                else:
                    self.assertNotIn("next", body)
                self.assertEqual(set(body), expected_body_keys)
                self.assert_pa_json_value(body["phase"], expected["phase"])
                self.assert_pa_json_value(body["since"], expected["since"])
                if expected["original_outcome"] is not None:
                    self.assert_pa_json_value(
                        dict(body["original_outcome"]),
                        expected["original_outcome"],
                    )
                if expected["attempts"] is not None:
                    self.assert_pa_json_value(
                        body["attempts"], expected["attempts"]
                    )
                if expected["reason"] is not None:
                    self.assert_pa_json_value(
                        body["reason"], expected["reason"]
                    )

                expected_bindings = {
                    binding["lane"]: binding
                    for binding in expected["bindings"]
                }
                actual_bindings = dict(body["bindings"])
                self.assertCountEqual(
                    actual_bindings, expected_bindings
                )
                self.assertEqual(
                    len(actual_bindings), len(expected["bindings"])
                )
                for lane, binding in expected_bindings.items():
                    payload = actual_bindings[lane]
                    expected_payload_keys = {
                        "disposition", "tip", "since",
                    }
                    for name in (
                        "pull", "reviewed_head", "reason", "attempts",
                    ):
                        if binding[name] is None:
                            self.assertNotIn(name, payload)
                        else:
                            expected_payload_keys.add(name)
                            self.assertIn(name, payload)
                            self.assert_pa_json_value(
                                payload[name], binding[name]
                            )
                    binding_next = binding["next"]
                    binding_next_is_stored = (
                        binding_next["kind"] != "unknown"
                        or (key, lane) in stored_unknown_next
                    )
                    if binding_next_is_stored:
                        expected_payload_keys.add("next")
                        self.assertIn("next", payload)
                        self.assert_pa_json_value(
                            dict(payload["next"]), binding_next
                        )
                    else:
                        self.assertNotIn("next", payload)
                    self.assertEqual(set(payload), expected_payload_keys)
                    self.assert_pa_json_value(
                        payload["disposition"],
                        binding["disposition"],
                    )
                    self.assert_pa_json_value(
                        payload["tip"], binding["tip"]
                    )
                    self.assert_pa_json_value(
                        payload["since"], binding["since"]
                    )

                expected_notices = {
                    (
                        notice["lane"],
                        notice["head"],
                        notice["fault_class"],
                    ): notice
                    for notice in expected["notices"]
                }
                actual_notices = {
                    identity: payload
                    for identity, payload in notices
                }
                self.assertCountEqual(
                    [identity for identity, _payload in notices],
                    expected_notices,
                )
                self.assertEqual(
                    len(notices), len(expected["notices"])
                )
                for identity, notice in expected_notices.items():
                    payload = actual_notices[identity]
                    self.assertEqual(
                        notice["repository"], expected["repository"]
                    )
                    if notice["state"] == "confirmed":
                        self.assertEqual(
                            set(payload),
                            {"state", "since", "remote_identity"},
                        )
                        self.assert_pa_json_value(
                            dict(payload["remote_identity"]),
                            notice["remote_identity"],
                        )
                    else:
                        self.assertEqual(
                            set(payload), {"state", "since"}
                        )
                        self.assertNotIn("remote_identity", payload)
                    self.assert_pa_json_value(
                        payload["state"], notice["state"]
                    )
                    self.assert_pa_json_value(
                        payload["since"], notice["since"]
                    )

    def assert_pa_locked_status(
        self,
        cfg,
        gh,
        boundaries,
        expected_text,
        expected_json_fields,
        expected_state_loads,
        expected_queue,
        expected_nightly_queue,
        expected_retro_queue,
        expected_queue_events,
        expected_remote_events,
        expected_files,
        expected_git_events=(),
        expected_launch_events=(),
        expected_forget_events=(),
        expected_custody=_PA_ABSENT,
        expected_custody_text=_PA_ABSENT,
        test_clock=None,
        expected_projection_probes=None,
        expected_projection_trace=None,
        expected_renderer_trace=None,
    ):
        expected_projection_probes = list(
            expected_projection_probes or ()
        )
        expected_projection_trace = list(
            expected_projection_trace or ()
        )
        expected_renderer_trace = list(
            expected_renderer_trace or ()
        )
        self.assertEqual(
            expected_remote_events is None,
            not hasattr(gh, "events"),
            "expected remote events must match the fake event log",
        )
        state_paths = (
            self.paths.state,
            ht.Paths(cfg, self.home, "nightly-").state,
            ht.Paths(cfg, self.home, "retro-").state,
        )
        cfg = dict(cfg)
        bound_custody = any(
            "target" in body
            for path in state_paths
            for _key, body, _notices in ht.State(path).vetted_custody_records
        )
        if bound_custody:
            layout_number = getattr(
                self, "_custody_status_layout_number", 0
            )
            self._custody_status_layout_number = layout_number + 1
            layout = CustodyTreeLayout(
                self, f"status-{layout_number}"
            )
            cfg["root"] = str(layout.paths.root)
            configured_paths = ht.Paths(cfg, self.home)
            self.assertEqual(configured_paths.state, self.paths.state)
            self.assertEqual(
                configured_paths.lock, self.paths.lock
            )
            self.assertTrue(configured_paths.worktrees.is_dir())
        queue_events, remote_events = expected_queue_events, expected_remote_events
        text_queue_events, encoded_queue_events = queue_events
        if remote_events is None:
            text_remote_events = encoded_remote_events = None
        else:
            text_remote_events, encoded_remote_events = remote_events

        def invoke(
            argv, call_queue_events, call_remote_events
        ):
            constructors = []
            reads = []
            renderer_trace = []
            clock_calls = []
            original_init = ht.State.__init__
            original_read_text = Path.read_text
            original_path_methods = {
                name: getattr(Path, name)
                for name in (
                    "resolve", "readlink", "stat", "lstat", "exists",
                    "is_file", "is_dir", "read_bytes", "open",
                    "iterdir", "glob", "rglob", "cwd", "absolute",
                )
            }
            original_open = open
            original_io_open = io.open
            original_os_methods = {
                name: getattr(os, name)
                for name in (
                    "open", "close", "stat", "lstat", "scandir",
                    "listdir", "readlink", "access", "fstat", "getcwd",
                )
            }
            remote_start = (
                len(gh.events) if hasattr(gh, "events") else None
            )

            observer_code = getattr(
                ht, "_observe_custody_tree", None
            )
            observer_code = (
                observer_code.__code__
                if observer_code is not None else None
            )
            projection_code = ht.custody_status.__code__
            renderer_code = ht.custody_text.__code__

            def in_code(code):
                frame = sys._getframe(1)
                while frame is not None:
                    if frame.f_code is code:
                        return True
                    frame = frame.f_back
                return False

            def in_projection():
                return (
                    in_code(projection_code)
                    and not in_code(observer_code)
                )

            def observe_probe(label, original):
                def observed(*args, **kwargs):
                    if in_code(renderer_code):
                        renderer_trace.append(label)
                        raise AssertionError(
                            f"unexpected custody renderer access {label}"
                        )
                    if in_projection():
                        raise AssertionError(
                            f"unexpected custody projection access {label}"
                        )
                    return original(*args, **kwargs)
                return observed

            def observed_init(state, path):
                constructors.append(Path(path))
                return original_init(state, path)

            def observed_read_text(path, *args, **kwargs):
                if in_code(renderer_code):
                    renderer_trace.append("Path.read_text")
                    raise AssertionError(
                        "unexpected custody renderer access Path.read_text"
                    )
                if in_projection():
                    raise AssertionError(
                        "unexpected custody projection access Path.read_text"
                    )
                if Path(path) in state_paths:
                    reads.append(Path(path))
                return original_read_text(path, *args, **kwargs)

            with contextlib.ExitStack() as stack:
                stack.enter_context(mock.patch.object(
                    ht.State, "__init__", new=observed_init
                ))
                stack.enter_context(mock.patch.object(
                    Path, "read_text", new=observed_read_text
                ))
                for name, original in original_path_methods.items():
                    stack.enter_context(mock.patch.object(
                        Path,
                        name,
                        new=observe_probe(f"Path.{name}", original),
                    ))
                stack.enter_context(mock.patch(
                    "builtins.open",
                    new=observe_probe("builtins.open", original_open),
                ))
                stack.enter_context(mock.patch.object(
                    io,
                    "open",
                    new=observe_probe("io.open", original_io_open),
                ))
                for name, original in original_os_methods.items():
                    stack.enter_context(mock.patch.object(
                        os,
                        name,
                        new=observe_probe(f"os.{name}", original),
                    ))
                queue_open = stack.enter_context(mock.patch.object(
                    gh, "open_issues", wraps=gh.open_issues
                ))
                writer = stack.enter_context(mock.patch.object(
                    ht, "writer_lock",
                    side_effect=AssertionError(
                        "status acquired writer lock"
                    ),
                ))
                admission = stack.enter_context(mock.patch.object(
                    ht, "admitted_tick",
                    side_effect=AssertionError(
                        "status entered admission"
                    ),
                ))
                save = stack.enter_context(mock.patch.object(
                    ht.State, "save",
                    side_effect=AssertionError("status saved state"),
                ))
                mkdir = stack.enter_context(mock.patch.object(
                    ht, "durable_mkdir",
                    side_effect=AssertionError(
                        "status created a directory"
                    ),
                ))
                with CustodyTreeTrace() as projection_trace:
                    result = self.main_golden(
                        argv, cfg, gh, boundaries,
                        custody_clock=test_clock,
                        clock_calls=clock_calls,
                    )
            self.assertEqual(
                {
                    "probes": projection_trace.probes,
                    "calls": projection_trace.events,
                },
                {
                    "probes": expected_projection_probes,
                    "calls": expected_projection_trace,
                },
                f"custody projection trace for {' '.join(argv)}",
            )
            self.assertEqual(
                renderer_trace,
                expected_renderer_trace,
                f"custody renderer trace for {' '.join(argv)}",
            )
            self.assertEqual(
                len(clock_calls),
                1,
                "custody projection clock samples",
            )
            self.assertEqual(constructors, list(state_paths))
            self.assertEqual(reads, list(state_paths))
            writer.assert_not_called()
            admission.assert_not_called()
            save.assert_not_called()
            mkdir.assert_not_called()
            self.assertEqual(
                list(
                    ("open", call.args[0])
                    for call in queue_open.call_args_list
                ),
                list(call_queue_events),
                f"queue events for {' '.join(argv)}",
            )
            if remote_start is not None:
                self.assertEqual(
                    list(gh.events[remote_start:]),
                    list(call_remote_events),
                    f"complete remote events for {' '.join(argv)}",
                )
            return result

        with ht.writer_lock(self.paths) as admitted:
            self.assertTrue(admitted)
            self.paths.lock.write_text("4242")
            before_bytes = self.file_bytes()
            before_inventory = self.file_inventory()
            text = invoke(
                ["status"],
                text_queue_events,
                text_remote_events,
            )
            encoded = invoke(
                ["status", "--json"],
                encoded_queue_events,
                encoded_remote_events,
            )
            after_bytes = self.file_bytes()
            after_inventory = self.file_inventory()
        after_lock_bytes = self.file_bytes()

        if expected_custody_text is _PA_ABSENT:
            self.assertEqual(text, expected_text)
        else:
            offset = 0
            for line in expected_custody_text.splitlines(True):
                position = expected_text[1].find(line, offset)
                self.assertNotEqual(
                    position,
                    -1,
                    "custody text comparison: supplied line is missing "
                    "from expected text",
                )
                offset = position + len(line)
            self.assertEqual(
                text,
                expected_text,
                "custody text stdout comparison",
            )
        self.assertEqual((encoded[0], encoded[2]), (0, ""))
        report = json.loads(encoded[1])
        if expected_custody is not _PA_ABSENT:
            self.assertEqual(
                set(report),
                _PA_LEGACY_REPORT_KEYS | {"custody"},
                "custody JSON root keys",
            )
        for field, expected in expected_json_fields.items():
            self.assertIn(field, report)
            self.assertEqual(report[field], expected)
        self.assertEqual(report["queue"], expected_queue)
        self.assertEqual(report["nightly_queue"], expected_nightly_queue)
        self.assertEqual(report["state_loads"], expected_state_loads)
        self.assertEqual(report["retro_queue"], expected_retro_queue)
        if expected_custody is _PA_ABSENT:
            self.assertNotIn(
                "custody",
                report,
                "custody JSON decoded root is present",
            )
            self.assertNotIn("custody", encoded[1])
        else:
            self.assertIn(
                "custody", report, "custody JSON comparison"
            )
            for record in report["custody"]["records"]:
                self.assertNotIn(
                    "target_branch",
                    record,
                    "custody JSON actual target branch leakage",
                )
            self.assert_pa_json_value(
                report["custody"],
                expected_custody,
            )
        if expected_custody_text is _PA_ABSENT:
            self.assertNotIn(
                "custody", text[1], "custody text comparison"
            )
        self.assertEqual(
            tuple(boundaries.git_events), expected_git_events
        )
        self.assertEqual(
            tuple(boundaries.launch_events), expected_launch_events
        )
        self.assertEqual(
            tuple(boundaries.forget_events), expected_forget_events
        )
        self.assertEqual(before_bytes, expected_files)
        self.assertEqual(after_bytes, before_bytes)
        self.assertEqual(after_lock_bytes, expected_files)
        self.assertEqual(after_inventory, before_inventory)
        return text[1], encoded[1]

    def file_bytes(self):
        return {
            str(path.relative_to(self.home)): path.read_bytes()
            for path in sorted(self.home.rglob("*"))
            if path.is_file()
        }

    def file_inventory(self):
        inventory = {}
        pending = [self.home]
        while pending:
            parent = pending.pop()
            with os.scandir(parent) as entries:
                for entry in sorted(entries, key=lambda item: item.name):
                    path = Path(entry.path)
                    relative = str(path.relative_to(self.home))
                    info = entry.stat(follow_symlinks=False)
                    if stat.S_ISLNK(info.st_mode):
                        inventory[relative] = ("link", os.readlink(path))
                    elif stat.S_ISDIR(info.st_mode):
                        inventory[relative] = ("directory",)
                        pending.append(path)
                    elif stat.S_ISREG(info.st_mode):
                        inventory[relative] = ("file", info.st_size)
                    else:
                        inventory[relative] = ("other", info.st_mode)
        return inventory

    @staticmethod
    def saved_bytes(value):
        return json.dumps(value, indent=2, sort_keys=True).encode()

    @staticmethod
    def expected_seeded_bytes(value, seed):
        expected = seeded_expected(value, seed)
        return json.dumps(expected, indent=2, sort_keys=True).encode()


class RecordlessTraceGitHub(FakeGitHub):
    """Argument-aware remote seam with a hard call bound."""

    def __init__(self, by_repo=None, pulls=None, limit=200):
        super().__init__([])
        self.by_repo = {repo: list(items) for repo, items in (by_repo or {}).items()}
        self.pulls = dict(pulls or {})
        self.events = []
        self.limit = limit
        self.issues = {
            item["number"]: item
            for items in self.by_repo.values()
            for item in items
        }

    def _event(self, *event):
        if len(self.events) >= self.limit:
            raise AssertionError(f"remote call limit exceeded: {event!r}")
        self.events.append(event)

    def open_issues(self, repo):
        self._event("open", repo)
        return [
            item for item in self.by_repo.get(repo, [])
            if item.get("state", "OPEN") == "OPEN"
        ]

    def issue(self, repo, n):
        self._event("issue", repo, n)
        return super().issue(repo, n)

    def comments(self, repo, n):
        self._event("comments", repo, n)
        return super().comments(repo, n)

    def edit_labels(self, repo, n, add=(), remove=()):
        self._event("labels", repo, n, tuple(add), tuple(remove))
        return super().edit_labels(repo, n, add, remove)

    def create_comment(self, repo, n, body):
        self._event("comment", repo, n, body)
        return super().create_comment(repo, n, body)

    def edit_comment(self, repo, comment_id, body):
        self._event("edit", repo, comment_id, body)
        return super().edit_comment(repo, comment_id, body)

    def close(self, repo, n, not_planned=False):
        self._event("close", repo, n, not_planned)
        return super().close(repo, n, not_planned)

    def pull(self, url):
        self._event("pull", url)
        return super().pull(url)

    def label_pull(self, url, add="", remove=""):
        self._event("label_pull", url, add, remove)
        return super().label_pull(url, add, remove)

    def ready_pull(self, url):
        self._event("ready", url)
        return super().ready_pull(url)

    def branch_pulls(self, repo, branch):
        self._event("branch_pulls", repo, branch)
        return super().branch_pulls(repo, branch)

    def create_label(self, repo, name, color, description):
        self._event("label", repo, name, color, description)
        return super().create_label(repo, name, color, description)

    def create_issue(self, repo, title, body, labels=()):
        self._event("issue_create", repo, title, body, tuple(labels))
        return super().create_issue(repo, title, body, labels)

    def disarm_pull(self, url):
        self._event("disarm", url)
        return super().disarm_pull(url)


class RecordlessBoundaries:
    """Small Git and launch fakes; no runner branch is replaced."""

    def __init__(self, home: Path, statuses=None, launcher=None, limit=200):
        self.home = home
        self.statuses = dict(statuses or {})
        self.launcher_result = launcher or {}
        self.git_events = []
        self.launch_events = []
        self.limit = limit
        self.land_events = []
        self.persistence_events = []
        self.forget_events = []
        self.launched = False
        self.lane_ref = ""

    def forget(self, path, home):
        self.forget_events.append((Path(path), Path(home)))

    def run(self, runner, args, allow_dry=False, cwd=None, check=True):
        if len(self.git_events) >= self.limit:
            raise AssertionError(f"git call limit exceeded: {args!r}")
        self.git_events.append((tuple(str(arg) for arg in args), str(cwd) if cwd else ""))
        if "worktree" in args and "remove" in args:
            self.persistence_events.append((
                "drop", str(Path(args[-1]).relative_to(self.home))
            ))
        if args[:3] == ["git", "-C", str(runner.paths.clone)] and "worktree" in args:
            if "add" in args:
                if "-B" in args:
                    target = Path(args[args.index("-B") + 2])
                elif "-b" in args:
                    target = Path(args[args.index("-b") + 2])
                else:
                    target = Path(args[args.index("add") + 1])
                target.mkdir(parents=True, exist_ok=True)
        if args[:2] == ["gh", "repo"]:
            (runner.paths.clone / ".git").mkdir(parents=True, exist_ok=True)
        return subprocess.CompletedProcess(args, 0, "", "")

    def land_git(self, repo, *args, **kwargs):
        event = (str(repo), tuple(str(arg) for arg in args))
        if len(self.git_events) >= self.limit:
            raise AssertionError(f"git call limit exceeded: {event!r}")
        self.git_events.append(event)
        proc = subprocess.CompletedProcess(list(args), 0, "", "")
        if self.lane_ref and tuple(str(arg) for arg in args)[:4] == (
            "ls-remote", "origin", "refs/heads/agents/*"
        ) and self.launched:
            proc.stdout = f"{'c' * 40}\trefs/heads/{self.lane_ref}\n"
        return proc

    def land(self, lane, base, **kwargs):
        self.land_events.append((lane, base, kwargs.get("expected_sha")))
        return {"parent": "", "merge": "d" * 40}

    def launch(self, runner, label, worktree, prompt, log):
        if len(self.launch_events) >= self.limit:
            raise AssertionError(f"launch call limit exceeded: {label!r}")
        self.launch_events.append((
            label,
            str(worktree.relative_to(self.home)),
            prompt,
        ))
        self.launched = True
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text("recordless launcher fixture\n")
        status = self.statuses.get(label)
        if status is not None:
            status_path = (
                worktree / "build" / "retro" / f"{status[1]}.status.json"
                if isinstance(status, tuple)
                else runner.paths.status_file(label)
            )
            status_path.parent.mkdir(parents=True, exist_ok=True)
            status_path.write_text(json.dumps(
                status[0] if isinstance(status, tuple) else status
            ))
        configured = self.launcher_result.get(label, {})
        seed = configured.get("retro_seed")
        if seed:
            path = worktree / "build" / "retro" / seed["name"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(seed["value"]))
        runner.guard_tampered = configured.get("tampered", False)
        runner.t3_stray = configured.get("stray", False)
        runner.stray = configured.get("stray", False)
        return configured.get("code", 0)


class RecordlessAckGitHub(RecordlessTraceGitHub):
    def __init__(self, by_repo, old, head, pr=17):
        super().__init__(by_repo)
        self.old = old
        self.head = head
        self.pr = pr

    def commit_record(self, repo, sha):
        self._event("commit_record", repo, sha)
        return {
            "committer": {"login": "web-flow"},
            "commit": {
                "message": f"merge ({self.pr})",
                "verification": {"verified": True, "reason": "valid"},
            },
        }

    def commit_pulls(self, repo, sha):
        self._event("commit_pulls", repo, sha)
        return [{
            "number": self.pr,
            "merged_at": "2026-11-22T12:00:00Z",
            "merge_commit_sha": self.head,
            "base": {"ref": "main"},
            "head": {"sha": self.head},
        }]

    def live_requirements(self, repo, branch):
        self._event("requirements", repo, branch)
        return {
            "problems": [],
            "contexts": [("pr-checks", 77)],
            "updated_at": datetime(2026, 11, 21, tzinfo=timezone.utc),
        }

    def check_runs(self, repo, sha):
        self._event("checks", repo, sha)
        return [{
            "name": "pr-checks",
            "id": 1,
            "app": {"id": 77},
            "conclusion": "success",
            "completed_at": "2026-11-22T13:00:00Z",
        }]


class RecordlessQueueErrorGitHub(RecordlessTraceGitHub):
    def open_issues(self, repo):
        self._event("open", repo)
        raise ht.TriageError("synthetic queue failure")


class RecordlessAckBoundaries(RecordlessBoundaries):
    def __init__(self, home, old, head):
        super().__init__(home)
        self.old = old
        self.head = head

    def land_git(self, repo, *args, **kwargs):
        proc = super().land_git(repo, *args, **kwargs)
        values = tuple(str(arg) for arg in args)
        if values[:3] == ("ls-remote", "origin", "refs/heads/main"):
            proc.stdout = f"{self.head}\trefs/heads/main\n"
        elif values[:2] == ("rev-list", "--first-parent"):
            proc.stdout = self.head
        elif values[:3] == ("rev-list", "--parents", "-n1"):
            proc.stdout = f"{self.head} {self.old}\n"
        return proc


class LoadAndMissingTests(StoreTestBase):
    def test_legacy_map_and_unknown_top_level_field_survive_a_save(self):
        opaque = {"version": ["not interpreted"], "nested": {"owner": "kept"}}
        self.write_raw(self.paths.state, self.legacy(
            history=[{"issue": 41, "outcome": "done"}],
            opaque_extension=opaque,
        ))

        state = ht.State(self.paths.state)
        self.assertTrue(state.writable)
        state.save()

        reopened = ht.State(self.paths.state)
        self.assertTrue(reopened.writable)
        self.assertEqual(reopened.data["opaque_extension"], opaque)
        self.assertEqual(reopened.data["history"][0]["outcome"], "done")

    def test_fresh_missing_store_is_observed_not_remembered_and_can_be_saved(self):
        path = self.home / "missing" / "state.json"
        state = ht.State(path)
        self.assertTrue(state.writable)
        self.assertEqual(state.read_result, {
            "kind": "not_found",
            "exists": "no",
            "installation": "unknown",
        })
        self.assertFalse(path.exists())

        state.data["opaque_extension"] = {"first": True}
        state.save()
        reopened = ht.State(path)
        self.assertEqual(reopened.read_result, {"kind": "loaded", "exists": "yes"})
        self.assertEqual(reopened.data["opaque_extension"], {"first": True})

    def test_read_parse_root_and_legacy_type_faults_refuse_without_rewriting(self):
        cases = ("read", "parse", "root", "type")
        for store in ("primary", "nightly", "retro"):
            path = self.logical_path(store)
            for kind in cases:
                with self.subTest(store=store, kind=kind):
                    if kind == "read":
                        self.write_raw(path, self.legacy())
                    elif kind == "parse":
                        self.write_raw(path, "{")
                    elif kind == "root":
                        self.write_raw(path, [])
                    else:
                        self.write_raw(path, self.legacy(jobs=[]))
                    before = path.read_bytes()
                    context = (
                        mock.patch.object(Path, "read_text", side_effect=OSError("synthetic"))
                        if kind == "read" else mock.patch.dict(os.environ, {}, clear=False)
                    )
                    with context:
                        state = ht.State(path)
                    self.assertFalse(state.writable)
                    self.assertEqual(state.load_faults[0]["kind"], kind)
                    with self.assertRaises(ht.StateLoadError):
                        state.require_writable()
                    with self.assertRaises(ht.StateLoadError):
                        state.save()
                    self.assertEqual(path.read_bytes(), before)

    def test_duplicate_keys_are_a_parse_fault(self):
        self.write_raw(self.paths.state, '{"history":[],"history":[]}')
        state = ht.State(self.paths.state)
        self.assertEqual(state.load_faults, [{"kind": "parse", "exists": "yes"}])

    def test_retro_queue_and_done_types_are_checked_before_retro_iteration(self):
        path = self.logical_path("retro")
        for invalid in ({"queue": {}}, {"done": ["not-an-item"]}):
            with self.subTest(invalid=invalid):
                self.write_raw(path, self.legacy(**invalid))
                state = ht.State(path)
                self.assertFalse(state.writable)
                self.assertEqual(state.load_faults[0], {
                    "kind": "type",
                    "exists": "yes",
                })


class CustodyTreeObserverTests(StoreTestBase):
    def tearDown(self):
        gc.collect()
        super().tearDown()

    def expected_walk(self, layout, basename, stat_result="ok"):
        names = ["/"] + [
            item
            for item in os.fspath(layout.paths.root).split(os.sep)
            if item
        ] + ["worktrees"]
        events = []
        for index, name in enumerate(names):
            if index == 0:
                parent = None
            else:
                parent = f"fd{index - 1}"
            events.append((
                "open", name, CustodyTreeTrace._FLAGS,
                parent, "ok", f"fd{index}",
            ))
            if index:
                events.append(("close", f"fd{index - 1}", "ok"))
        parent = f"fd{len(names) - 1}"
        if stat_result == "missing":
            stat_error = errno.ENOENT
        elif isinstance(stat_result, int):
            stat_error = stat_result
        else:
            stat_error = None
        if stat_error is None:
            events.append(("stat", basename, parent, False, "ok"))
        else:
            events.append((
                "stat", basename, parent, False, "error", stat_error
            ))
        events.append(("close", parent, "ok"))
        return events

    def expected_open_ordinal(self, layout, component):
        names = ["/"] + [
            item
            for item in os.fspath(layout.paths.root).split(os.sep)
            if item
        ]
        if component == "worktrees":
            names.append("worktrees")
        return max(
            index for index, name in enumerate(names)
            if name == component
        )

    def expected_open_cutoff(self, layout, component, error):
        names = ["/"] + [
            item
            for item in os.fspath(layout.paths.root).split(os.sep)
            if item
        ]
        if component == "worktrees":
            names.append("worktrees")
        failure_index = self.expected_open_ordinal(
            layout, component
        )
        events = []
        for index in range(failure_index):
            name = names[index]
            parent = None if index == 0 else f"fd{index - 1}"
            events.append((
                "open", name, CustodyTreeTrace._FLAGS,
                parent, "ok", f"fd{index}",
            ))
            if index:
                events.append(("close", f"fd{index - 1}", "ok"))
        parent = None if failure_index == 0 else f"fd{failure_index - 1}"
        events.append((
            "open", names[failure_index], CustodyTreeTrace._FLAGS,
            parent, "error", error,
        ))
        if parent is not None:
            events.append(("close", parent, "ok"))
        return events

    def assert_open_cutoff(
            self, trace, layout, component, allowed_errors,
    ):
        failures = [
            event for event in trace.events
            if event[0] == "open" and event[4] == "error"
        ]
        self.assertEqual(len(failures), 1)
        error = failures[0][-1]
        self.assertIn(error, allowed_errors)
        self.assertEqual(
            trace.events,
            self.expected_open_cutoff(layout, component, error),
        )
        trace.assert_owned_once(self)

    def test_observer_observes_each_exact_positive_name(self):
        """Fails if: a producer loses its prefix, suffix spelling or final no-follow stat."""
        cases = (
            ("request:42", "42"),
            ("nightly:52", "nightly-52"),
            ("job:Researcher", "job-Researcher"),
            ("retro:Task-Mixed", "retro-Task-Mixed"),
        )
        for index, (producer, basename) in enumerate(cases):
            with self.subTest(producer=producer):
                layout = CustodyTreeLayout(
                    self, f"positive-{index}"
                )
                layout.leaf(basename)
                with CustodyTreeTrace() as trace:
                    observed = ht._observe_custody_tree(
                        layout.paths, producer
                    )
                self.assertEqual(observed, (True, None))
                self.assertEqual(
                    trace.events,
                    self.expected_walk(layout, basename),
                )
                trace.assert_owned_once(self)

    def test_observer_reports_missing_leaf_after_terminal_stat(self):
        """Fails if: a leaf ENOENT becomes unknown or triggers another metadata call."""
        layout = CustodyTreeLayout(self, "missing-leaf")
        with CustodyTreeTrace() as trace:
            observed = ht._observe_custody_tree(
                layout.paths, "request:42"
            )
        self.assertEqual(observed, (False, "missing_tree"))
        self.assertEqual(
            trace.events,
            self.expected_walk(layout, "42", "missing"),
        )
        trace.assert_owned_once(self)

    def test_observer_distinguishes_missing_root_and_worktrees(self):
        """Fails if: root ENOENT is absence or either walk continues past its cutoff."""
        cases = (
            (
                "root", "root", "absent", "directory", "runner",
                {errno.ENOENT},
            ),
            (
                "worktrees", "worktrees", "directory", "absent",
                "worktrees", {errno.ENOENT},
            ),
        )
        for name, _label, root_kind, worktrees_kind, cutoff, errors in cases:
            with self.subTest(case=name):
                layout = CustodyTreeLayout(
                    self, name, root=root_kind,
                    worktrees=worktrees_kind,
                )
                with CustodyTreeTrace() as trace:
                    observed = ht._observe_custody_tree(
                        layout.paths, "request:42"
                    )
                expected = (
                    (False, "missing_tree")
                    if name == "worktrees"
                    else (None, "unreadable_tree")
                )
                self.assertEqual(observed, expected)
                self.assert_open_cutoff(
                    trace, layout, cutoff, errors
                )

    def test_observer_rejects_wrong_kind_parents(self):
        """Fails if: a regular file at root or worktrees is classified as missing."""
        cases = (
            ("file-root", "file", "absent", "runner"),
            ("file-worktrees", "directory", "file", "worktrees"),
        )
        for name, root_kind, worktrees_kind, cutoff in cases:
            with self.subTest(case=name):
                layout = CustodyTreeLayout(
                    self, name, root=root_kind,
                    worktrees=worktrees_kind,
                )
                with CustodyTreeTrace() as trace:
                    observed = ht._observe_custody_tree(
                        layout.paths, "request:42"
                    )
                self.assertEqual(
                    observed, (None, "unreadable_tree")
                )
                self.assert_open_cutoff(
                    trace, layout, cutoff, {errno.ENOTDIR}
                )

    def test_observer_never_follows_directory_links(self):
        """Fails if: a linked ancestor, root or worktrees is traversed."""
        cases = (
            ("linked-parent", "linked_parent", "directory",
             "linked-parent"),
            ("linked-root", "link", "directory", "runner"),
            ("linked-worktrees", "directory", "link", "worktrees"),
        )
        for name, root_kind, worktrees_kind, cutoff in cases:
            with self.subTest(case=name):
                layout = CustodyTreeLayout(
                    self, name, root=root_kind,
                    worktrees=worktrees_kind,
                )
                layout.leaf("42")
                with CustodyTreeTrace() as trace:
                    observed = ht._observe_custody_tree(
                        layout.paths, "request:42"
                    )
                self.assertEqual(
                    observed, (None, "unreadable_tree")
                )
                self.assert_open_cutoff(
                    trace, layout, cutoff,
                    {errno.ELOOP, errno.ENOTDIR},
                )

    def test_observer_rejects_non_directory_leaf_modes_without_opening(self):
        """Fails if: a link, file or FIFO is opened or mistaken for absence or a directory."""
        kinds = (
            "file", "inside_link", "outside_link",
            "dangling_link", "fifo",
        )
        for index, kind in enumerate(kinds):
            with self.subTest(kind=kind):
                layout = CustodyTreeLayout(self, f"leaf-{index}")
                layout.leaf("42", kind)
                with CustodyTreeTrace() as trace:
                    observed = ht._observe_custody_tree(
                        layout.paths, "request:42"
                    )
                self.assertEqual(
                    observed, (None, "unreadable_tree")
                )
                self.assertEqual(
                    trace.events, self.expected_walk(layout, "42")
                )
                trace.assert_owned_once(self)

    def test_observer_maps_one_shot_stage_errors_and_continues_siblings(self):
        """Fails if: injected metadata errors become missing, leak text or prevent the next observation."""
        cases = (
            ("root-access", "open", "runner", errno.EACCES),
            ("worktrees-loop", "open", "worktrees", errno.ELOOP),
            ("worktrees-kind", "open", "worktrees", errno.ENOTDIR),
            ("leaf-io", "stat", "42", errno.EIO),
        )
        for name, operation, target, error in cases:
            with self.subTest(case=name):
                layout = CustodyTreeLayout(self, name)
                layout.leaf("42")
                injection_target = (
                    self.expected_open_ordinal(layout, target)
                    if operation == "open"
                    else target
                )
                with CustodyTreeTrace() as control:
                    self.assertEqual(
                        ht._observe_custody_tree(
                            layout.paths, "request:42"
                        ),
                        (True, None),
                    )
                control.assert_owned_once(self)
                with CustodyTreeTrace(
                    inject=(operation, injection_target, error)
                ) as trace:
                    observed = ht._observe_custody_tree(
                        layout.paths, "request:42"
                    )
                self.assertEqual(
                    observed, (None, "unreadable_tree")
                )
                self.assertNotIn("trace canary", repr(observed))
                trace.assert_fired(self)
                trace.assert_owned_once(self)
                if operation == "open":
                    self.assert_open_cutoff(
                        trace, layout, target, {error}
                    )
                else:
                    self.assertEqual(
                        trace.events,
                        self.expected_walk(layout, "42", error),
                    )
                with CustodyTreeTrace() as sibling:
                    self.assertEqual(
                        ht._observe_custody_tree(
                            layout.paths, "request:42"
                        ),
                        (True, None),
                    )
                sibling.assert_owned_once(self)

    def test_observer_cleanup_failure_overrides_result_and_retires_all_fds(self):
        """Fails if: a consumed close is retried, remaining cleanup is skipped or missing survives."""
        layout = CustodyTreeLayout(self, "cleanup")
        layout.leaf("42")
        with CustodyTreeTrace(close_failure=True) as trace:
            observed = ht._observe_custody_tree(
                layout.paths, "request:42"
            )
        self.assertEqual(observed, (None, "unreadable_tree"))
        trace.assert_fired(self)
        trace.assert_owned_once(self)
        self.assertEqual(trace.closed, ["fd0", "fd1"])
        first_component = os.fspath(
            layout.paths.root
        ).split(os.sep)[1]
        self.assertEqual(trace.events, [
            (
                "open", "/", CustodyTreeTrace._FLAGS,
                None, "ok", "fd0",
            ),
            (
                "open", first_component, CustodyTreeTrace._FLAGS,
                "fd0", "ok", "fd1",
            ),
            (
                "close", "fd0", "ok", "injected-error",
                errno.EIO,
            ),
            ("close", "fd1", "ok"),
        ])

    def test_observer_final_close_failure_overrides_missing_leaf(self):
        """Fails if: final cleanup failure lets a missing leaf remain positively absent."""
        layout = CustodyTreeLayout(self, "cleanup-final-missing")
        root_components = [
            item
            for item in os.fspath(layout.paths.root).split(os.sep)
            if item
        ]
        worktrees_symbol = f"fd{len(root_components) + 1}"
        with CustodyTreeTrace(
            close_failure=worktrees_symbol
        ) as trace:
            observed = ht._observe_custody_tree(
                layout.paths, "request:42"
            )
        self.assertEqual(observed, (None, "unreadable_tree"))
        trace.assert_fired(self)
        trace.assert_owned_once(self)
        expected = self.expected_walk(layout, "42", "missing")
        expected[-1] = (
            "close", worktrees_symbol, "ok", "injected-error",
            errno.EIO,
        )
        self.assertEqual(trace.events, expected)

    def test_observer_final_close_failure_overrides_positive_leaf(self):
        """Fails if: final cleanup failure lets a positive result survive."""
        layout = CustodyTreeLayout(self, "cleanup-final-positive")
        layout.leaf("42")
        root_components = [
            item
            for item in os.fspath(layout.paths.root).split(os.sep)
            if item
        ]
        worktrees_symbol = f"fd{len(root_components) + 1}"
        with CustodyTreeTrace(
            close_failure=worktrees_symbol
        ) as trace:
            observed = ht._observe_custody_tree(
                layout.paths, "request:42"
            )
        self.assertEqual(observed, (None, "unreadable_tree"))
        trace.assert_fired(self)
        trace.assert_owned_once(self)
        expected = self.expected_walk(layout, "42")
        expected[-1] = (
            "close", worktrees_symbol, "ok", "injected-error",
            errno.EIO,
        )
        self.assertEqual(trace.events, expected)

    def test_observer_worktrees_transition_close_failure_cleans_new_fd(self):
        """Fails if: transition cleanup failure skips the new worktrees fd or reaches the leaf."""
        layout = CustodyTreeLayout(self, "cleanup-transition")
        layout.leaf("42")
        root_components = [
            item
            for item in os.fspath(layout.paths.root).split(os.sep)
            if item
        ]
        root_symbol = f"fd{len(root_components)}"
        with CustodyTreeTrace(close_failure=root_symbol) as trace:
            observed = ht._observe_custody_tree(
                layout.paths, "request:42"
            )
        self.assertEqual(observed, (None, "unreadable_tree"))
        trace.assert_fired(self)
        trace.assert_owned_once(self)
        expected = self.expected_walk(layout, "42")[:-2]
        expected[-1] = (
            "close", root_symbol, "ok", "injected-error",
            errno.EIO,
        )
        expected.append((
            "close", f"fd{len(root_components) + 1}", "ok"
        ))
        self.assertEqual(trace.events, expected)

    def test_observer_unsafe_roots_and_names_short_circuit_without_io(self):
        """Fails if: a private unsafe operand reaches cwd, a directory open or a stat."""
        invalid_roots = (
            "relative-runner",
            "//ambiguous-runner",
            "/private/../relative-runner",
            "/root\0runner",
            "/root\ud800",
        )
        for index, spelling in enumerate(invalid_roots):
            with self.subTest(root=index):
                cfg = dict(self.cfg)
                cfg["root"] = spelling
                paths = ht.Paths(cfg, self.home)
                with CustodyTreeTrace() as trace:
                    observed = ht._observe_custody_tree(
                        paths, "request:42"
                    )
                self.assertEqual(
                    observed, (None, "unreadable_tree")
                )
                self.assertEqual(trace.events, [])
        layout = CustodyTreeLayout(self, "unsafe-name")
        invalid_names = (
            "other:42",
            "request:",
            "request:a/b",
            "request:a\0b",
            "request:.",
            "request:..",
        )
        for index, producer in enumerate(invalid_names):
            with self.subTest(producer=index):
                with CustodyTreeTrace() as trace:
                    observed = ht._observe_custody_tree(
                        layout.paths, producer
                    )
                self.assertEqual(
                    observed, (None, "unreadable_tree")
                )
                self.assertEqual(trace.events, [])

    def test_observer_preserves_long_decimal_suffix_at_real_stat_boundary(self):
        """Fails if: an unbounded decimal spelling is converted or its OS error becomes missing."""
        layout = CustodyTreeLayout(self, "long-name")
        basename = "9" * 1000
        with CustodyTreeTrace() as trace:
            observed = ht._observe_custody_tree(
                layout.paths, f"request:{basename}"
            )
        self.assertEqual(observed, (None, "unreadable_tree"))
        self.assertEqual(
            trace.events,
            self.expected_walk(layout, basename, errno.ENAMETOOLONG),
        )
        trace.assert_owned_once(self)

    def test_observer_walks_afresh_without_cache(self):
        """Fails if: a second observation reuses a prior absence or descriptor walk."""
        layout = CustodyTreeLayout(self, "uncached")
        with CustodyTreeTrace() as first:
            absent = ht._observe_custody_tree(
                layout.paths, "request:42"
            )
        self.assertEqual(absent, (False, "missing_tree"))
        self.assertEqual(
            first.events, self.expected_walk(layout, "42", "missing")
        )
        first.assert_owned_once(self)
        layout.leaf("42")
        with CustodyTreeTrace() as second:
            present = ht._observe_custody_tree(
                layout.paths, "request:42"
            )
        self.assertEqual(present, (True, None))
        self.assertEqual(
            second.events, self.expected_walk(layout, "42")
        )
        second.assert_owned_once(self)


class CustodySchemaTests(StoreTestBase):
    @staticmethod
    def _clone(value):
        return json.loads(json.dumps(value))

    @staticmethod
    def _leaf(aggregate, seed):
        return aggregate["records"][seed.repository][seed.intake][
            seed.producer
        ][seed.generation]

    @staticmethod
    def _key(seed):
        return {
            "repository": seed.repository,
            "intake": seed.intake,
            "producer": seed.producer,
            "generation": seed.generation,
        }

    def _write_custody(self, store, aggregate, extra=None):
        path = self.logical_path(store)
        value = self.legacy(**(extra or {}))
        value["custody"] = self._clone(aggregate)
        self.write_raw(path, value)
        return path

    def _assert_custody_fault(
            self, store, aggregate, kind, scope="record",
            version=1, key=None,
    ):
        path = self._write_custody(store, aggregate)
        before = path.read_bytes()
        state = ht.State(path)
        self.assertFalse(state.writable)
        expected = {
            "kind": kind,
            "exists": "yes",
            "scope": scope,
            "version": version,
            "key": key,
        }
        self.assertIn(expected, state.load_faults)
        self.assertEqual(path.read_bytes(), before)
        with self.assertRaises(ht.StateLoadError):
            state.require_writable()
        return state

    def test_custody_wire_field_matrix_refuses_each_invalid_cell(self):
        """Fails if: one invalid wire cell is accepted in a correctly placed intake."""
        for seed, store in (
            (self.request_seed(42), "primary"),
            (self.nightly_seed(), "nightly"),
        ):
            cases = [
                (
                    "phase type", "phase",
                    lambda record: record.__setitem__("phase", []),
                ),
                (
                    "phase enum", "phase",
                    lambda record: record.__setitem__("phase", "ready"),
                ),
                (
                    "since spelling", "type",
                    lambda record: record.__setitem__(
                        "since", "2026-11-23 12:00:00Z"
                    ),
                ),
                (
                    "since calendar", "type",
                    lambda record: record.__setitem__(
                        "since", "2026-02-30T12:00:00Z"
                    ),
                ),
                (
                    "outcome closed", "type",
                    lambda record: record["original_outcome"].__setitem__(
                        "extra", True
                    ),
                ),
                (
                    "outcome exit bool", "type",
                    lambda record: record["original_outcome"].__setitem__(
                        "exit_code", False
                    ),
                ),
                (
                    "outcome state", "type",
                    lambda record: record["original_outcome"].__setitem__(
                        "state", "rejected"
                    ),
                ),
                (
                    "target branch", "type",
                    lambda record: record["target"].__setitem__(
                        "branch", "agents/report"
                    ),
                ),
                (
                    "target archive name", "type",
                    lambda record: record["target"].__setitem__(
                        "archive_name", "../archive"
                    ),
                ),
                (
                    "target archive session", "type",
                    lambda record: record["target"].__setitem__(
                        "archive_session", "bad session"
                    ),
                ),
                (
                    "target source repository", "namespace",
                    lambda record: record["target"].__setitem__(
                        "source_repository", "Example/Product"
                    ),
                ),
                (
                    "pre refs", "type",
                    lambda record: record["pre_refs"].__setitem__(
                        record["target"]["branch"], "deadbeef"
                    ),
                ),
                (
                    "bindings container", "type",
                    lambda record: record.__setitem__("bindings", []),
                ),
                (
                    "attempts bool", "type",
                    lambda record: record.__setitem__("attempts", True),
                ),
                (
                    "reason enum", "type",
                    lambda record: record.__setitem__("reason", "unknown"),
                ),
                (
                    "next closed", "type",
                    lambda record: record.__setitem__(
                        "next", {"kind": "retry", "at": None}
                    ),
                ),
            ]
            for label, kind, mutate in cases:
                with self.subTest(store=store, cell=label):
                    aggregate = seed.aggregate()
                    mutate(self._leaf(aggregate, seed))
                    self._assert_custody_fault(
                        store, aggregate, kind, key=self._key(seed)
                    )

            envelope_cases = [
                ("aggregate type", [], "type", None),
                ("version missing", {"records": {}}, "version", None),
                ("version bool", {"version": True, "records": {}},
                 "version", None),
                ("version unsupported", {"version": 2, "records": {}},
                 "version", None),
                ("records type", {"version": 1, "records": []},
                 "type", 1),
            ]
            for label, aggregate, kind, version in envelope_cases:
                with self.subTest(store=store, cell=label):
                    self._assert_custody_fault(
                        store, aggregate, kind, "store", version
                    )

        retro = self.stopped_retro_seed()
        for label, mutate, kind in (
            (
                "retro source archive",
                lambda target: target.__setitem__(
                    "source_archive", "bad/name"
                ),
                "type",
            ),
            (
                "retro source queued",
                lambda target: target.__setitem__(
                    "source_queued", "2026-02-30T00:00:00Z"
                ),
                "type",
            ),
            (
                "retro source repository",
                lambda target: target.__setitem__(
                    "source_repository", "example/issues"
                ),
                "namespace",
            ),
        ):
            with self.subTest(cell=label):
                aggregate = retro.aggregate()
                target = self._leaf(aggregate, retro)["target"]
                mutate(target)
                self._assert_custody_fault(
                    "primary", aggregate, kind, key=self._key(retro)
                )

    def test_custody_release_conjunction_and_signed_fields(self):
        """Fails if: release authorization accepts any missing positive proof."""
        for seed, store in (
            (self.request_seed(42), "primary"),
            (self.nightly_seed(), "nightly"),
        ):
            mutations = [
                ("target absent", lambda record:
                 record.pop("target"), "phase"),
                ("original outcome absent", lambda record:
                 record.pop("original_outcome"), "phase"),
                ("release proof absent", lambda record:
                 record.pop("release_proof"), "phase"),
                (
                    "outcome trust",
                    lambda record: (
                        record["original_outcome"].__setitem__(
                            "trust", "untrusted"
                        ),
                        record["original_outcome"].pop("exit_code"),
                        record["original_outcome"].pop("state"),
                    ),
                    "phase",
                ),
                ("outcome exit", lambda record:
                 record["original_outcome"].__setitem__("exit_code", 1),
                 "type"),
                ("outcome state", lambda record:
                 record["original_outcome"].__setitem__(
                     "state", "blocked"
                 ), "phase"),
                ("proof scalar", lambda record:
                 record.__setitem__("release_proof", []), "type"),
                ("inventory", lambda record:
                 record["release_proof"].__setitem__(
                     "inventory", "not_empty"
                 ), "phase"),
                ("unlanded", lambda record:
                 record["release_proof"].__setitem__(
                     "unlanded", "none"
                 ), "phase"),
                ("archive name", lambda record:
                 record["release_proof"].__setitem__(
                     "archive_name", "other-name"
                 ), "phase"),
                ("archive session", lambda record:
                 record["release_proof"].__setitem__(
                     "archive_session", "other-session"
                 ), "phase"),
                ("archive disposition missing", lambda record:
                 record["release_proof"].pop("archive_disposition"), "phase"),
                ("archive disposition", lambda record:
                 record["release_proof"].__setitem__(
                     "archive_disposition", "missing"
                 ), "phase"),
                ("inventory type", lambda record:
                 record["release_proof"].__setitem__("inventory", 1),
                 "type"),
                ("unlanded type", lambda record:
                 record["release_proof"].__setitem__("unlanded", 1),
                 "type"),
                ("archive name type", lambda record:
                 record["release_proof"].__setitem__(
                     "archive_name", "bad/name"
                 ), "type"),
                ("archive session type", lambda record:
                 record["release_proof"].__setitem__(
                     "archive_session", ""
                 ), "type"),
                ("archive disposition type", lambda record:
                 record["release_proof"].__setitem__(
                     "archive_disposition", 1
                 ), "type"),
                ("bindings", lambda record:
                 record.__setitem__("bindings", {
                     "agents/test": {
                         "disposition": "owner_wait",
                         "tip": "a" * 40,
                         "since": "2026-01-01T00:00:00Z",
                     },
                 }), "phase"),
                (
                    "target absent pending",
                    lambda record: (
                        record.__setitem__("phase", "pending"),
                        record.pop("target"),
                        record.pop("release_proof"),
                    ),
                    "type",
                ),
                (
                    "proof on pending",
                    lambda record: record.__setitem__("phase", "pending"),
                    "phase",
                ),
            ]
            for label, mutate, kind in mutations:
                with self.subTest(store=store, field=label):
                    aggregate = seed.aggregate()
                    mutate(self._leaf(aggregate, seed))
                    state = self._assert_custody_fault(
                        store, aggregate, kind, key=self._key(seed)
                    )
                    if label.endswith(" type"):
                        self.assertEqual(state.load_faults, [{
                            "kind": "type",
                            "exists": "yes",
                            "scope": "record",
                            "version": 1,
                            "key": self._key(seed),
                        }])
                        self.assertEqual(
                            state.vetted_custody_records, ()
                        )

    def test_custody_wire_key_binding_and_optional_matrix(self):
        """Fails if: a hierarchy, copy, binding or optional field is coerced."""
        for seed, store in (
            (self.request_seed(42), "primary"),
            (self.nightly_seed(), "nightly"),
        ):
            key = self._key(seed)
            other_intake = (
                "nightly" if seed.intake == "request" else "request"
            )
            producer_alias = (
                f"{seed.producer.split(':', 1)[0]}:"
                f"0{seed.producer.split(':', 1)[1]}"
            )

            def tree(aggregate):
                records = aggregate["records"]
                intakes = records[seed.repository]
                producers = intakes[seed.intake]
                generations = producers[seed.producer]
                return records, intakes, producers, generations

            hierarchy = [
                (
                    "repository spelling",
                    lambda aggregate: aggregate["records"].__setitem__(
                        "Example/Product",
                        aggregate["records"].pop(seed.repository),
                    ),
                    "namespace", "store", None,
                ),
                (
                    "repository value",
                    lambda aggregate: aggregate["records"].__setitem__(
                        seed.repository, []
                    ),
                    "type", "record", {"repository": seed.repository},
                ),
                (
                    "intake placement",
                    lambda aggregate: tree(aggregate)[0].__setitem__(
                        seed.repository,
                        {
                            other_intake: tree(
                                aggregate
                            )[0][seed.repository][seed.intake],
                        },
                    ),
                    "namespace", "record", {"repository": seed.repository},
                ),
                (
                    "intake value",
                    lambda aggregate: tree(aggregate)[1].__setitem__(
                        seed.intake, []
                    ),
                    "type", "record", {
                        "repository": seed.repository,
                        "intake": seed.intake,
                    },
                ),
                (
                    "producer spelling",
                    lambda aggregate: tree(aggregate)[2].__setitem__(
                        producer_alias,
                        tree(aggregate)[2].pop(seed.producer),
                    ),
                    "namespace", "record", {
                        "repository": seed.repository,
                        "intake": seed.intake,
                    },
                ),
                (
                    "producer value",
                    lambda aggregate: tree(aggregate)[2].__setitem__(
                        seed.producer, []
                    ),
                    "type", "record", {
                        "repository": seed.repository,
                        "intake": seed.intake,
                        "producer": seed.producer,
                    },
                ),
                (
                    "generation spelling",
                    lambda aggregate: tree(aggregate)[3].__setitem__(
                        "../generation",
                        tree(aggregate)[3].pop(seed.generation),
                    ),
                    "key", "record", {
                        "repository": seed.repository,
                        "intake": seed.intake,
                        "producer": seed.producer,
                    },
                ),
                (
                    "record value",
                    lambda aggregate: tree(aggregate)[3].__setitem__(
                        seed.generation, []
                    ),
                    "type", "record", key,
                ),
                (
                    "identity copy",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    ).__setitem__("producer", "request:99"),
                    "key", "record", key,
                ),
                (
                    "target null",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    ).__setitem__("target", None),
                    "type", "record", key,
                ),
                (
                    "outcome null",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    ).__setitem__("original_outcome", None),
                    "type", "record", key,
                ),
                (
                    "pre refs null",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    ).__setitem__("pre_refs", None),
                    "type", "record", key,
                ),
                (
                    "pre refs key",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    )["pre_refs"].__setitem__("refs/heads/-bad", "absent"),
                    "key", "record", key,
                ),
                (
                    "source archive on non-retro",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    )["target"].__setitem__("source_archive", "source"),
                    "namespace", "record", key,
                ),
                (
                    "source queued on non-retro",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    )["target"].__setitem__(
                        "source_queued", "2026-01-01T00:00:00Z"
                    ),
                    "namespace", "record", key,
                ),
                (
                    "next kind",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    ).__setitem__("next", {"kind": "later"}),
                    "type", "record", key,
                ),
                (
                    "next time on human",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    ).__setitem__("next", {
                        "kind": "human",
                        "at": "2026-01-01T00:00:00Z",
                    }),
                    "type", "record", key,
                ),
                (
                    "record delivery alias",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    ).__setitem__("delivery", {}),
                    "key", "record", key,
                ),
                (
                    "record notice alias",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    ).__setitem__("notice", {}),
                    "key", "record", key,
                ),
                (
                    "proof null",
                    lambda aggregate: self._leaf(
                        aggregate, seed
                    ).__setitem__("release_proof", None),
                    "type", "record", key,
                ),
            ]
            for label, mutate, kind, scope, expected_key in hierarchy:
                with self.subTest(store=store, cell=label):
                    aggregate = seed.aggregate()
                    mutate(aggregate)
                    self._assert_custody_fault(
                        store, aggregate, kind, scope, key=expected_key
                    )

            binding_cases = [
                ("lane plain", "invalid lane", "key"),
                ("lane hyphen", "agents/-x", "key"),
                ("lane underscore", "agents/_x", "key"),
                ("binding container", None, "type"),
                ("lane copy", {"lane": "agents/other"}, "key"),
                ("branch copy", {
                    "branch": "refs/heads/agents/other"
                }, "key"),
                ("disposition type", {"disposition": []}, "disposition"),
                ("disposition enum", {
                    "disposition": "terminal"
                }, "disposition"),
                ("tip", {"tip": "deadbeef"}, "type"),
                ("since", {"since": "2026-02-30T00:00:00Z"}, "type"),
                ("pull bool", {"pull": True}, "type"),
                ("reviewed head", {"reviewed_head": "A" * 40}, "type"),
                ("attempts bool", {"attempts": True}, "type"),
                ("reason", {"reason": "unknown"}, "type"),
                ("next extra", {
                    "next": {"kind": "human", "extra": 1}
                }, "type"),
                ("next kind", {"next": {"kind": "later"}}, "type"),
                ("next time on human", {
                    "next": {
                        "kind": "human",
                        "at": "2026-01-01T00:00:00Z",
                    },
                }, "type"),
                ("notices alias", {"notices": {}}, "key"),
                ("delivery alias", {"delivery": {}}, "key"),
            ]
            for label, change, kind in binding_cases:
                with self.subTest(store=store, cell=label):
                    aggregate = seed.aggregate()
                    record = self._leaf(aggregate, seed)
                    record["phase"] = "pending"
                    record.pop("release_proof")
                    binding = {
                        "disposition": "owner_wait",
                        "tip": "a" * 40,
                        "since": "2026-01-01T00:00:00Z",
                    }
                    lane = "agents/test"
                    if label.startswith("lane ") and label not in (
                        "lane copy",
                    ):
                        lane = change
                    elif label == "binding container":
                        binding = change
                    else:
                        binding.update(change)
                    record["bindings"] = {lane: binding}
                    self._assert_custody_fault(
                        store, aggregate, kind, key=key
                    )

    def test_custody_closed_payload_and_extra_boundaries(self):
        """Fails if: opaque extras become authority or closed payloads admit them."""
        for seed, store in (
            (self.request_seed(42), "primary"),
            (self.nightly_seed(), "nightly"),
        ):
            aggregate = seed.aggregate()
            record = self._leaf(aggregate, seed)
            aggregate["future"] = {"envelope": True}
            record["future"] = {"record": True}
            record["target"]["future"] = {"target": True}
            path = self._write_custody(store, aggregate)
            state = ht.State(path)
            self.assertTrue(state.writable)
            with self.assertRaises(TypeError):
                state.vetted_custody_records[0][1]["phase"] = "unknown"
            for closed, field, value in (
                ("original_outcome", "extra", True),
                ("next", "extra", True),
                ("release_proof", "extra", True),
            ):
                with self.subTest(store=store, closed=closed):
                    invalid = seed.aggregate()
                    invalid_record = self._leaf(invalid, seed)
                    if closed == "next":
                        invalid_record["next"] = {"kind": "human"}
                    invalid_record[closed]["extra"] = value
                    self._assert_custody_fault(
                        store, invalid, "type", key=self._key(seed)
                    )

    def test_custody_alias_collisions_refuse_both_spelling_orders(self):
        """Fails if: an alias collision trusts either spelling in any order."""
        for seed, store in (
            (self.request_seed(42), "primary"),
            (self.nightly_seed(), "nightly"),
        ):
            producer_alias = (
                f"{seed.producer.split(':', 1)[0]}:"
                f"0{seed.producer.split(':', 1)[1]}"
            )
            for reverse in (False, True):
                with self.subTest(
                    store=store, collision="producer", reverse=reverse
                ):
                    aggregate = seed.aggregate()
                    records = aggregate["records"]
                    producer_map = records[seed.repository][seed.intake]
                    entries = [
                        (seed.producer, self._clone(
                            producer_map[seed.producer]
                        )),
                        (producer_alias, self._clone(
                            producer_map[seed.producer]
                        )),
                    ]
                    producer_map.clear()
                    producer_map.update(
                        entries[::-1] if reverse else entries
                    )
                    self._assert_custody_fault(
                        store, aggregate, "key",
                        key={
                            "repository": seed.repository,
                            "intake": seed.intake,
                        },
                    )
                with self.subTest(
                    store=store, collision="class", reverse=reverse
                ):
                    aggregate = seed.aggregate()
                    notices = [
                        ("needs_pr", {
                            "state": "intent",
                            "since": "2026-01-01T00:00:00Z",
                        }),
                        ("NEEDS_PR", {
                            "state": "intent",
                            "since": "2026-01-01T00:00:00Z",
                        }),
                    ]
                    self._leaf(aggregate, seed)["notices"] = {
                        "agents/test": {
                            "a" * 40: dict(
                                notices[::-1] if reverse else notices
                            ),
                        },
                    }
                    state = self._assert_custody_fault(
                        store, aggregate, "key", "notice",
                        key={
                            **self._key(seed),
                            "lane": "agents/test",
                            "head": "a" * 40,
                        },
                    )
                    self.assertEqual(state.vetted_custody_records[0][2], ())
                with self.subTest(
                    store=store, collision="head", reverse=reverse
                ):
                    aggregate = seed.aggregate()
                    heads = [
                        ("a" * 40, {
                            "needs_pr": {
                                "state": "intent",
                                "since": "2026-01-01T00:00:00Z",
                            },
                        }),
                        ("A" * 40, {
                            "needs_pr": {
                                "state": "intent",
                                "since": "2026-01-01T00:00:00Z",
                            },
                        }),
                    ]
                    self._leaf(aggregate, seed)["notices"] = {
                        "agents/test": dict(
                            heads[::-1] if reverse else heads
                        ),
                    }
                    state = self._assert_custody_fault(
                        store, aggregate, "key", "notice",
                        key={
                            **self._key(seed),
                            "lane": "agents/test",
                        },
                    )
                    self.assertEqual(state.vetted_custody_records[0][2], ())

    def test_custody_noncanonical_repository_collision_has_store_scope(self):
        """Fails if: rejected repository text is lowercased into a record key."""
        for seed, store in (
            (self.request_seed(42), "primary"),
            (self.nightly_seed(), "nightly"),
        ):
            entries = [
                (
                    "Example/Product",
                    self._clone(seed.aggregate()["records"][seed.repository]),
                ),
                (
                    "EXAMPLE/PRODUCT",
                    self._clone(seed.aggregate()["records"][seed.repository]),
                ),
            ]
            for reverse in (False, True):
                with self.subTest(store=store, reverse=reverse):
                    aggregate = {
                        "version": 1,
                        "records": dict(
                            entries[::-1] if reverse else entries
                        ),
                    }
                    state = self._assert_custody_fault(
                        store, aggregate, "namespace", "store", 1, None
                    )
                    self.assertEqual(state.vetted_custody_records, ())

    def test_custody_notice_field_matrix_refuses_each_invalid_cell(self):
        """Fails if: a malformed notice field is accepted or loses bounded scope."""
        lane = "agents/test"
        head = "a" * 40
        for seed, store in (
            (self.request_seed(42), "primary"),
            (self.nightly_seed(), "nightly"),
        ):
            cases = [
                ("notices container", [], "type"),
                ("lane", {"not a lane": {head: {}}}, "key"),
                ("lane hyphen", {"agents/-x": {head: {}}}, "key"),
                ("lane underscore", {"agents/_x": {head: {}}}, "key"),
                ("heads container", {lane: []}, "type"),
                ("head", {lane: {"A" * 40: {}}}, "key"),
                ("fault classes container", {lane: {head: []}}, "type"),
                ("fault class", {
                    lane: {head: {"unknown": {}}}
                }, "key"),
                ("payload type", {
                    lane: {head: {"needs_pr": []}}
                }, "type"),
                ("state type", {
                    lane: {head: {"needs_pr": {
                        "state": [], "since": "2026-01-01T00:00:00Z",
                    }}}
                }, "type"),
                ("state enum", {
                    lane: {head: {"needs_pr": {
                        "state": "later",
                        "since": "2026-01-01T00:00:00Z",
                    }}}
                }, "type"),
                ("since spelling", {
                    lane: {head: {"needs_pr": {
                        "state": "intent", "since": "not-a-time",
                    }}}
                }, "type"),
                ("since calendar", {
                    lane: {head: {"needs_pr": {
                        "state": "intent",
                        "since": "2026-02-30T00:00:00Z",
                    }}}
                }, "type"),
                ("remote missing", {
                    lane: {head: {"needs_pr": {
                        "state": "confirmed",
                        "since": "2026-01-01T00:00:00Z",
                    }}}
                }, "type"),
                ("remote on intent", {
                    lane: {head: {"needs_pr": {
                        "state": "intent",
                        "since": "2026-01-01T00:00:00Z",
                        "remote_identity": {
                            "repository": "private/issues",
                            "number": 1,
                        },
                    }}}
                }, "type"),
                ("identity copy", {
                    lane: {head: {"needs_pr": {
                        "state": "intent",
                        "since": "2026-01-01T00:00:00Z",
                        "head": "b" * 40,
                    }}}
                }, "key"),
                ("delivery alias", {
                    lane: {head: {"needs_pr": {
                        "state": "intent",
                        "since": "2026-01-01T00:00:00Z",
                        "delivery": {},
                    }}}
                }, "key"),
                ("remote repository", {
                    lane: {head: {"needs_pr": {
                        "state": "confirmed",
                        "since": "2026-01-01T00:00:00Z",
                        "remote_identity": {
                            "repository": "private/Issues",
                            "number": 1,
                        },
                    }}}
                }, "type"),
                ("remote number bool", {
                    lane: {head: {"needs_pr": {
                        "state": "confirmed",
                        "since": "2026-01-01T00:00:00Z",
                        "remote_identity": {
                            "repository": "private/issues",
                            "number": True,
                        },
                    }}}
                }, "type"),
                ("remote number zero", {
                    lane: {head: {"needs_pr": {
                        "state": "confirmed",
                        "since": "2026-01-01T00:00:00Z",
                        "remote_identity": {
                            "repository": "private/issues",
                            "number": 0,
                        },
                    }}}
                }, "type"),
                ("remote extra", {
                    lane: {head: {"needs_pr": {
                        "state": "confirmed",
                        "since": "2026-01-01T00:00:00Z",
                        "remote_identity": {
                            "repository": "private/issues",
                            "number": 1,
                            "extra": True,
                        },
                    }}}
                }, "type"),
            ]
            for label, notices, kind in cases:
                with self.subTest(store=store, cell=label):
                    aggregate = seed.aggregate()
                    self._leaf(aggregate, seed)["notices"] = notices
                    key = self._key(seed)
                    if label not in (
                        "notices container", "lane",
                        "lane hyphen", "lane underscore",
                    ):
                        key["lane"] = lane
                    if label not in (
                        "notices container", "lane",
                        "lane hyphen", "lane underscore",
                        "heads container", "head",
                    ):
                        key["head"] = head
                    if label not in (
                        "notices container", "lane",
                        "lane hyphen", "lane underscore",
                        "heads container", "head",
                        "fault classes container", "fault class",
                    ):
                        key["fault_class"] = "needs_pr"
                    state = self._assert_custody_fault(
                        store, aggregate, kind, "notice", key=key
                    )
                    self.assertTrue(state.vetted_custody_records)

    def test_custody_empty_v1_is_writable_without_a_record_key(self):
        """Fails if: an explicitly empty v1 aggregate is treated as no record."""
        for store in ("primary", "nightly"):
            with self.subTest(store=store):
                path = self._write_custody(
                    store, {"version": 1, "records": {}}
                )
                state = ht.State(path)
                self.assertTrue(state.writable)
                self.assertEqual(state.load_faults, [])
                self.assertEqual(state.vetted_custody_records, ())

    def test_custody_duplicate_name_inside_notice_is_a_file_parse_fault(self):
        """Fails if: a duplicate notice member is partially decoded as a notice fault."""
        for seed, store in (
            (self.request_seed(42), "primary"),
            (self.nightly_seed(), "nightly"),
        ):
            with self.subTest(store=store):
                aggregate = seed.aggregate()
                self._leaf(aggregate, seed)["notices"] = {
                    "agents/test": {
                        "a" * 40: {
                            "needs_pr": {
                                "state": "intent",
                                "since": "2026-01-01T00:00:00Z",
                            },
                        },
                    },
                }
                value = self.legacy(custody=aggregate)
                raw = json.dumps(value, separators=(",", ":"))
                raw = raw.replace(
                    '"state":"intent"',
                    '"state":"intent","state":"confirmed"',
                    1,
                )
                path = self.logical_path(store)
                self.write_raw(path, raw)
                before = path.read_bytes()
                state = ht.State(path)
                self.assertEqual(state.load_faults, [{
                    "kind": "parse",
                    "exists": "yes",
                }])
                self.assertEqual(state.vetted_custody_records, ())
                with self.assertRaises(ht.StateLoadError):
                    state.save()
                self.assertEqual(path.read_bytes(), before)

    def test_custody_bad_record_refuses_store_and_preserves_vetted_sibling(self):
        """Fails if: one bad record is trusted or discarded without refusing its store."""
        for good, bad, store in (
            (self.request_seed(42), self.request_seed(43), "primary"),
            (self.nightly_seed(52), self.nightly_seed(53), "nightly"),
        ):
            for seeds in ((good, bad), (bad, good)):
                with self.subTest(
                    store=store, order=[seed.producer for seed in seeds]
                ):
                    aggregate = CustodySeeds(seeds).aggregate()
                    self._leaf(aggregate, bad)["phase"] = "invalid"
                    state = self._assert_custody_fault(
                        store, aggregate, "phase", key=self._key(bad)
                    )
                    self.assertEqual(
                        [item[0] for item in state.vetted_custody_records],
                        [(
                            good.repository,
                            good.intake,
                            good.producer,
                            good.generation,
                        )],
                    )

    def test_custody_bad_notice_refuses_store_and_preserves_safe_notice(self):
        """Fails if: a bad notice removes its valid body, bindings or safe notice."""
        for seed, store in (
            (self.request_seed(42), "primary"),
            (self.nightly_seed(), "nightly"),
        ):
            aggregate = seed.aggregate()
            record = self._leaf(aggregate, seed)
            notice_items = (
                ("agents/safe", {
                    "a" * 40: {
                        "needs_pr": {
                            "state": "intent",
                            "since": "2026-01-01T00:00:00Z",
                        },
                    },
                }),
                ("agents/bad", {
                    "b" * 40: {
                        "needs_pr": {
                            "state": "unknown",
                            "since": "2026-01-01T00:00:00Z",
                        },
                    },
                }),
            )
            for items in (notice_items, tuple(reversed(notice_items))):
                with self.subTest(
                    store=store, order=[item[0] for item in items]
                ):
                    record["notices"] = dict(items)
                    state = self._assert_custody_fault(
                        store, aggregate, "type", "notice",
                        key={
                            **self._key(seed),
                            "lane": "agents/bad",
                            "head": "b" * 40,
                            "fault_class": "needs_pr",
                        },
                    )
                    self.assertEqual(len(state.vetted_custody_records), 1)
                    body = state.vetted_custody_records[0][1]
                    notices = state.vetted_custody_records[0][2]
                    self.assertEqual(body["phase"], "release_authorized")
                    self.assertEqual(
                        [item[0] for item in notices],
                        [("agents/safe", "a" * 40, "needs_pr")],
                    )

    def test_custody_absent_notice_is_valid_and_not_synthesized(self):
        """Fails if: missing notices become a delivery fact or a writer veto."""
        for seed, store in (
            (self.request_seed(42), "primary"),
            (self.nightly_seed(), "nightly"),
        ):
            with self.subTest(store=store):
                path = self._write_custody(store, seed.aggregate())
                state = ht.State(path)
                self.assertTrue(state.writable)
                self.assertEqual(state.vetted_custody_records[0][2], ())

    def test_custody_tuple_collision_trusts_neither_spelling(self):
        """Fails if: an alias collision trusts either record spelling."""
        for seed, source, store in (
            (
                self.request_seed(42),
                self.request_seed(43),
                "primary",
            ),
            (
                self.nightly_seed(52),
                self.nightly_seed(53),
                "nightly",
            ),
        ):
            aggregate = seed.aggregate()
            record_map = aggregate["records"]
            canonical = seed.repository
            alias = canonical.upper()
            record_map[alias] = self._clone(record_map[canonical])
            disjoint = CustodySeed(
                repository="other/product",
                intake=source.intake,
                producer=source.producer,
                generation=source.generation,
                branch=source.branch,
                archive_name=source.archive_name,
                archive_session=source.archive_session,
                source_repository=source.source_repository,
            )
            record_map[disjoint.repository] = {
                disjoint.intake: {
                    disjoint.producer: {
                        disjoint.generation: self._clone(
                            self._leaf(disjoint.aggregate(), disjoint)
                        ),
                    },
                },
            }
            expected = [(
                disjoint.repository,
                disjoint.intake,
                disjoint.producer,
                disjoint.generation,
            )]
            for order in (
                tuple(record_map),
                tuple(reversed(tuple(record_map))),
            ):
                with self.subTest(store=store, order=order):
                    aggregate["records"] = {
                        repository: record_map[repository]
                        for repository in order
                    }
                    state = self._assert_custody_fault(
                        store, aggregate, "key",
                        key={"repository": seed.repository},
                    )
                    self.assertEqual(
                        [item[0] for item in state.vetted_custody_records],
                        expected,
                    )

    def test_custody_unbounded_namespace_fault_has_no_guessed_view(self):
        """Fails if: an unbounded namespace leak invents a projected identity."""
        aggregate = {
            "version": 1,
            "records": {
                "../outside": {
                    "request": {},
                },
            },
        }
        for store in ("primary", "nightly"):
            with self.subTest(store=store):
                state = self._assert_custody_fault(
                    store, aggregate, "namespace", "store", 1, None
                )
                self.assertEqual(state.vetted_custody_records, ())

    def test_custody_direct_save_refuses_before_any_save_effect(self):
        """Fails if: direct save serializes or creates anything for a faulted state."""
        seed = self.request_seed(42)
        aggregate = seed.aggregate()
        self._leaf(aggregate, seed)["phase"] = "invalid"
        path = self._write_custody("primary", aggregate)
        before = path.read_bytes()
        state = ht.State(path)
        with mock.patch.object(ht, "durable_mkdir") as mkdir, \
                mock.patch.object(ht.json, "dumps") as dumps, \
                mock.patch.object(ht.tempfile, "mkstemp") as temp, \
                mock.patch.object(ht.os, "replace") as replace:
            with self.assertRaises(ht.StateLoadError):
                state.save()
        mkdir.assert_not_called()
        dumps.assert_not_called()
        temp.assert_not_called()
        replace.assert_not_called()
        self.assertEqual(path.read_bytes(), before)

    def test_custody_fresh_tick_reloads_and_refuses_fault(self):
        """Fails if: Runner.tick trusts its earlier in-memory state."""
        runner = self.runner(FakeGitHub([]))
        runner._state_loader = ht.State
        seed = self.request_seed(42)
        aggregate = seed.aggregate()
        self._leaf(aggregate, seed)["phase"] = "invalid"
        self._write_custody("primary", aggregate)
        with mock.patch.object(
            runner, "_tick_locked",
            side_effect=AssertionError("work after custody refusal"),
        ):
            with self.assertRaisesRegex(ht.StateLoadError, "phase"):
                runner.tick()

    def test_custody_fault_projection_and_text_have_exact_metadata(self):
        """Fails if: custody metadata changes legacy fault shapes or text."""
        seed = self.request_seed(42)
        aggregate = seed.aggregate()
        self._leaf(aggregate, seed)["phase"] = "invalid"
        state = self._assert_custody_fault(
            "primary", aggregate, "phase", key=self._key(seed)
        )
        projection = state.load_projection("request")
        self.assertEqual(projection, [{
            "store": "request",
            "kind": "phase",
            "exists": "yes",
            "scope": "record",
            "version": 1,
            "key": self._key(seed),
        }])
        self.assertEqual(
            ht.state_load_text(projection),
            ["state store request: phase (exists yes, scope record, "
             f"version 1, key {json.dumps(self._key(seed), separators=(',', ':'))})"],
        )
        legacy = {"store": "nightly", "kind": "type", "exists": "yes"}
        self.assertEqual(
            ht.state_load_text([legacy]),
            ["state store nightly: type (exists yes)"],
        )

        mixed_path = self._write_custody(
            "primary", {"version": 1, "records": []}, {"jobs": []}
        )
        mixed = ht.State(mixed_path).load_projection("request")
        self.assertEqual(mixed, [
            {"store": "request", "kind": "type", "exists": "yes"},
            {
                "store": "request",
                "kind": "type",
                "exists": "yes",
                "scope": "store",
                "version": 1,
                "key": None,
            },
        ])
        self.assertEqual(ht.state_load_text(mixed), [
            "state store request: type (exists yes)",
            "state store request: type "
            "(exists yes, scope store, version 1, key unknown)",
        ])

    def test_custody_unrelated_save_preserves_seed_and_extras(self):
        """Fails if: a required legacy save drops or reinterprets custody."""
        seed = self.request_seed(42)
        aggregate = seed.aggregate()
        aggregate["opaque"] = {"future": ["kept"]}
        self._leaf(aggregate, seed)["opaque"] = {"record": True}
        path = self._write_custody(
            "primary", aggregate, {"opaque_extension": {"legacy": 1}}
        )
        expected = json.loads(path.read_text())
        state = ht.State(path)
        state.data["history"].append({
            "issue": 42,
            "outcome": "done",
            "detail": "",
            "at": "2026-01-01T00:00:00Z",
        })
        expected["history"] = self._clone(state.data["history"])
        state.save()
        self.assertEqual(path.read_bytes(), self.saved_bytes(expected))
        reopened = ht.State(path)
        self.assertTrue(reopened.writable)
        self.assertEqual(reopened.data["custody"], aggregate)

    def test_custody_missing_tree_does_not_veto_writer_or_probe(self):
        """Fails if: schema validation turns an absent target tree into authority."""
        seed = self.request_seed(42)
        path = self._write_custody("primary", seed.aggregate())
        target = self.paths.worktrees / "42"
        original_exists = Path.exists

        def guarded_exists(candidate):
            if candidate == target:
                raise AssertionError("loader or save probed a custody tree")
            return original_exists(candidate)

        with mock.patch.object(
            Path, "exists", autospec=True, side_effect=guarded_exists,
        ):
            state = ht.State(path)
        self.assertTrue(state.writable)
        self.assertFalse(
            self.paths.worktrees.joinpath("42").exists()
        )
        with mock.patch.object(
            Path, "exists", autospec=True, side_effect=guarded_exists,
        ):
            state.data["opaque_extension"] = {"saved": True}
            state.save()

    def test_custody_status_has_only_existing_fault_channel(self):
        """Fails if: the scoped phase fault misses custody.faults or its text is not printed exactly once, state_loads or existing state-store lines change, file bytes change, or a writer repair occurs."""
        seed = self.request_seed(42)
        aggregate = seed.aggregate()
        self._leaf(aggregate, seed)["phase"] = "invalid"
        primary = self.legacy(custody=aggregate)
        self.write_raw(self.paths.state, primary)
        nightly_path = ht.Paths(
            self.cfg, self.home, "nightly-"
        ).state
        nightly = self.legacy(jobs=[])
        self.write_raw(nightly_path, nightly)
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        boundaries = RecordlessBoundaries(self.home)
        self.assert_pa_custody_loader(
            cfg,
            _PA_INVALID_42_CUSTODY,
            _PA_INVALID_JSON_FIELDS["state_loads"],
        )
        self.assert_pa_locked_status(
            cfg,
            FakeGitHub([]),
            boundaries,
            with_custody_text(
                _PA_INVALID_STATUS_TEXT, _CT_REQUEST_42_PHASE_FAULT
            ),
            _PA_INVALID_JSON_FIELDS,
            _PA_INVALID_JSON_FIELDS["state_loads"],
            _PA_INVALID_JSON_FIELDS["queue"],
            _PA_INVALID_JSON_FIELDS["nightly_queue"],
            _PA_INVALID_JSON_FIELDS["retro_queue"],
            (
                (("open", cfg["request_repo"]),),
                (("open", cfg["request_repo"]),),
            ),
            None,
            {
                ".local/state/hass-triage/state.json":
                    json.dumps(primary).encode(),
                ".local/state/hass-triage/state-nightly.json":
                    json.dumps(nightly).encode(),
                ".local/state/hass-triage/tick.lock": b"4242",
            },
            expected_custody=_PA_INVALID_42_CUSTODY,
            expected_custody_text=_CT_REQUEST_42_PHASE_FAULT,
        )

    def test_custody_retro_presence_refuses_all_retro_effects(self):
        """Fails if: even an empty aggregate in the shared retro store reaches an effect."""
        runner = self.runner(FakeGitHub([]))
        path = runner.retro_paths.state
        self.write_raw(path, self.legacy(queue=[], done=[], custody={}))
        before = path.read_bytes()
        with self.assertRaisesRegex(ht.StateLoadError, "namespace"):
            runner.run_retro()
        self.assertEqual(path.read_bytes(), before)
        state = ht.State(path)
        self.assertEqual(state.load_faults, [{
            "kind": "namespace",
            "exists": "yes",
            "scope": "store",
            "version": None,
            "key": None,
        }])
        self.assertEqual(state.vetted_custody_records, ())
        existing_queue = [{
            "task": "existing",
            "archive": str(self.paths.root / "archive" / "existing"),
        }]
        self.write_raw(
            path,
            self.legacy(queue=existing_queue, done=[], custody={}),
        )
        before = path.read_bytes()
        task = "request-42"
        tree = self.paths.worktree(42)
        digest = tree / "build" / "retro" / f"{task}.json"
        digest.parent.mkdir(parents=True, exist_ok=True)
        digest.write_text(json.dumps({
            "triggers": [{"id": "schema-custody"}],
        }))
        runner.state.record(42, "done", "completed")
        with mock.patch.object(
            runner, "run_retro_digest"
        ), mock.patch.object(
            runner, "run_retro_phase"
        ), mock.patch(
            "sys.stderr", new=io.StringIO()
        ) as err:
            archived = runner.archive_evidence(
                42,
                tree=tree,
                name="request-42",
                task=task,
                include_sidecar=False,
            )
            runner.state.save()
        self.assertEqual(
            archived,
            self.paths.root / "archive" / "request-42",
        )
        self.assertIn("retro enqueue not committed", err.getvalue())
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(ht.State(path).data["queue"], existing_queue)

        with mock.patch.object(
            runner, "readable_base_map", return_value={}
        ), mock.patch.object(
            runner, "refresh_clone"
        ), mock.patch.object(
            runner, "check_base"
        ), mock.patch.object(
            runner, "check_ha_changes"
        ), mock.patch.object(
            runner, "check_merging"
        ), mock.patch.object(
            runner, "check_parked"
        ), mock.patch.object(
            runner, "requeue"
        ), mock.patch.object(
            runner, "recover"
        ), mock.patch.object(
            runner, "check_regressions", return_value=False
        ), mock.patch.object(
            runner, "run_due_job", return_value=None
        ) as job, mock.patch(
            "sys.stderr", new=io.StringIO()
        ) as err:
            self.assertEqual(runner._tick_locked(), 4)
        job.assert_called_once_with()
        self.assertIn("retro state refused", err.getvalue())
        self.assertTrue(self.paths.state.exists())
        self.assertEqual(path.read_bytes(), before)

    def test_custody_faulted_tick_refuses_only_affected_intake(self):
        """Fails if: a faulty intake suppresses its healthy sibling or does work."""
        cases = (
            ("primary", self.request_seed(42), ["tick"], "nightly"),
            (
                "primary", self.request_seed(42),
                ["tick", "--dry-run"], "nightly",
            ),
            ("nightly", self.nightly_seed(), ["tick"], "primary"),
        )
        for store, seed, argv, healthy_store in cases:
            with self.subTest(store=store, argv=argv):
                for path in (
                    self.paths.state,
                    ht.Paths(self.cfg, self.home, "nightly-").state,
                    self.paths.lock,
                ):
                    path.unlink(missing_ok=True)
                aggregate = seed.aggregate()
                self._leaf(aggregate, seed)["phase"] = "invalid"
                bad_path = self._write_custody(store, aggregate)
                bad_bytes = bad_path.read_bytes()
                healthy_data = self.legacy(
                    opaque_extension={"preserve": [healthy_store, 11]}
                )
                healthy_path = self.logical_path(healthy_store)
                self.write_raw(healthy_path, healthy_data)
                base_calls = []
                refresh_calls = []
                saves = []
                original_save = ht.State.save

                def save(state):
                    saves.append(state.path)
                    return original_save(state)

                def label(runner):
                    return "nightly" if runner.intake else "primary"

                with mock.patch.object(
                    ht, "load_config", return_value=self.cfg
                ), mock.patch.object(
                    ht, "GitHub", return_value=FakeGitHub([])
                ), mock.patch.object(
                    ht.os, "getpid", return_value=4242
                ), mock.patch.object(
                    ht.State, "save", autospec=True, side_effect=save
                ), mock.patch.object(
                    ht.Runner, "readable_base_map", autospec=True,
                    side_effect=lambda runner: (
                        base_calls.append(label(runner)) or {}
                    ),
                ), mock.patch.object(
                    ht.Runner, "refresh_clone", autospec=True,
                    side_effect=lambda runner: refresh_calls.append(
                        label(runner)
                    ),
                ), mock.patch.object(
                    ht.Runner, "check_base"
                ), mock.patch.object(
                    ht.Runner, "check_ha_changes"
                ), mock.patch.object(
                    ht.Runner, "check_merging"
                ), mock.patch.object(
                    ht.Runner, "check_parked"
                ), mock.patch.object(
                    ht.Runner, "requeue"
                ), mock.patch.object(
                    ht.Runner, "recover"
                ), mock.patch("sys.stderr", new=io.StringIO()) as err:
                    code = ht.main(
                        [*argv, "--max-items", "0"], home=self.home
                    )
                self.assertEqual(code, 4)
                self.assertEqual(base_calls, [healthy_store])
                self.assertEqual(refresh_calls, [healthy_store])
                self.assertEqual(saves, [healthy_path])
                self.assertIn(
                    f"state store refused: phase for {bad_path.name}",
                    err.getvalue(),
                )
                self.assertEqual(bad_path.read_bytes(), bad_bytes)
                self.assertEqual(healthy_path.read_bytes(),
                                 self.saved_bytes(healthy_data))
                self.assertEqual(self.file_bytes(), {
                    bad_path.relative_to(self.home).as_posix(): bad_bytes,
                    healthy_path.relative_to(
                        self.home
                    ).as_posix(): self.saved_bytes(healthy_data),
                    self.paths.lock.relative_to(
                        self.home
                    ).as_posix(): b"4242",
                })

    def test_custody_command_precedence_and_exemptions_remain_pinned(self):
        """Fails if: malformed custody changes busy, pause, preview or ack precedence."""
        seed = self.request_seed(42)
        aggregate = seed.aggregate()
        self._leaf(aggregate, seed)["phase"] = "invalid"
        self._write_custody("primary", aggregate)
        cfg = dict(self.cfg)
        with ht.writer_lock(self.paths) as admitted:
            self.assertTrue(admitted)
            result, _out, _err = self.main_with(["run-issue", "42"], cfg)
            self.assertEqual(result, 1)
        self.paths.paused.parent.mkdir(parents=True, exist_ok=True)
        self.paths.paused.write_text("paused\n")
        result, out, _err = self.main_with(["run-job", "steward"], cfg)
        self.assertEqual((result, out), (0, "paused\n"))
        self.paths.paused.unlink()
        with mock.patch.object(
            ht.Runner, "refresh_clone",
            side_effect=AssertionError("refresh after custody refusal"),
        ):
            result, _out, _err = self.main_with(["run-issue", "42"], cfg)
        self.assertEqual(result, 4)
        with mock.patch.object(
            ht, "render_prompt", return_value="fixed preview"
        ) as render, mock.patch.object(
            ht.Runner, "refresh_clone",
            side_effect=AssertionError("preview refreshed"),
        ):
            result, out, err = self.main_with(
                ["run-issue", "42", "--dry-run"],
                cfg,
                FakeGitHub([t.issue(42)]),
            )
        self.assertEqual((result, out, err), (0, "fixed preview\n", ""))
        render.assert_called_once()
        verified = {
            "ok": True, "reason": "", "head": "a" * 40, "prs": [1],
        }
        with mock.patch.object(
            ht.Runner, "ack_base", return_value="a" * 40
        ), mock.patch.object(
            ht.Runner, "ack_verified", return_value=verified
        ), mock.patch.dict(os.environ, {}, clear=True), mock.patch(
            "sys.stdin.isatty", return_value=True
        ):
            base, _out, _err = self.main_with(
                ["ack-base", "a" * 40], cfg
            )
            checked, _out, _err = self.main_with(["ack-verified"], cfg)
        self.assertEqual((base, checked), (0, 0))


class AdmissionTests(StoreTestBase):
    def test_tick_preserves_primary_fault_and_still_admits_healthy_nightly(self):
        self.write_raw(self.paths.state, "{")
        calls = []
        cfg = dict(self.cfg)
        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.Runner, "_tick_locked",
                          autospec=True,
                                  side_effect=lambda self, _max: calls.append(
                                      "nightly" if self.intake else "primary") or 0), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            code = ht.main(["tick"], home=self.home)
        self.assertEqual(code, 4)
        self.assertEqual(calls, ["nightly"])
        self.assertIn("state store refused: parse for state.json", err.getvalue())

    def test_nightly_fault_refuses_only_nightly_after_primary_admission(self):
        self.write_raw(ht.Paths(self.cfg, self.home, "nightly-").state, "{")
        calls = []
        with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.Runner, "_tick_locked",
                          autospec=True,
                                  side_effect=lambda self, _max: calls.append(
                                      "nightly" if self.intake else "primary") or 0), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            code = ht.main(["tick"], home=self.home)
        self.assertEqual(code, 4)
        self.assertEqual(calls, ["primary"])
        self.assertIn("state-nightly.json", err.getvalue())

    def test_runner_tick_reloads_and_refuses_under_the_real_writer_lock(self):
        runner = self.runner(FakeGitHub([]))
        runner._state_loader = ht.State
        self.write_raw(self.paths.state, "{")
        with mock.patch.object(ht.Runner, "_tick_locked",
                               side_effect=AssertionError("work after refusal")):
            with self.assertRaisesRegex(ht.StateLoadError, "parse"):
                runner.tick()

    def test_manual_run_commands_refuse_after_busy_and_paused_checks(self):
        self.write_raw(self.paths.state, "{")
        with mock.patch.object(ht.Runner, "refresh_clone",
                               side_effect=AssertionError("refresh after refusal")), \
                mock.patch.object(ht.Runner, "work",
                                  side_effect=AssertionError("work after refusal")):
            result, _out, err = self.main_with(["run-issue", "13"])
        self.assertEqual(result, 4)
        self.assertIn("state store refused: parse", err)

        ht._PRINTED.clear()
        with mock.patch.object(ht.Runner, "run_job",
                               side_effect=AssertionError("job after refusal")):
            result, _out, err = self.main_with(["run-job", "steward"])
        self.assertEqual(result, 4)
        self.assertIn("state store refused: parse", err)

        self.paths.paused.parent.mkdir(parents=True, exist_ok=True)
        self.paths.paused.write_text("paused\n")
        with mock.patch.object(ht, "Runner",
                               side_effect=AssertionError("constructed while paused")):
            result, out, err = self.main_with(["run-job", "steward"])
        self.assertEqual((result, out, err), (0, "paused\n", ""))

    def test_manual_preview_does_not_need_state_write_authority(self):
        self.write_raw(self.paths.state, "{")
        gh = FakeGitHub([t.issue(13)])
        with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh), \
                mock.patch.object(ht, "render_prompt", return_value="fixed preview") as render, \
                mock.patch.object(ht.Runner, "refresh_clone",
                                  side_effect=AssertionError("preview refreshed")), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(
                ht.main(["run-issue", "13", "--dry-run"], home=self.home),
                0,
            )
        self.assertEqual(out.getvalue(), "fixed preview\n")
        render.assert_called_once()
        self.assertEqual(self.paths.state.read_text(), "{")

    def test_acknowledgements_do_not_require_intake_authority(self):
        self.write_raw(self.paths.state, "{")
        verified = {"ok": True, "reason": "", "head": "a" * 40, "prs": [1]}
        with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.Runner, "ack_base", return_value="a" * 40), \
                mock.patch.object(ht.Runner, "ack_verified", return_value=verified), \
                mock.patch.dict(os.environ, {}, clear=True), \
                mock.patch("sys.stdin.isatty", return_value=True), \
                mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(ht.main(["ack-base", "a" * 40], home=self.home), 0)
            self.assertEqual(ht.main(["ack-verified"], home=self.home), 0)


class DurableSaveTests(StoreTestBase):
    def existing_state(self, name: str = "state.json") -> ht.State:
        path = self.paths.state_dir / name
        state = ht.State(path)
        state.data["sentinel"] = "old"
        state.save()
        return ht.State(path)

    def test_save_orders_all_entry_file_replace_and_parent_barriers(self):
        state = ht.State(self.paths.state)
        state.data["sentinel"] = "new"
        opened = {}
        events = []
        real_open, real_fsync, real_replace = os.open, os.fsync, os.replace

        def open_spy(target, flags, *args, **kwargs):
            fd = real_open(target, flags, *args, **kwargs)
            opened[fd] = str(target)
            return fd

        def sync_spy(fd):
            target = opened.get(fd, "")
            events.append("file" if stat.S_ISREG(os.fstat(fd).st_mode) else f"directory:{target}")
            return real_fsync(fd)

        def replace_spy(source, destination):
            events.append("replace")
            return real_replace(source, destination)

        with mock.patch.object(ht.os, "open", side_effect=open_spy), \
                mock.patch.object(ht.os, "fsync", side_effect=sync_spy), \
                mock.patch.object(ht.os, "replace", side_effect=replace_spy):
            state.save()

        self.assertIn("file", events)
        self.assertIn("replace", events)
        self.assertTrue(any(
            event.startswith("directory:") for event in events
        ))
        file_sync = events.index("file")
        replace = events.index("replace")
        parent_event = f"directory:{self.paths.state_dir}"
        self.assertIn(parent_event, events[replace + 1:])
        parent = events.index(parent_event, replace + 1)
        self.assertLess(file_sync, replace)
        self.assertLess(replace, parent)
        self.assertTrue(any(event.startswith("directory:") for event in events[:file_sync]))
        self.assertFalse(any(self.paths.state_dir.glob(f".{self.paths.state.name}.*.tmp")))
        self.assertEqual(stat.S_IMODE(self.paths.state.stat().st_mode), 0o600)

    def test_each_save_stage_preserves_old_bytes_except_post_replace_sync(self):
        stages = ("directory", "temp", "write", "flush", "file_sync", "replace", "parent_sync")
        for stage in stages:
            with self.subTest(stage=stage):
                state = self.existing_state(f"{stage}.json")
                old = state.path.read_bytes()
                state.data["sentinel"] = "new"
                real_fdopen, real_fsync, real_open = os.fdopen, os.fsync, os.open
                opened = {}

                def open_spy(target, flags, *args, **kwargs):
                    fd = real_open(target, flags, *args, **kwargs)
                    opened[fd] = str(target)
                    return fd

                if stage == "directory":
                    context = mock.patch.object(ht, "durable_mkdir", side_effect=OSError("directory"))
                elif stage == "temp":
                    context = mock.patch.object(ht.tempfile, "mkstemp", side_effect=OSError("temp"))
                elif stage in {"write", "flush"}:
                    class FailingHandle:
                        def __init__(self, fd, *args, **kwargs):
                            self.handle = real_fdopen(fd, *args, **kwargs)

                        def __enter__(self):
                            self.handle.__enter__()
                            return self

                        def __exit__(self, *args):
                            return self.handle.__exit__(*args)

                        def write(self, value):
                            if stage == "write":
                                raise OSError("write")
                            return self.handle.write(value)

                        def flush(self):
                            if stage == "flush":
                                raise OSError("flush")
                            return self.handle.flush()

                        def fileno(self):
                            return self.handle.fileno()

                    context = mock.patch.object(ht.os, "fdopen", side_effect=FailingHandle)
                elif stage in {"file_sync", "parent_sync"}:
                    def fail_sync(fd):
                        regular = stat.S_ISREG(os.fstat(fd).st_mode)
                        if (stage == "file_sync" and regular) \
                                or (stage == "parent_sync" and not regular
                                    and opened.get(fd) == str(state.path.parent)):
                            raise OSError(stage)
                        return real_fsync(fd)

                    context = contextlib.ExitStack()
                    context.enter_context(mock.patch.object(
                        ht.os, "open", side_effect=open_spy
                    ))
                    context.enter_context(mock.patch.object(
                        ht.os, "fsync", side_effect=fail_sync
                    ))
                else:
                    context = mock.patch.object(ht.os, "replace", side_effect=OSError("replace"))

                with context, self.assertRaisesRegex(ht.StateSaveError, stage):
                    state.save()
                after = state.path.read_bytes()
                if stage == "parent_sync":
                    self.assertEqual(json.loads(after)["sentinel"], "new")
                else:
                    self.assertEqual(after, old)
                self.assertFalse(any(state.path.parent.glob(f".{state.path.name}.*.tmp")))

    def test_existing_mode_survives_and_failed_ancestor_entry_is_retried(self):
        state = self.existing_state()
        os.chmod(state.path, 0o640)
        state.data["sentinel"] = "mode"
        state.save()
        self.assertEqual(stat.S_IMODE(state.path.stat().st_mode), 0o640)

        before = state.path.read_bytes()
        state.data["sentinel"] = "after"
        real_open, real_fsync = os.open, os.fsync
        opened = {}
        failed = {"value": False}

        def open_spy(target, flags, *args, **kwargs):
            fd = real_open(target, flags, *args, **kwargs)
            opened[fd] = str(target)
            return fd

        def fail_once(fd):
            if not failed["value"] and opened.get(fd) == str(self.paths.state_dir.parent):
                failed["value"] = True
                raise OSError("entry")
            return real_fsync(fd)

        with mock.patch.object(ht.os, "open", side_effect=open_spy), \
                mock.patch.object(ht.os, "fsync", side_effect=fail_once), \
                self.assertRaisesRegex(ht.StateSaveError, "directory"):
            state.save()
        self.assertEqual(state.path.read_bytes(), before)
        state.save()
        self.assertEqual(json.loads(state.path.read_text())["sentinel"], "after")

    def test_quiet_one_and_two_intake_ticks_save_exactly_once_each(self):
        for nightly in (None, self.cfg["nightly"]):
            with self.subTest(two_intakes=nightly is not None):
                cfg = dict(self.cfg)
                cfg["nightly"] = nightly
                events, saves = [], []
                original_save = ht.State.save
                real_open, real_fsync = os.open, os.fsync
                opened = {}
                file_syncs = []
                parent_syncs = []
                ancestor_syncs = []

                def counted(state):
                    saves.append(state.path.name)
                    original_save(state)

                def open_spy(target, flags, *args, **kwargs):
                    fd = real_open(target, flags, *args, **kwargs)
                    opened[fd] = str(target)
                    return fd

                def sync_spy(fd):
                    if stat.S_ISREG(os.fstat(fd).st_mode):
                        file_syncs.append(opened.get(fd))
                    elif opened.get(fd) == str(self.paths.state_dir):
                        parent_syncs.append(opened[fd])
                    else:
                        ancestor_syncs.append(opened.get(fd))
                    return real_fsync(fd)

                patches = self.quiet_tick_patches(events)
                with mock.patch.object(ht, "load_config", return_value=cfg), \
                        mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                        mock.patch.object(ht.State, "save", autospec=True,
                                          side_effect=counted), \
                        mock.patch.object(ht.os, "open", side_effect=open_spy), \
                        mock.patch.object(ht.os, "fsync", side_effect=sync_spy), \
                        patches[0], patches[1], patches[2], patches[3], \
                        patches[4], patches[5], patches[6], patches[7], \
                        mock.patch("sys.stdout", new=io.StringIO()):
                    self.assertEqual(
                        ht.main(["tick", "--max-items", "0"], home=self.home),
                        0,
                    )
                expected = ["state.json", "state-nightly.json"] if nightly else ["state.json"]
                self.assertEqual(saves[-len(expected):], expected)
                self.assertEqual(len(file_syncs), len(expected))
                self.assertEqual(len(parent_syncs), len(expected))
                self.assertEqual(
                    len(ancestor_syncs),
                    6,
                )


class ContainmentTests(StoreTestBase):
    def completed_request(self, retro_path: Path):
        runner = self.runner(FakeGitHub([]))
        log = runner.paths.log(1, 1)
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text("completed\n")
        runner.task_id = mock.Mock(return_value="task-1")
        runner.run_retro_phase = mock.Mock()
        runner.run_retro_digest = mock.Mock()
        dest = runner.paths.root / "archive" / "request-1"
        (dest / "retro").mkdir(parents=True, exist_ok=True)
        (dest / "retro" / "task-1.json").write_text(
            json.dumps({"triggers": [{"id": "sample"}]})
        )

        def completed(_issue):
            runner.state.record(1, "done", "completed")
            runner._ending["log"] = log
            return "done"

        runner._work = completed
        self.write_raw(retro_path, "{")
        with mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(runner.work(1), "done")
        self.assertIn("enqueue not committed", err.getvalue())
        runner.state.save()
        return runner

    def test_completed_request_preserves_outcome_when_retro_load_refuses_enqueue(self):
        runner = self.completed_request(
            ht.Paths(self.cfg, self.home, "retro-").state
        )
        reopened = ht.State(self.paths.state)
        self.assertEqual(reopened.data["history"][-1]["outcome"], "done")

    def test_completed_job_preserves_outcome_and_save_when_retro_load_refuses(self):
        runner = self.runner(
            FakeGitHub([]),
            {"state": "done", "summary": "completed"},
        )
        runner.preflight = mock.Mock(return_value=True)
        self.write_raw(runner.retro_paths.state, "{")

        def digest(_n, dest, attempt=0, task="", **_kwargs):
            (dest / "retro").mkdir(parents=True, exist_ok=True)
            (dest / "retro" / f"{task}.json").write_text(
                json.dumps({"triggers": [{"id": "sample"}]})
            )

        runner.run_retro_digest = mock.Mock(side_effect=digest)
        runner.run_retro_phase = mock.Mock()
        runner.archive_evidence = mock.Mock(
            wraps=lambda *args, **kwargs: runner.__class__.archive_evidence(
                runner, *args, **kwargs
            )
        )
        with mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(runner.run_job("researcher"), "done")
        self.assertIn("enqueue not committed", err.getvalue())
        reopened = ht.State(self.paths.state)
        self.assertEqual(reopened.data["jobs"]["researcher"]["outcome"], "done")

    def test_enqueue_save_failure_reports_commit_uncertainty_without_losing_archive(self):
        runner = self.runner(FakeGitHub([]))
        retro_path = ht.Paths(self.cfg, self.home, "retro-").state
        self.write_raw(retro_path, self.legacy(queue=[]))
        dest = runner.paths.root / "archive" / "request-1"
        (dest / "retro").mkdir(parents=True, exist_ok=True)
        (dest / "retro" / "task-1.json").write_text(
            json.dumps({"triggers": [{"id": "sample"}]})
        )
        log = dest / "worker.log"
        log.write_text("done\n")
        with mock.patch.object(runner, "run_retro_digest"), \
                mock.patch.object(runner, "run_retro_phase"), \
                mock.patch.object(ht.State, "save", autospec=True,
                                  side_effect=ht.StateSaveError(
                                      retro_path.name, "parent_sync"
                                  )), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            result = runner.archive_evidence(
                1, log=log, name="request-1", task="task-1"
            )
        self.assertEqual(result, dest)
        self.assertIn("retro enqueue unconfirmed", err.getvalue())
        self.assertTrue((dest / "worker.log.tail").exists())

    def test_retro_load_refusal_continues_independent_primary_final_save_and_job(self):
        runner = self.runner(FakeGitHub([]))
        self.write_raw(runner.retro_paths.state, "{")
        with mock.patch.object(runner, "readable_base_map", return_value={}), \
                mock.patch.object(runner, "refresh_clone"), \
                mock.patch.object(runner, "check_base"), \
                mock.patch.object(runner, "check_ha_changes"), \
                mock.patch.object(runner, "check_merging"), \
                mock.patch.object(runner, "check_parked"), \
                mock.patch.object(runner, "requeue"), \
                mock.patch.object(runner, "recover"), \
                mock.patch.object(runner, "check_regressions", return_value=False), \
                mock.patch.object(runner, "run_due_job", return_value=None) as job, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(runner._tick_locked(), 4)
        job.assert_called_once_with()
        self.assertIn("retro state refused", err.getvalue())
        self.assertTrue(self.paths.state.exists())

    def test_retro_prelaunch_save_failure_stops_tick_without_primary_save(self):
        runner = self.runner(FakeGitHub([]))
        queue = [{"task": "sample", "archive": str(self.home / "archive")}]
        self.write_raw(runner.retro_paths.state, self.legacy(queue=queue, done=[]))
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        original_save = ht.State.save

        def fail_retro(state):
            if state.path == runner.retro_paths.state:
                raise ht.StateSaveError(state.path.name, "file_sync")
            return original_save(state)

        with mock.patch.object(runner, "readable_base_map", return_value={}), \
                mock.patch.object(runner, "refresh_clone"), \
                mock.patch.object(runner, "check_base"), \
                mock.patch.object(runner, "check_ha_changes"), \
                mock.patch.object(runner, "check_merging"), \
                mock.patch.object(runner, "check_parked"), \
                mock.patch.object(runner, "requeue"), \
                mock.patch.object(runner, "recover"), \
                mock.patch.object(runner, "preflight", return_value=True), \
                mock.patch.object(runner, "run_due_job",
                                  side_effect=AssertionError("job after retro save failure")), \
                mock.patch.object(
                    runner, "_run",
                    side_effect=lambda *args, **kwargs: subprocess.CompletedProcess(
                        args, 0, "", ""
                    )
                ), \
                mock.patch.object(ht.State, "save", autospec=True,
                                  side_effect=fail_retro), \
                mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht, "Runner", return_value=runner), \
                mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(ht.main(["tick"], home=self.home), 4)
        self.assertEqual(out.getvalue(), "")
        self.assertIn("state persistence failed during file_sync", err.getvalue())
        self.assertFalse(self.paths.state.exists())
        self.assertEqual(json.loads(runner.retro_paths.state.read_text())["queue"], queue)

    def test_job_final_save_failure_is_not_reported_as_a_normal_result(self):
        runner = self.runner(
            FakeGitHub([]),
            {"state": "done", "summary": "completed"},
        )
        runner.preflight = mock.Mock(return_value=True)
        original_save = ht.State.save
        primary_saves = 0

        def fail_final(state):
            nonlocal primary_saves
            if state.path == self.paths.state:
                primary_saves += 1
                if primary_saves == 2:
                    raise ht.StateSaveError(state.path.name, "parent_sync")
            return original_save(state)

        with mock.patch.object(ht.State, "save", autospec=True,
                               side_effect=fail_final):
            with self.assertRaisesRegex(ht.StateSaveError, "parent_sync"):
                runner.run_job("steward")
        self.assertEqual(primary_saves, 2)

    def assert_reviewer_save_failure_propagates_through_job(
            self, callback: bool, seed=None) -> None:
        lane = "agents/researcher-reviewer-save"
        if seed is not None:
            self.write_raw(
                self.paths.state,
                seeded_expected(self.legacy(), seed),
            )
        runner = self.runner(
            FakeGitHub([]),
            {
                "state": "done",
                "summary": "completed",
                "lanes": [lane],
            },
        )
        runner.preflight = mock.Mock(return_value=True)
        runner.refresh_clone = mock.Mock()
        runner.readable_base_map = mock.Mock(return_value={})
        runner.check_base = mock.Mock(return_value=True)
        runner.lane_refs = mock.Mock(return_value={lane: "c" * 40})
        runner.snapshot_lanes = mock.Mock(
            side_effect=lambda label: runner.lane_snapshots.__setitem__(
                str(label), {}
            )
        )
        trusted = self.home / "trusted"
        trusted.mkdir()
        runner.trusted_clone = mock.Mock(return_value=trusted)
        diff = self.home / "review.diff"
        diff.write_text("fixture diff\n")
        worker_launch = runner.launch
        process = mock.Mock(pid=987654, stdin=mock.Mock(), stdout=None)
        reap = ht.lane_land.reap_group
        reap.reset_mock()

        class Launcher:
            def __init__(self, *_args, **_kwargs):
                pass

            def launch(self, **kwargs):
                try:
                    kwargs["on_thread"]("thread-1")
                except ht.StateSaveError:
                    return ht.t3launch.Outcome(1, "thread-1", False, True)

        def launch(label, worktree, prompt, log):
            if runner.agent_override != "reviewer":
                return worker_launch(label, worktree, prompt, log)
            if callback:
                return runner._t3_launch(label, worktree, prompt, log)
            return runner._launch(label, worktree, prompt, log)

        runner.launch = launch
        archive_ready = mock.Mock(return_value=True)
        archive_evidence = mock.Mock()
        runner.archive_before_change = archive_ready
        runner.archive_evidence = archive_evidence
        original_save = ht.State.save
        primary_saves = 0

        def fail_reviewer_save(state):
            nonlocal primary_saves
            if state.path == self.paths.state:
                primary_saves += 1
                if primary_saves == 2:
                    raise ht.StateSaveError(state.path.name, "file_sync")
            return original_save(state)

        def land_lane(_lane, base, *_args, **_kwargs):
            runner.review_lane(lane, "c" * 40, base, diff)
            return "merged"

        runner.land_lane = mock.Mock(side_effect=land_lane)

        with mock.patch.object(ht, "load_config", return_value=self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=runner.gh), \
                mock.patch.object(ht, "Runner", return_value=runner), \
                mock.patch.object(ht.State, "save", autospec=True,
                                  side_effect=fail_reviewer_save), \
                mock.patch.object(ht.subprocess, "Popen",
                                  return_value=process), \
                mock.patch.object(ht.t3launch, "Launcher", Launcher), \
                mock.patch.object(ht.shutil, "which", return_value=None), \
                mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(
                ht.main(["run-job", "researcher"], home=self.home), 4
            )

        self.assertEqual(primary_saves, 2)
        self.assertEqual(out.getvalue(), "")
        self.assertIn("state persistence failed during file_sync", err.getvalue())
        archive_ready.assert_not_called()
        archive_evidence.assert_not_called()
        disk = ht.State(self.paths.state).data
        self.assertEqual(disk["history"], [])
        self.assertEqual(disk["current"]["job"], "researcher")
        if seed is not None:
            self.assertEqual(disk["custody"], seed.aggregate())
        if callback:
            self.assertIn("cleanup", err.getvalue())
        else:
            process.stdin.close.assert_called_once_with()
            reap.assert_called_once_with(987654)
            self.assertIn(
                "launched process cleanup confirmed after",
                err.getvalue(),
            )

    def test_classic_reviewer_save_failure_is_not_a_job_lane_error(self):
        """Fails if: the classic reviewer hides persistence failure or fails to contain its exact fake pid."""
        self.assert_reviewer_save_failure_propagates_through_job(False)

    def test_callback_reviewer_save_failure_is_not_a_job_lane_error(self):
        """Fails if: the T3 callback turns reviewer persistence failure into a normal lane result."""
        self.assert_reviewer_save_failure_propagates_through_job(True)

    def test_seeded_classic_reviewer_save_failure_preserves_custody(self):
        """Fails if: a staged valid job seed changes classic reviewer containment or failure propagation."""
        self.assert_reviewer_save_failure_propagates_through_job(
            False, self.custody_fixture("classic reviewer")
        )

    def test_seeded_callback_reviewer_save_failure_preserves_custody(self):
        """Fails if: a staged valid job seed changes worker callback containment or error propagation."""
        self.assert_reviewer_save_failure_propagates_through_job(
            True, self.custody_fixture("worker reviewer callback")
        )

    def test_t3_reviewer_override_dispatches_to_the_classic_launcher(self):
        """Fails if: a T3-configured reviewer is sent through the worker callback launcher."""
        cfg = dict(self.cfg)
        cfg["agent"] = dict(cfg["agent"])
        cfg["agent"]["launcher"] = "t3code"
        runner = ht.Runner(cfg, self.paths, FakeGitHub([]))
        runner.agent_override = "reviewer"
        process = mock.Mock(pid=54321, stdin=mock.Mock(), stdout=None)
        with mock.patch.object(
            ht.t3launch, "settings_agree", return_value=True
        ) as agree, mock.patch.object(
            runner, "_t3_launch",
            side_effect=AssertionError("reviewer entered worker launcher"),
        ) as callback, mock.patch.object(
            ht.subprocess, "Popen", return_value=process
        ) as popen, mock.patch.object(
            runner, "_wait_group", return_value=(0, True)
        ) as wait, mock.patch.object(
            ht.shutil, "which", return_value=None
        ):
            self.assertEqual(
                runner.launch(
                    "job-researcher",
                    self.home / "tree",
                    "review prompt",
                    self.home / "review.log",
                ),
                0,
            )
        agree.assert_not_called()
        callback.assert_not_called()
        popen.assert_called_once()
        process.stdin.write.assert_called_once_with(b"review prompt")
        process.stdin.close.assert_called_once_with()
        wait.assert_called_once_with(process, 18000.0)
        ht.lane_land.reap_group.assert_not_called()

    def assert_retro_final_save_failure_preserves_primary_authority(self, ready):
        runner = self.runner(
            FakeGitHub([]),
            {"state": "done", "summary": "completed"},
        )
        self.write_raw(
            runner.retro_paths.state,
            self.legacy(
                queue=[{"task": "sample", "archive": str(self.home / "archive")}],
                done=[],
            ),
        )
        original_save = ht.State.save
        retro_saves = 0
        primary_saves = 0
        cfg = dict(self.cfg)
        cfg["nightly"] = None

        def fail_final(state):
            nonlocal primary_saves, retro_saves
            if state.path == runner.retro_paths.state:
                retro_saves += 1
                if retro_saves == 2:
                    raise ht.StateSaveError(state.path.name, "file_sync")
            elif state.path == self.paths.state:
                primary_saves += 1
            return original_save(state)

        with mock.patch.object(runner, "readable_base_map", return_value={}), \
                mock.patch.object(runner, "refresh_clone"), \
                mock.patch.object(runner, "check_base"), \
                mock.patch.object(runner, "check_ha_changes"), \
                mock.patch.object(runner, "check_merging"), \
                mock.patch.object(runner, "check_parked"), \
                mock.patch.object(runner, "requeue"), \
                mock.patch.object(runner, "recover"), \
                mock.patch.object(runner, "preflight", return_value=True), \
                mock.patch.object(runner, "check_regressions",
                                  side_effect=AssertionError("after retro failure")), \
                mock.patch.object(runner, "run_due_job",
                                  side_effect=AssertionError("after retro failure")), \
                mock.patch.object(runner, "archive_before_change",
                                  return_value=ready) as archive_ready, \
                mock.patch.object(runner, "archive_evidence"), \
                mock.patch.object(
                    runner, "_run",
                    side_effect=lambda *args, **kwargs: subprocess.CompletedProcess(
                        args, 0, "", ""
                    ),
                ), \
                mock.patch.object(ht.State, "save", autospec=True,
                                  side_effect=fail_final), \
                mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht, "Runner", return_value=runner), \
                mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertEqual(ht.main(["tick"], home=self.home), 4)
        self.assertEqual(retro_saves, 2)
        self.assertEqual(primary_saves, 1)
        archive_ready.assert_called_once()
        self.assertEqual(out.getvalue(), "")
        self.assertIn("state persistence failed during file_sync", err.getvalue())
        primary = ht.State(self.paths.state).data
        self.assertEqual(primary["history"], [])
        self.assertEqual(primary["current"]["job"], "retro-sample")
        reopened_retro = ht.State(runner.retro_paths.state).data
        self.assertEqual(reopened_retro["queue"], [])
        self.assertEqual(reopened_retro["current"]["task"], "sample")

    def test_retro_done_save_failure_preserves_primary_authority(self):
        self.assert_retro_final_save_failure_preserves_primary_authority(True)

    def test_retro_held_queue_save_failure_preserves_primary_authority(self):
        self.assert_retro_final_save_failure_preserves_primary_authority(False)

    def test_primary_save_after_retro_finalizer_is_not_contained_as_retro_error(self):
        runner = self.runner(
            FakeGitHub([]),
            {"state": "done", "summary": "completed"},
        )
        self.write_raw(
            runner.retro_paths.state,
            self.legacy(
                queue=[{"task": "sample", "archive": str(self.home / "archive")}],
                done=[],
            ),
        )
        original_save = ht.State.save
        primary_saves = 0

        def fail_primary(state):
            nonlocal primary_saves
            if state.path == self.paths.state:
                primary_saves += 1
                if primary_saves == 2:
                    raise ht.StateSaveError(state.path.name, "file_sync")
            return original_save(state)

        with mock.patch.object(runner, "readable_base_map", return_value={}), \
                mock.patch.object(runner, "refresh_clone"), \
                mock.patch.object(runner, "check_base"), \
                mock.patch.object(runner, "check_ha_changes"), \
                mock.patch.object(runner, "check_merging"), \
                mock.patch.object(runner, "check_parked"), \
                mock.patch.object(runner, "requeue"), \
                mock.patch.object(runner, "recover"), \
                mock.patch.object(runner, "preflight", return_value=True), \
                mock.patch.object(
                    runner, "_run",
                    side_effect=lambda *args, **kwargs: subprocess.CompletedProcess(
                        args, 0, "", ""
                    ),
                ), \
                mock.patch.object(ht.State, "save", autospec=True,
                                  side_effect=fail_primary):
            with self.assertRaisesRegex(ht.StateSaveError, "file_sync"):
                runner._tick_locked()
        self.assertEqual(primary_saves, 2)

    def test_classic_launcher_reports_cleanup_before_propagating_save_failure(self):
        runner = self.runner(FakeGitHub([]))
        runner.state.data["current"] = {}
        process = mock.Mock(pid=987654, stdin=mock.Mock(), stdout=None)
        with mock.patch.object(ht.subprocess, "Popen", return_value=process), \
                mock.patch.object(runner.state, "save",
                                  side_effect=ht.StateSaveError("state.json", "file_sync")), \
                mock.patch.object(ht.lane_land, "reap_group", return_value=True) as reap, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            with self.assertRaises(ht.StateSaveError):
                runner._launch(1, self.home / "tree", "prompt", self.home / "log")
        process.stdin.close.assert_called_once_with()
        reap.assert_called_once_with(987654)
        self.assertIn("cleanup confirmed", err.getvalue())

    def test_t3_callback_reports_cleanup_before_propagating_save_failure(self):
        runner = self.runner(FakeGitHub([]))
        runner.state.data["current"] = {}

        class Launcher:
            def __init__(self, *_args, **_kwargs):
                pass

            def launch(self, **kwargs):
                try:
                    kwargs["on_thread"]("thread-1")
                except ht.StateSaveError:
                    return ht.t3launch.Outcome(1, "thread-1", False, True)

        with mock.patch.object(ht.t3launch, "Launcher", Launcher), \
                mock.patch.object(runner.state, "save",
                                  side_effect=ht.StateSaveError("state.json", "parent_sync")), \
                mock.patch.object(runner, "trusted_clone", return_value=self.paths.clone), \
                mock.patch.object(ht.shutil, "which", return_value=None), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            with self.assertRaises(ht.StateSaveError):
                runner._t3_launch(
                    "job-sample", self.home / "tree", "prompt", self.home / "log"
                )
        self.assertIn("cleanup confirmed", err.getvalue())

    def test_wrapped_t3_callback_save_failure_is_not_a_normal_lane_error(self):
        runner = self.runner(FakeGitHub([]))
        runner.state.data["current"] = {}

        class Launcher:
            def __init__(self, *_args, **_kwargs):
                pass

            def launch(self, **kwargs):
                try:
                    kwargs["on_thread"]("thread-1")
                except ht.StateSaveError:
                    raise RuntimeError("launcher wrapped callback failure")

        with mock.patch.object(ht.t3launch, "Launcher", Launcher), \
                mock.patch.object(runner.state, "save",
                                  side_effect=ht.StateSaveError("state.json", "file_sync")), \
                mock.patch.object(runner, "trusted_clone", return_value=self.paths.clone), \
                mock.patch.object(ht.shutil, "which", return_value=None), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            with self.assertRaisesRegex(ht.StateSaveError, "file_sync"):
                runner._t3_launch(
                    "job-sample", self.home / "tree", "prompt", self.home / "log"
                )
        self.assertIn("cleanup unconfirmed", err.getvalue())


class StatusAndGoldenTests(StoreTestBase):
    def run_status(self, args, cfg=None, gh=None):
        with mock.patch.object(ht, "load_config", return_value=cfg or self.cfg), \
                mock.patch.object(ht, "GitHub", return_value=gh or FakeGitHub([])), \
                mock.patch.object(ht, "claude_logged_in", return_value=None), \
                mock.patch.object(ht.t3launch, "ready", return_value=(None, "")), \
                mock.patch.object(ht, "writer_lock",
                                  side_effect=AssertionError("status acquired writer lock")), \
                mock.patch.object(ht.State, "save",
                                  side_effect=AssertionError("status saved state")), \
                mock.patch.object(ht, "durable_mkdir",
                                  side_effect=AssertionError("status created a directory")), \
                mock.patch("sys.stdout", new=io.StringIO()) as out:
            code = ht.main(args, home=self.home)
        self.assertEqual(code, 0)
        return out.getvalue()

    def test_status_faults_are_read_only_bounded_and_match_both_formats(self):
        self.write_raw(self.paths.state, self.legacy(
            current=[],
            jobs={"steward": {"last_run": 42}},
        ))
        nightly = ht.Paths(self.cfg, self.home, "nightly-").state
        self.write_raw(nightly, "{")
        retro = ht.Paths(self.cfg, self.home, "retro-").state
        self.write_raw(retro, self.legacy(queue={"not": "a list"}))
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        with ht.writer_lock(self.paths) as admitted:
            self.assertTrue(admitted)
            before = {
                str(path.relative_to(self.home)): path.read_bytes()
                for path in self.home.rglob("*") if path.is_file()
            }
            text = self.run_status(["status"], cfg=cfg)
            encoded = self.run_status(["status", "--json"], cfg=cfg)
        report = json.loads(encoded)
        self.assertIn("state store request: type (exists yes)", text)
        self.assertIn("state store nightly: parse (exists yes)", text)
        self.assertEqual(
            {(item["store"], item["kind"], item["exists"])
             for item in report["state_loads"]},
            {
                ("request", "type", "yes"),
                ("nightly", "parse", "yes"),
                ("retro", "type", "yes"),
            },
        )
        self.assertIsNone(report["jobs"]["steward"]["last_run"])
        self.assertEqual(report["jobs"]["steward"]["next_due"], "unknown")
        self.assertEqual(report["retro_queue"], [])
        self.assertEqual(
            {str(path.relative_to(self.home)): path.read_bytes()
             for path in self.home.rglob("*") if path.is_file()},
            before,
        )

    def test_status_does_not_refuse_on_missing_optional_and_reports_primary_missing(self):
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        encoded = self.run_status(["status", "--json"], cfg=cfg)
        report = json.loads(encoded)
        self.assertEqual(report["state_loads"], [{
            "store": "request",
            "kind": "not_found",
            "exists": "no",
            "installation": "unknown",
        }])

    def test_recordless_quiet_tick_has_fixed_ordered_transcript_and_opaque_bytes(self):
        """Fails if: quiet tick ordering, the one save or its complete state bytes change."""
        events = []
        expected = self.legacy(
            opaque_extension={"preserve": ["exact", 1]}
        )
        self.write_raw(self.paths.state, expected)
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        patches = self.quiet_tick_patches(events)
        original_save = ht.State.save

        def save(state):
            events.append("save")
            original_save(state)

        with mock.patch.object(ht, "load_config", return_value=cfg), \
                mock.patch.object(ht, "GitHub", return_value=FakeGitHub([])), \
                mock.patch.object(ht.State, "save", autospec=True, side_effect=save), \
                patches[0], patches[1], patches[2], patches[3], \
                patches[4], patches[5], patches[6], patches[7], \
                mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            code = ht.main(["tick", "--max-items", "0"], home=self.home)
        self.assertEqual((code, out.getvalue(), err.getvalue()), (0, "", ""))
        self.assertEqual(events, [
            "base-map", "refresh", "base", "ha", "merging", "parked",
            "requeue", "recover", "save",
        ])
        reopened = json.loads(self.paths.state.read_text())
        self.assertEqual(reopened["opaque_extension"], {"preserve": ["exact", 1]})
        self.assertEqual(
            self.paths.state.read_bytes(),
            self.saved_bytes(expected),
        )

    def test_recordless_both_admissions_choose_priority_and_keep_fixed_bytes(self):
        """Fails if: dry priority, admission ordering or any complete intake byte changes."""
        self.maxDiff = None
        request_old = t.issue(
            41, created="2026-10-12T00:00:00Z"
        )
        request_priority = t.issue(
            42, labels=["Priority"], created="2026-10-13T00:00:00Z"
        )
        nightly_old = t.issue(
            51,
            labels=["Nightly Fix"],
            author="github-actions",
            created="2026-10-12T00:00:00Z",
        )
        nightly_priority = t.issue(
            52,
            labels=["Nightly Fix", "Priority"],
            author="github-actions",
            created="2026-10-13T00:00:00Z",
        )
        gh = RecordlessTraceGitHub({
            self.cfg["request_repo"]: [request_old, request_priority],
            self.cfg["nightly"]["repo"]: [nightly_old, nightly_priority],
        })
        primary_data = self.legacy(
            opaque_extension={"preserve": ["request", 1]}
        )
        nightly_data = self.legacy(
            opaque_extension={"preserve": ["nightly", 2]}
        )
        self.write_raw(self.paths.state, primary_data)
        nightly_path = ht.Paths(self.cfg, self.home, "nightly-").state
        self.write_raw(nightly_path, nightly_data)
        boundaries = RecordlessBoundaries(self.home)

        result = self.main_golden(
            ["tick", "--dry-run", "--max-items", "2"], self.cfg, gh, boundaries
        )

        self.assertEqual(
            result,
            (
                0,
                "[dry-run] would work #42: [Bug] Thing 42\n"
                "[dry-run] queued #41: [Bug] Thing 41\n"
                "[dry-run] would work #52: [Bug] Thing 52\n"
                "[dry-run] queued #51: [Bug] Thing 51\n",
                "",
            ),
        )
        self.assertEqual(gh.events, [
            ("open", self.cfg["request_repo"]),
            ("open", self.cfg["request_repo"]),
            ("open", self.cfg["request_repo"]),
            ("open", self.cfg["nightly"]["repo"]),
            ("open", self.cfg["nightly"]["repo"]),
            ("open", self.cfg["nightly"]["repo"]),
        ])
        clone = str(self.paths.clone)
        self.assertEqual(boundaries.git_events, [
            (("gh", "repo", "clone", self.cfg["product_repo"], clone), ""),
            (("git", "-C", clone, "fetch", "-q", "origin",
              self.cfg["product_base"]), ""),
            (("git", "-C", clone, "fetch", "-q", "origin",
              self.cfg["product_base"]), ""),
        ])
        self.assertEqual(boundaries.launch_events, [])
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/state-nightly.json": self.saved_bytes(nightly_data),
            ".local/state/hass-triage/state.json": self.saved_bytes(primary_data),
            ".local/state/hass-triage/tick.lock": b"4242",
        })
        self.assertEqual(boundaries.forget_events, [])

    def test_recordless_idle_primary_reads_nightly_queue_before_job_work(self):
        """Fails if: the drained intake order, nightly idle callback or bytes change."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        primary = self.legacy(opaque_extension={"preserve": ["idle", 1]})
        nightly = self.legacy(opaque_extension={"preserve": ["idle", 2]})
        self.write_raw(self.paths.state, primary)
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        self.write_raw(nightly_path, nightly)
        gh = RecordlessTraceGitHub({
            cfg["request_repo"]: [],
            cfg["nightly"]["repo"]: [],
        })
        boundaries = RecordlessBoundaries(self.home)

        self.assertEqual(
            self.main_golden(["tick"], cfg, gh, boundaries),
            (0, "", ""),
        )
        self.assertEqual(gh.events, [
            ("open", cfg["request_repo"]),
            ("open", cfg["request_repo"]),
            ("open", cfg["request_repo"]),
            ("open", cfg["nightly"]["repo"]),
            ("open", cfg["nightly"]["repo"]),
            ("open", cfg["nightly"]["repo"]),
            ("open", cfg["nightly"]["repo"]),
        ])
        clone = str(self.paths.clone)
        self.assertEqual(boundaries.git_events, [
            (("gh", "repo", "clone", cfg["product_repo"], clone), ""),
            (("git", "-C", clone, "fetch", "-q", "origin",
              cfg["product_base"]), ""),
            (("git", "-C", clone, "checkout", "-q", "--detach",
              f"origin/{cfg['product_base']}"), ""),
            (("git", "-C", clone, "worktree", "prune"), ""),
            (str(self.paths.clone), ("ls-remote", "origin",
                                     f"refs/heads/{cfg['product_base']}")),
            (("git", "-C", clone, "fetch", "-q", "origin",
              cfg["product_base"]), ""),
            (("git", "-C", clone, "checkout", "-q", "--detach",
              f"origin/{cfg['product_base']}"), ""),
            (("git", "-C", clone, "worktree", "prune"), ""),
            (str(self.paths.clone), ("ls-remote", "origin",
                                     f"refs/heads/{cfg['product_base']}")),
        ])
        self.assertEqual(boundaries.launch_events, [])
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/state-nightly.json":
                self.saved_bytes(nightly),
            ".local/state/hass-triage/state.json": self.saved_bytes(primary),
            ".local/state/hass-triage/tick.lock": b"4242",
        })
        self.assertEqual(boundaries.forget_events, [])

    def test_recordless_tick_self_change_pause_stops_retro_dispatch(self):
        """Fails if: the moved-base stop, pause audit or suppressed retro dispatch changes."""
        old = "a" * 40
        head = "b" * 40
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        cfg["workflow_base"] = "workflow"
        primary = self.legacy(opaque_extension={"preserve": ["self-change", 2]})
        retro = self.legacy(
            queue=[{"task": "held-retro", "archive": str(self.home / "archive")}],
            done=[],
        )
        self.write_raw(self.paths.state, primary)
        self.write_raw(ht.Paths(cfg, self.home, "retro-").state, retro)
        base = self.paths.state_dir / "workflow-base.json"
        base.parent.mkdir(parents=True, exist_ok=True)
        base.write_text(json.dumps({"workflow": old}, indent=2, sort_keys=True))
        land = self.paths.root / "land" / cfg["product_repo"].split("/")[-1]
        (land / ".git").mkdir(parents=True)
        gh = RecordlessTraceGitHub({cfg["request_repo"]: []})

        class SelfChangeBoundaries(RecordlessBoundaries):
            def land_git(self, repo, *args, **kwargs):
                proc = super().land_git(repo, *args, **kwargs)
                if tuple(str(arg) for arg in args) == (
                    "ls-remote", "origin", "refs/heads/workflow"
                ):
                    proc.stdout = f"{head}\trefs/heads/workflow\n"
                return proc

        boundaries = SelfChangeBoundaries(self.home)
        reason = (
            f"origin/workflow is {head}, but the runner last landed or saw "
            f"{old} (noticed at tick, 2026-11-23T12:00:00Z). "
            "Self-change landings are paused. Accept with "
            "`python3 tools/triage/hass_triage.py ack-verified` when every "
            "move is a checked PR merge; for anything else the owner runs "
            "`ack-base <sha>` from a terminal. Owner only: after checking "
            "the change, accept it from an interactive shell with "
            f"`python3 tools/triage/hass_triage.py ack-base {head}` "
            "(agents never run this)."
        )

        result = self.main_golden(["tick"], cfg, gh, boundaries)

        self.assertEqual(result, (
            0,
            f"base integrity: {reason}\n"
            "retro: paused (PAUSED file); queued post-mortems wait\n",
            "",
        ))
        title = f"Workflow: workflow moved without the runner ({head[:10]})"
        self.assertEqual(gh.events, [
            ("open", cfg["request_repo"]),
            ("issue_create", cfg["request_repo"], title,
             f"{reason}\n\n```\n\n\n\n```", ("Workflow", "On Hold")),
            ("open", cfg["request_repo"]),
            ("open", cfg["request_repo"]),
            ("open", cfg["request_repo"]),
        ])
        clone = str(self.paths.clone)
        self.assertEqual(boundaries.git_events, [
            (("gh", "repo", "clone", cfg["product_repo"], clone), ""),
            (("git", "-C", clone, "fetch", "-q", "origin",
              cfg["product_base"]), ""),
            (("git", "-C", clone, "checkout", "-q", "--detach",
              f"origin/{cfg['product_base']}"), ""),
            (("git", "-C", clone, "worktree", "prune"), ""),
            (str(land), ("ls-remote", "origin", "refs/heads/workflow")),
            (str(land), ("fetch", "-q", "origin",
                         "+refs/heads/workflow:refs/remotes/origin/workflow")),
            (str(land), ("log", "-1", "--format=author: %an <%ae>%n"
                         "committer: %cn <%ce>%nsubject: %s", head)),
            (str(land), ("diff", "--stat", f"{old}..{head}")),
        ])
        self.assertEqual(boundaries.launch_events, [])
        pause_info = {
            "base": "workflow",
            "sha": head,
            "expected": old,
            "when": "tick",
            "at": "2026-11-23T12:00:00Z",
            "latest": head,
            "moves": [],
        }
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/SELF_CHANGE_PAUSED":
                f"{reason}\n".encode(),
            ".local/state/hass-triage/SELF_CHANGE_PAUSED.json":
                self.saved_bytes(pause_info),
            ".local/state/hass-triage/state-retro.json":
                json.dumps(retro).encode(),
            ".local/state/hass-triage/state.json":
                self.saved_bytes(primary),
            ".local/state/hass-triage/tick.lock": b"4242",
            ".local/state/hass-triage/workflow-base.json":
                json.dumps({"workflow": old}, indent=2, sort_keys=True).encode(),
        })
        self.assertEqual(boundaries.forget_events, [])

    def test_recordless_acknowledgements_ignore_bad_primary_and_keep_base_history(self):
        old = "a" * 40
        head = "b" * 40
        cfg = dict(self.cfg)
        cfg["workflow_base"] = cfg["product_base"]
        cfg["nightly"] = None
        self.write_raw(self.paths.state, "{")
        base = self.paths.state_dir / "workflow-base.json"
        pause = self.paths.state_dir / "SELF_CHANGE_PAUSED"
        pause_info = self.paths.state_dir / "SELF_CHANGE_PAUSED.json"
        gh = RecordlessAckGitHub(
            {cfg["request_repo"]: []}, old, head
        )
        boundaries = RecordlessAckBoundaries(self.home, old, head)
        land = self.paths.root / "land" / cfg["product_repo"].split("/")[-1]
        (land / ".git").mkdir(parents=True)

        def seed_pause():
            base.parent.mkdir(parents=True, exist_ok=True)
            base.write_text(json.dumps({"main": old}, indent=2, sort_keys=True))
            pause.write_text("unexpected workflow base move\n")
            pause_info.write_text(json.dumps({
                "base": "main",
                "sha": head,
                "expected": old,
                "moves": [],
                "when": "tick",
                "at": "2026-11-23T12:00:00Z",
            }))

        seed_pause()
        accepted = self.main_golden(
            ["ack-base", head], cfg, gh, boundaries
        )
        self.assertEqual(accepted, (
            0,
            "Accepted bbbbbbbbbb as the workflow base; SELF_CHANGE_PAUSED cleared.\n",
            "",
        ))

        seed_pause()
        verified = self.main_golden(
            ["ack-verified"], cfg, gh, boundaries
        )
        self.assertEqual(verified, (
            0,
            "Accepted 1 PR merges: #17; head bbbbbbbbbb; "
            "SELF_CHANGE_PAUSED cleared.\n",
            "",
        ))
        self.assertEqual(gh.events, [
            ("requirements", cfg["product_repo"], "main"),
            ("commit_record", cfg["product_repo"], head),
            ("commit_pulls", cfg["product_repo"], head),
            ("checks", cfg["product_repo"], head),
        ])
        self.assertEqual(boundaries.git_events, [
            (str(land), ("ls-remote", "origin", "refs/heads/main")),
            (str(land), ("ls-remote", "origin", "refs/heads/main")),
            (str(land), ("fetch", "-q", "origin",
                         "+refs/heads/main:refs/remotes/origin/main")),
            (str(land), ("merge-base", "--is-ancestor", old, head)),
            (str(land), ("rev-list", "--first-parent",
                         "--max-count=201", f"{old}..{head}")),
            (str(land), ("rev-list", "--parents", "-n1", head)),
            (str(land), ("ls-remote", "origin", "refs/heads/main")),
        ])
        ack_log = {
            "at": "2026-11-23T12:00:00Z",
            "contexts": ["pr-checks"],
            "from": old,
            "mode": "verified",
            "prs": [17],
            "session": "owner",
            "to": head,
        }
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/ack.lock": b"",
            ".local/state/hass-triage/ack-log.jsonl":
                (json.dumps(ack_log, sort_keys=True) + "\n").encode(),
            ".local/state/hass-triage/state.json": b"{",
            ".local/state/hass-triage/tick.lock": b"4242",
            ".local/state/hass-triage/workflow-base.json":
                json.dumps({"main": head}, indent=2, sort_keys=True).encode(),
        })

    def test_recordless_tick_routes_merging_parked_recovery_and_stored_finish(self):
        """Fails if: maintenance 62-67 changes a route, effect, drop or expected complete byte."""
        self.maxDiff = None
        repo = self.cfg["request_repo"]
        product = self.cfg["product_repo"]
        merged_62 = f"https://github.com/{product}/pull/62"
        merged_63 = f"https://github.com/{product}/pull/63"
        parked_67 = f"https://github.com/{product}/pull/67"
        issues = [
            t.issue(62, labels=["Merging"], created="2026-10-01T00:00:00Z"),
            t.issue(63, labels=["Needs Decision"], created="2026-10-02T00:00:00Z"),
            t.issue(64, labels=["In Progress"], created="2026-10-03T00:00:00Z"),
            t.issue(65, labels=["In Progress"], created="2026-10-04T00:00:00Z"),
            t.issue(66, labels=["Blocked"], created="2026-10-05T00:00:00Z"),
            t.issue(67, labels=["Needs Decision"], created="2026-10-06T00:00:00Z"),
        ]
        finish_62 = {"state": "done", "summary": "merged sixty-two"}
        finish_63 = {"state": "done", "summary": "merged sixty-three"}
        finish_64 = {"state": "done", "summary": "stored finish sixty-four"}
        hold_path = self.paths.worktrees / "64"
        hold_path.mkdir(parents=True)
        self.paths.worktrees.joinpath("62").mkdir(parents=True)
        state_data = self.legacy(
            attempts={"65": 1},
            merging={"62": {
                "pr": merged_62, "status": finish_62, "since": 1
            }},
            parked={
                "63": {"pr": merged_63, "status": finish_63, "since": 1},
                "67": {
                    "pr": parked_67,
                    "status": finish_63,
                    "since": 1795435200.0,
                },
            },
            archive_sessions={"request-64": {
                "name": "request-64",
                "session": "request-64-fixed",
                "path": str(hold_path),
            }},
            archive_holds={"request-64": {
                "name": "request-64",
                "path": str(hold_path),
                "reason": "sidecar_archive_io",
                "since": "2026-11-22T00:00:00Z",
                "finish": {
                    "kind": "done", "status": finish_64, "pr": merged_63
                },
            }},
            opaque_extension={"preserve": ["maintenance", 3]},
        )
        self.write_raw(self.paths.state, state_data)
        gh = RecordlessTraceGitHub(
            {repo: issues},
            {
                merged_62: {"state": "MERGED", "url": merged_62, "labels": []},
                merged_63: {"state": "MERGED", "url": merged_63, "labels": []},
                parked_67: {"state": "OPEN", "url": parked_67, "labels": []},
            },
        )
        for number in (66, 67):
            gh.comment_store[number] = [
                {
                    "id": 700 + number,
                    "body": f"<!-- hass-triage:{number}:blocked -->",
                    "user": {"login": "sfenton-agent"},
                    "created_at": "2026-11-22T00:00:00Z",
                },
                {
                    "id": 800 + number,
                    "body": "pick the second option",
                    "user": {"login": "SFenton"},
                    "created_at": "2026-11-23T00:00:00Z",
                },
            ]
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        boundaries = RecordlessBoundaries(self.home)

        result = self.main_golden(
            ["tick", "--dry-run", "--max-items", "1"],
            cfg,
            gh,
            boundaries,
        )

        self.assertEqual(result, (
            0,
            "#66: owner replied; re-queued\n"
            "#67: owner replied; re-queued\n"
            "#65: worker gone; re-queued\n"
            "[dry-run] would work #65: [Bug] Thing 65\n"
            "[dry-run] queued #66: [Bug] Thing 66\n"
            "[dry-run] queued #67: [Bug] Thing 67\n",
            "",
        ))
        self.assertEqual(gh.events, [
            ("pull", merged_62),
            ("comments", repo, 62),
            ("comment", repo, 62,
             "**Resolved** (triage agent)\n\nmerged sixty-two\n\n"
             f"**Merged:** {merged_62}\n\n"
             "<!-- hass-triage:62:resolution -->"),
            ("labels", repo, 62, ("Done",),
             ("In Progress", "Merging", "Needs Decision")),
            ("close", repo, 62, False),
            ("pull", merged_63),
            ("comments", repo, 63),
            ("comment", repo, 63,
             "**Resolved** (triage agent)\n\nmerged sixty-three\n\n"
             f"**Merged:** {merged_63}\n\n"
             "<!-- hass-triage:63:resolution -->"),
            ("labels", repo, 63, ("Done",),
             ("In Progress", "Merging", "Needs Decision")),
            ("close", repo, 63, False),
            ("pull", parked_67),
            ("open", repo),
            ("comments", repo, 66),
            ("labels", repo, 66, (), ("Blocked",)),
            ("comments", repo, 67),
            ("labels", repo, 67, (), ("Needs Decision",)),
            ("label_pull", parked_67, "", "Needs Decision"),
            ("open", repo),
            ("comments", repo, 64),
            ("comment", repo, 64,
             "**Resolved** (triage agent)\n\nstored finish sixty-four\n\n"
             f"**Merged:** {merged_63}\n\n"
             "<!-- hass-triage:64:resolution -->"),
            ("labels", repo, 64, ("Done",),
             ("In Progress", "Merging", "Needs Decision")),
            ("close", repo, 64, False),
            ("labels", repo, 65, (), ("In Progress",)),
            ("open", repo),
        ])
        reopened = json.loads(self.paths.state.read_text())
        expected_history = [
            {
                "at": "2026-11-23T12:00:00Z",
                "detail": merged_62,
                "issue": 62,
                "outcome": "done",
            },
            {
                "at": "2026-11-23T12:00:00Z",
                "detail": merged_63,
                "issue": 63,
                "outcome": "done",
            },
            {
                "at": "2026-11-23T12:00:00Z",
                "detail": merged_63,
                "issue": 64,
                "outcome": "done",
            },
        ]
        expected = self.legacy(
            attempts={"65": 1},
            history=expected_history,
            replies={"66": 866, "67": 867},
            resumed={"66": "2026-11-23T00:00:00Z"},
            picked={"67": parked_67},
            opaque_extension={"preserve": ["maintenance", 3]},
        )
        self.assertEqual(reopened, expected)
        self.assertEqual(boundaries.launch_events, [])
        clone = str(self.paths.clone)
        tree_62 = str(self.paths.worktrees / "62")
        tree_64 = str(self.paths.worktrees / "64")
        self.assertEqual(boundaries.git_events, [
            (("gh", "repo", "clone", product, clone), ""),
            (("git", "-C", clone, "fetch", "-q", "origin",
              cfg["product_base"]), ""),
            (("git", "-C", tree_62, "diff", "--name-only",
              f"origin/{cfg['product_base']}...HEAD"), ""),
            (("git", "-C", clone, "worktree", "remove", "--force",
              tree_62), ""),
            (("git", "-C", tree_64, "diff", "--name-only",
              f"origin/{cfg['product_base']}...HEAD"), ""),
            (("git", "-C", clone, "worktree", "remove", "--force",
              tree_64), ""),
        ])
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/state.json": self.saved_bytes(expected),
            ".local/state/hass-triage/tick.lock": b"4242",
        })
        self.assertEqual(boundaries.forget_events, [])

    def test_recordless_scheduled_manual_job_and_retro_reach_both_saves_and_enqueue(self):
        """Fails if: job, retro or regression changes any ordered effect, normalized prompt or byte."""
        self.maxDiff = None
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        self.write_raw(self.paths.state, self.legacy(
            jobs={"researcher": {
                "last_run": "2026-01-01T00:00:00Z",
                "outcome": "old",
            }},
            opaque_extension={"preserve": ["jobs", 4]},
        ))
        gh = RecordlessTraceGitHub({cfg["request_repo"]: []})
        (self.paths.root / "land" / cfg["product_repo"].split("/")[-1] /
         ".git").mkdir(parents=True)
        landed_at = 1795435200.0
        for offset, after in (
            (-10, False),
            (10, True),
        ):
            for number in range(10):
                digest = (
                    self.paths.root / "archive" /
                    f"request-{after}-{number}" / "retro" /
                    f"flow-{number}.json"
                )
                digest.parent.mkdir(parents=True, exist_ok=True)
                triggers = (
                    [{"id": "owner_correction"}, {"id": "routing_override"}]
                    if after else []
                )
                digest.write_text(json.dumps({
                    "task": f"flow-{after}-{number}",
                    "triggers": triggers,
                    "cost": {"tokens": 2000 if after else 100},
                }))
                os.utime(digest, (landed_at + offset, landed_at + offset))
        statuses = {
            "job-researcher": {
                "state": "done",
                "summary": "job completed",
            },
            "retro-job-researcher-2026-11-23": (
                {
                    "state": "done",
                    "summary": "retro completed",
                },
                "job-researcher-2026-11-23",
            ),
        }
        boundaries = RecordlessBoundaries(self.home, statuses=statuses)
        fixture_bytes = self.file_bytes()

        scheduled = self.main_golden(
            ["tick"], cfg, gh, boundaries, observe_saves=True
        )
        self.assertEqual(scheduled, (0, "", ""))

        task = "job-researcher-2026-11-23"
        lane = "agents/researcher-golden"
        boundaries.launched = False
        boundaries.lane_ref = lane
        boundaries.statuses["job-researcher"] = {
            "state": "done",
            "summary": "job completed",
            "lanes": [lane],
        }
        boundaries.launcher_result["job-researcher"] = {
            "retro_seed": {
                "name": f"{task}.json",
                "value": {"triggers": [{"id": "history-volume"}]},
            },
        }
        manual = self.main_golden(
            ["run-job", "researcher"], cfg, gh, boundaries,
            observe_saves=True,
        )
        self.assertEqual(manual, (
            0,
            "job-researcher: landed agents/researcher-golden "
            "into main (dddddddddd)\ndone\n",
            "",
        ))
        queued = json.loads(ht.Paths(cfg, self.home, "retro-").state.read_text())
        self.assertEqual(
            [item["task"] for item in queued["queue"]],
            [task],
        )
        self.assertEqual(queued["queue"][0]["triggers"], ["history-volume"])

        retro = self.main_golden(
            ["tick"], cfg, gh, boundaries, observe_saves=True
        )
        self.assertEqual(retro, (0, "", ""))
        self.assertEqual(
            [(label, tree) for label, tree, _prompt in boundaries.launch_events],
            [
                ("job-researcher", "hass-agents/worktrees/job-researcher"),
                ("job-researcher", "hass-agents/worktrees/job-researcher"),
                (
                    "retro-job-researcher-2026-11-23",
                    "hass-agents/worktrees/retro-job-researcher-2026-11-23",
                ),
            ],
        )
        self.assertEqual(
            boundaries.land_events,
            [(lane, cfg["workflow_base"], "c" * 40)],
        )
        primary = json.loads(self.paths.state.read_text())
        self.assertEqual(primary["opaque_extension"], {"preserve": ["jobs", 4]})
        self.assertEqual(primary["current"], None)
        self.assertEqual(primary["jobs"]["researcher"]["outcome"], "done")
        self.assertEqual(primary["lanes"]["job-researcher"][lane], "merged")
        self.assertEqual(
            [entry["outcome"] for entry in primary["history"]],
            ["job:done", "job:done", "retro:done"],
        )
        reopened_retro = json.loads(
            ht.Paths(cfg, self.home, "retro-").state.read_text()
        )
        self.assertEqual(reopened_retro["queue"], [])
        self.assertIsNone(reopened_retro["current"])
        self.assertEqual(
            reopened_retro["done"][-1]["outcome"],
            "done",
        )
        self.assertEqual(
            reopened_retro["done"][-1]["task"],
            task,
        )

        regression = self.main_golden(
            ["tick"], cfg, gh, boundaries, observe_saves=True
        )
        self.assertEqual(regression, (
            0,
            f"revert: landed agents/revert-{'d' * 12} "
            "into main (dddddddddd)\n",
            "",
        ))
        self.assertEqual(boundaries.land_events[-1], (
            f"agents/revert-{'d' * 12}",
            cfg["workflow_base"],
            None,
        ))
        label_color = "5319e7"
        label_description = (
            "How the agents work: Steward-first, autonomous "
            "(owner 2026-11-02)"
        )
        self.assertEqual(gh.events, [
            *[("open", cfg["request_repo"]) for _ in range(3)],
            ("label", cfg["product_repo"], "Workflow", label_color,
             label_description),
            ("label", cfg["product_repo"], "Workflow", label_color,
             label_description),
            *[("open", cfg["request_repo"]) for _ in range(3)],
            ("label", cfg["product_repo"], "Workflow", label_color,
             label_description),
            *[("open", cfg["request_repo"]) for _ in range(4)],
            ("issue_create", cfg["request_repo"],
             "Workflow: agents/researcher-golden reverted, metrics "
             "regressed (dddddddddddd)",
             "`agents/researcher-golden` (merge `dddddddddddd`, landed "
             "2026-11-23T12:00:00Z) was followed by flows that got worse "
             "than the flows before it by more than 20% on 4 metrics:\n\n"
             "- corrections_per_task: 0.0 to 1.0 (from zero)\n"
             "- nudged_flows_rate: 0.0 to 1.0 (from zero)\n"
             "- routing_overrides_rate: 0.0 to 1.0 (from zero)\n"
             "- tokens_per_task: 100.0 to 2000.0 (+1900%)\n\n"
             "Flows compared: 10 before, 10 after.\n\n"
             "The runner prepared `agents/revert-dddddddddddd` and lands it "
             "like any lane (independent review, tests, protected paths).",
             ("Workflow",)),
        ])
        self.assertEqual(boundaries.launch_events, [
            (
                "job-researcher",
                "hass-agents/worktrees/job-researcher",
                ELIDED_PROMPT_ARGUMENTS["scheduled researcher"],
            ),
            (
                "job-researcher",
                "hass-agents/worktrees/job-researcher",
                ELIDED_PROMPT_ARGUMENTS["manual researcher"],
            ),
            ("retro-job-researcher-2026-11-23",
             "hass-agents/worktrees/retro-job-researcher-2026-11-23",
             ELIDED_PROMPT_ARGUMENTS["retro"]),
        ])
        self.assertEqual(boundaries.land_events, [
            (lane, cfg["workflow_base"], "c" * 40),
            (f"agents/revert-{'d' * 12}", cfg["workflow_base"], None),
        ])
        clone = str(self.paths.clone)
        land = str(
            self.paths.root / "land" /
            cfg["product_repo"].split("/")[-1]
        )
        job_tree = str(self.paths.worktrees / "job-researcher")
        retro_tree = str(
            self.paths.worktrees /
            "retro-job-researcher-2026-11-23"
        )

        def command(*args):
            return (tuple(str(arg) for arg in args), "")

        expected_git = [
            command("gh", "repo", "clone", cfg["product_repo"], clone),
            command("git", "-C", clone, "fetch", "-q", "origin",
                    cfg["product_base"]),
            command("git", "-C", clone, "checkout", "-q", "--detach",
                    f"origin/{cfg['product_base']}"),
            command("git", "-C", clone, "worktree", "prune"),
            (land, ("ls-remote", "origin", "refs/heads/main")),
            command("git", "-C", clone, "worktree", "prune"),
            command("git", "-C", clone, "fetch", "-q", "origin",
                    cfg["workflow_base"]),
            command("git", "-C", clone, "ls-remote", "--exit-code",
                    "--heads", "origin", cfg["workflow_base"]),
            command("git", "-C", clone, "worktree", "add", "-B",
                    "agents/researcher-261123", job_tree,
                    f"origin/{cfg['workflow_base']}"),
            (land, ("ls-remote", "origin", "refs/heads/agents/*")),
            (land, ("ls-remote", "origin", "refs/heads/main")),
            command("git", "-C", job_tree, "diff", "--name-only",
                    f"origin/{cfg['product_base']}...HEAD"),
            command(sys.executable,
                    str(ht.HERE.parent / "retro_digest.py"),
                    "--task", task, "--archive",
                    str(self.paths.root / "archive" / task),
                    "--outcome", "done"),
            command("git", "-C", clone, "worktree", "remove", "--force",
                    job_tree),
            command("git", "-C", clone, "fetch", "-q", "origin",
                    cfg["product_base"]),
            command("git", "-C", clone, "checkout", "-q", "--detach",
                    f"origin/{cfg['product_base']}"),
            command("git", "-C", clone, "worktree", "prune"),
            command("git", "-C", job_tree, "diff", "--name-only",
                    f"origin/{cfg['product_base']}...HEAD"),
            command("git", "-C", clone, "worktree", "remove", "--force",
                    job_tree),
            command("git", "-C", clone, "worktree", "prune"),
            command("git", "-C", clone, "fetch", "-q", "origin",
                    cfg["workflow_base"]),
            command("git", "-C", clone, "ls-remote", "--exit-code",
                    "--heads", "origin", cfg["workflow_base"]),
            command("git", "-C", clone, "worktree", "add", "-B",
                    "agents/researcher-261123", job_tree,
                    f"origin/{cfg['workflow_base']}"),
            (land, ("ls-remote", "origin", "refs/heads/agents/*")),
            (land, ("ls-remote", "origin", "refs/heads/main")),
            (land, ("ls-remote", "origin", "refs/heads/agents/*")),
            (land, ("ls-remote", "origin", "refs/heads/agents/*")),
            (land, ("ls-remote", "origin", "refs/heads/main")),
            (land, ("ls-remote", "origin", "refs/heads/main")),
            command("git", "-C", job_tree, "diff", "--name-only",
                    f"origin/{cfg['product_base']}...HEAD"),
            command(sys.executable,
                    str(ht.HERE.parent / "retro_digest.py"),
                    "--task", task, "--archive",
                    str(self.paths.root / "archive" / task),
                    "--outcome", "done"),
            command("git", "-C", clone, "worktree", "remove", "--force",
                    job_tree),
            command("git", "-C", clone, "fetch", "-q", "origin",
                    cfg["product_base"]),
            command("git", "-C", clone, "checkout", "-q", "--detach",
                    f"origin/{cfg['product_base']}"),
            command("git", "-C", clone, "worktree", "prune"),
            (land, ("ls-remote", "origin", "refs/heads/main")),
            command("git", "-C", clone, "ls-remote", "--exit-code",
                    "origin", cfg["workflow_base"]),
            command("git", "-C", clone, "worktree", "prune"),
            command("git", "-C", clone, "fetch", "-q", "origin",
                    cfg["workflow_base"]),
            command("git", "-C", clone, "worktree", "add", "-B",
                    "agents/retro-job-researcher-2026-11-23-261123",
                    retro_tree, f"origin/{cfg['workflow_base']}"),
            (land, ("ls-remote", "origin", "refs/heads/agents/*")),
            (land, ("ls-remote", "origin", "refs/heads/main")),
            command("git", "-C", retro_tree, "diff", "--name-only",
                    f"origin/{cfg['product_base']}...HEAD"),
            command(sys.executable,
                    str(ht.HERE.parent / "retro_digest.py"),
                    "--task", f"retro-{task}", "--archive",
                    str(self.paths.root / "archive" / f"retro-{task}"),
                    "--outcome", "done"),
            command("git", "-C", clone, "fetch", "-q", "origin",
                    cfg["product_base"]),
            command("git", "-C", retro_tree, "rev-parse", "HEAD"),
            command("git", "-C", clone, "merge-base", "--is-ancestor", "",
                    f"origin/{cfg['product_base']}"),
            command("git", "-C", clone, "worktree", "remove", "--force",
                    retro_tree),
            command("git", "-C", clone, "fetch", "-q", "origin",
                    cfg["product_base"]),
            command("git", "-C", clone, "checkout", "-q", "--detach",
                    f"origin/{cfg['product_base']}"),
            command("git", "-C", clone, "worktree", "prune"),
            (land, ("ls-remote", "origin", "refs/heads/main")),
            (land, ("fetch", "-q", "origin",
                    "+refs/heads/main:refs/remotes/origin/main")),
            (land, ("merge-base", "--is-ancestor", "d" * 40,
                    "refs/remotes/origin/main")),
            (land, ("ls-remote", "origin",
                    f"refs/heads/agents/revert-{'d' * 12}")),
            (land, ("checkout", "-q", "-f", "-B",
                    f"_revert/{'d' * 12}",
                    "refs/remotes/origin/main")),
            (land, ("revert", "-m", "1", "--no-commit", "d" * 40)),
            (land, ("commit", "-q", "-m",
                    "Revert agents/researcher-golden (dddddddddddd): "
                    "the metrics regressed\n\n"
                    "- corrections_per_task: 0.0 to 1.0 (from zero)\n"
                    "- nudged_flows_rate: 0.0 to 1.0 (from zero)\n"
                    "- routing_overrides_rate: 0.0 to 1.0 (from zero)\n"
                    "- tokens_per_task: 100.0 to 2000.0 (+1900%)\n\n"
                    "Automatic revert by the triage runner (plan section "
                    "9); it lands through the normal review.\n\n"
                    "Release-Note: none\n"
                    "Co-Authored-By: Claude Opus 5.5 "
                    "<noreply@anthropic.com>\n")),
            (land, ("rev-parse", "HEAD")),
            (land, ("push", "origin",
                    f"HEAD:refs/heads/agents/revert-{'d' * 12}")),
            (land, ("checkout", "-q", "-f", "--detach",
                    "refs/remotes/origin/main")),
            (land, ("ls-remote", "origin", "refs/heads/main")),
            (land, ("ls-remote", "origin", "refs/heads/main")),
        ]
        self.assertEqual(boundaries.git_events, expected_git)
        primary_expected = self.legacy(
            archive_sessions={
                "job-researcher": {
                    "name": task,
                    "path": str(
                        self.paths.worktrees / "job-researcher"
                    ),
                    "session": "job-researcher-897aded5543e",
                },
                "retro-job-researcher-2026-11-23": {
                    "name": "retro-job-researcher-2026-11-23",
                    "path": str(
                        self.paths.worktrees /
                        "retro-job-researcher-2026-11-23"
                    ),
                    "session":
                        "retro-job-researcher-2026-11-23-e6789b1f72f7",
                },
            },
            history=[
                {
                    "at": "2026-11-23T12:00:00Z",
                    "detail": "agents/researcher-261123",
                    "issue": "job-researcher",
                    "outcome": "job:done",
                },
                {
                    "at": "2026-11-23T12:00:00Z",
                    "detail": "agents/researcher-261123",
                    "issue": "job-researcher",
                    "outcome": "job:done",
                },
                {
                    "at": "2026-11-23T12:00:00Z",
                    "detail": task,
                    "issue": "retro-job-researcher-2026-11-23",
                    "outcome": "retro:done",
                },
            ],
            jobs={
                "researcher": {
                    "archive_name": task,
                    "archive_session": "job-researcher-897aded5543e",
                    "branch": "agents/researcher-261123",
                    "last_run": "2026-11-23T12:00:00Z",
                    "outcome": "done",
                },
                "steward": {"last_run": "2026-11-23T12:00:00Z"},
            },
            lanes={
                "job-researcher": {lane: "merged"},
            },
            opaque_extension={"preserve": ["jobs", 4]},
            test_counts={},
        )
        retro_expected = self.legacy(
            queue=[],
            done=[{
                "archive": str(
                    self.paths.root / "archive" / task
                ),
                "archive_name": "retro-job-researcher-2026-11-23",
                "archive_session":
                    "retro-job-researcher-2026-11-23-e6789b1f72f7",
                "finished": "2026-11-23T12:00:00Z",
                "outcome": "done",
                "queued": "2026-11-23T12:00:00Z",
                "summary": "retro completed",
                "task": task,
                "touched": [],
                "triggers": ["history-volume"],
            }],
        )
        landing = {
            "after": {
                "flows": 10,
                "metrics": {
                    "corrections_per_task": 1.0,
                    "nudged_flows_rate": 1.0,
                    "owner_rule_repeats_rate": 0.0,
                    "review_findings_per_pr": 0.0,
                    "routing_overrides_rate": 1.0,
                    "tokens_per_task": 2000.0,
                },
            },
            "base": "main",
            "evaluated": "reverted",
            "landed_at": "2026-11-23T12:00:00Z",
            "lane": lane,
            "merge_sha": "d" * 40,
            "metrics_before": {
                "flows": 10,
                "metrics": {
                    "corrections_per_task": 0.0,
                    "nudged_flows_rate": 0.0,
                    "owner_rule_repeats_rate": 0.0,
                    "review_findings_per_pr": 0.0,
                    "routing_overrides_rate": 0.0,
                    "tokens_per_task": 100.0,
                },
            },
            "regressed": [
                {
                    "after": 1.0,
                    "before": 0.0,
                    "change_pct": None,
                    "metric": metric,
                }
                for metric in (
                    "corrections_per_task",
                    "nudged_flows_rate",
                    "routing_overrides_rate",
                )
            ] + [{
                "after": 2000.0,
                "before": 100.0,
                "change_pct": 1900.0,
                "metric": "tokens_per_task",
            }],
            "revert_lane": f"agents/revert-{'d' * 12}",
            "revert_sha": "",
        }
        expected_files = dict(fixture_bytes)
        expected_files.update({
            ".local/state/hass-triage/landings.json":
                self.saved_bytes([landing]),
            ".local/state/hass-triage/landings.lock": b"",
            ".local/state/hass-triage/state-retro.json":
                self.saved_bytes(retro_expected),
            ".local/state/hass-triage/state.json":
                self.saved_bytes(primary_expected),
            ".local/state/hass-triage/tick.lock": b"4242",
            f"hass-agents/archive/{task}/retro/{task}.json":
                b'{\n  "triggers": [\n    {\n'
                b'      "id": "history-volume"\n'
                b'    }\n  ]\n}\n',
            f"hass-agents/archive/{task}/status.json":
                b'{\n  "state": "done",\n'
                b'  "summary": "job completed",\n'
                b'  "lanes": [\n'
                b'    "agents/researcher-golden"\n  ]\n}\n',
            f"hass-agents/archive/{task}/worker.log.tail":
                b"recordless launcher fixture\n",
            "hass-agents/archive/retro-job-researcher-2026-11-23/retro/"
            f"{task}.status.json":
                b'{\n  "state": "done",\n'
                b'  "summary": "retro completed"\n}\n',
            "hass-agents/archive/retro-job-researcher-2026-11-23/"
            "status.json":
                b'{\n  "state": "done",\n'
                b'  "summary": "retro completed"\n}\n',
            "hass-agents/archive/retro-job-researcher-2026-11-23/"
            "worker.log.tail": b"recordless launcher fixture\n",
            "hass-agents/logs/job-researcher-1.log":
                b"recordless launcher fixture\n",
            "hass-agents/logs/retro-job-researcher-2026-11-23-1.log":
                b"recordless launcher fixture\n",
            "hass-agents/status/job-researcher.json":
                b'{"state": "done", "summary": "job completed", '
                b'"lanes": ["agents/researcher-golden"]}',
            "hass-agents/status/retro-job-researcher-2026-11-23.json":
                b'{"state": "done", "summary": "retro completed"}',
            f"hass-agents/worktrees/job-researcher/build/retro/{task}.json":
                b'{"triggers": [{"id": "history-volume"}]}',
            "hass-agents/worktrees/retro-job-researcher-2026-11-23/"
            f"build/retro/{task}.status.json":
                b'{"state": "done", "summary": "retro completed"}',
        })
        self.assertEqual(self.file_bytes(), expected_files)
        self.assertEqual(boundaries.persistence_events, [
            ("save", "state.json"),
            ("drop", "hass-agents/worktrees/job-researcher"),
            ("save", "state.json"),
            ("save", "state.json"),
            ("save", "state.json"),
            ("drop", "hass-agents/worktrees/job-researcher"),
            ("save", "state.json"),
            ("save", "state-retro.json"),
            ("drop", "hass-agents/worktrees/job-researcher"),
            ("save", "state.json"),
            ("save", "state-retro.json"),
            ("save", "state.json"),
            ("save", "state-retro.json"),
            ("drop",
             "hass-agents/worktrees/retro-job-researcher-2026-11-23"),
            ("save", "state.json"),
            ("save", "state.json"),
            ("save", "state.json"),
        ])
        self.assertEqual(boundaries.forget_events, [
            (self.paths.worktrees / "job-researcher", self.home),
            (self.paths.worktrees / "job-researcher", self.home),
            (self.paths.worktrees / "job-researcher", self.home),
            (
                self.paths.worktrees /
                "retro-job-researcher-2026-11-23",
                self.home,
            ),
        ])

    def test_recordless_run_issue_tamper_routes_block_and_disarms_pull(self):
        """Fails if: request 71 tamper changes classification, disarm, prompt normalization or bytes."""
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        item = t.issue(71, created="2026-10-01T00:00:00Z")
        pull = f"https://github.com/{cfg['product_repo']}/pull/71"
        gh = RecordlessTraceGitHub({cfg["request_repo"]: [item]})
        gh.branch_pull_list = [
            {"url": pull, "state": "OPEN", "labels": []}
        ]
        self.write_raw(self.paths.state, self.legacy(
            opaque_extension={"preserve": ["tamper", 5]}
        ))
        boundaries = RecordlessBoundaries(
            self.home,
            launcher={71: {"tampered": True}},
        )

        result = self.main_golden(
            ["run-issue", "71"], cfg, gh, boundaries
        )

        self.assertEqual(
            result[0],
            0,
        )
        self.assertRegex(
            result[1],
            r"^#71: retro phase failed: \[Errno 2\] No such file or directory: "
            r"'.*/hass-agents/archive/request-71/status\.json'\nblocked\n$",
        )
        self.assertEqual(result[2], "")
        detail = (
            "The session changed the guard hooks, settings or triage "
            "record, so its result was not used. auto-merge on "
            f"{pull} was turned off."
        )
        self.assertEqual(gh.events, [
            ("issue", cfg["request_repo"], 71),
            ("labels", cfg["request_repo"], 71, ("In Progress",), ()),
            ("comments", cfg["request_repo"], 71),
            ("comment", cfg["request_repo"], 71,
             "**Picked up** (triage agent)\n\n"
             "Started working on this (attempt 1). Progress shows up here as "
             "comments.\n\n<!-- hass-triage:71:pickup -->"),
            ("branch_pulls", cfg["product_repo"], "report/71"),
            ("disarm", pull),
            ("label_pull", pull, "", cfg["merge"]["label"]),
            ("comments", cfg["request_repo"], 71),
            ("comment", cfg["request_repo"], 71,
             "**Stopped** (triage agent)\n\n"
             f"{detail}\n\n"
             "Reply here (or comment `/retry`) and the agent picks it up "
             "again on its next run.\n\n"
             "<details><summary>Last lines of the session log</summary>\n\n"
             "```\nrecordless launcher fixture\n```\n</details>\n\n"
             "<!-- hass-triage:71:blocked -->"),
            ("labels", cfg["request_repo"], 71, ("Blocked",),
             ("In Progress", "Merging", "Needs Decision")),
            ("comments", cfg["request_repo"], 71),
        ])
        clone = str(self.paths.clone)
        tree = str(self.paths.worktrees / "71")
        archive = self.paths.root / "archive" / "request-71"
        self.assertEqual(boundaries.git_events, [
            (("gh", "repo", "clone", cfg["product_repo"], clone), ""),
            (("git", "-C", clone, "fetch", "-q", "origin",
              cfg["product_base"]), ""),
            (("git", "-C", clone, "checkout", "-q", "--detach",
              f"origin/{cfg['product_base']}"), ""),
            (("git", "-C", clone, "worktree", "prune"), ""),
            (("git", "-C", clone, "rev-parse", "--verify", "-q",
              "report/71"), ""),
            (("git", "-C", clone, "ls-remote", "--exit-code", "origin",
              "report/71"), ""),
            (("git", "-C", clone, "worktree", "add", tree,
              "report/71"), ""),
            (("git", "-C", tree, "diff", "--name-only",
              f"origin/{cfg['product_base']}...HEAD"), ""),
            ((sys.executable, str(ht.HERE.parent / "retro_digest.py"),
              "--task", "R-71", "--archive", str(archive), "--outcome",
              "blocked:guard_tampered", "--attempt", "1", "--started",
              "2026-11-23T12:00:00Z"), ""),
        ])
        self.assertEqual(boundaries.launch_events, [
            (
                71,
                "hass-agents/worktrees/71",
                ELIDED_PROMPT_ARGUMENTS["request 71"],
            ),
        ])
        reopened = json.loads(self.paths.state.read_text())
        self.assertEqual(reopened["current"], None)
        self.assertEqual(reopened["opaque_extension"], {
            "preserve": ["tamper", 5]
        })
        self.assertEqual(reopened["history"][-1]["outcome"], "blocked:guard_tampered")
        self.assertEqual(
            reopened["history"][-1]["detail"],
            detail,
        )
        expected = self.legacy(
            archive_sessions={
                "request-71": {
                    "name": "request-71",
                    "path": str(self.paths.worktrees / "71"),
                    "session": "request-71-a2d9ced85f6f",
                },
            },
            history=[{
                "at": "2026-11-23T12:00:00Z",
                "detail": detail,
                "issue": 71,
                "outcome": "blocked:guard_tampered",
            }],
            opaque_extension={"preserve": ["tamper", 5]},
        )
        request_snapshot = {
            "number": 71,
            "title": "[Bug] Thing 71",
            "body": "It broke",
            "author": "SFenton",
            "labels": [],
            "snapshot_at": "2026-11-23T12:00:00Z",
        }
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/state.json": self.saved_bytes(expected),
            ".local/state/hass-triage/tick.lock": b"4242",
            "hass-agents/archive/request-71/worker.log.tail":
                b"recordless launcher fixture\n",
            "hass-agents/logs/71-1.log":
                b"recordless launcher fixture\n",
            "hass-agents/requests/71.json":
                json.dumps(request_snapshot, indent=2).encode(),
        })
        self.assertEqual(boundaries.forget_events, [])

    def test_recordless_ordinary_request_finishes_successfully(self):
        """Fails if: request 70 changes positive-empty cleanup, prompt or complete bytes."""
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        issue = t.issue(70, created="2026-10-01T00:00:00Z")
        gh = RecordlessTraceGitHub({cfg["request_repo"]: [issue]})
        primary = self.legacy(
            opaque_extension={"preserve": ["ordinary", 9]}
        )
        self.write_raw(self.paths.state, primary)
        boundaries = RecordlessBoundaries(
            self.home,
            statuses={70: {
                "state": "no_changes",
                "summary": "nothing to change",
            }},
        )

        result = self.main_golden(
            ["run-issue", "70"], cfg, gh, boundaries
        )
        self.assertEqual(result, (0, "no_changes\n", ""))
        self.assertEqual(gh.events, [
            ("issue", cfg["request_repo"], 70),
            ("labels", cfg["request_repo"], 70, ("In Progress",), ()),
            ("comments", cfg["request_repo"], 70),
            ("comment", cfg["request_repo"], 70,
             "**Picked up** (triage agent)\n\n"
             "Started working on this (attempt 1). Progress shows up here as "
             "comments.\n\n<!-- hass-triage:70:pickup -->"),
            ("comments", cfg["request_repo"], 70),
            ("comment", cfg["request_repo"], 70,
             "**Result** (triage agent)\n\nnothing to change\n\n"
             "<!-- hass-triage:70:result -->"),
            ("labels", cfg["request_repo"], 70, ("No Changes",),
             ("In Progress",)),
            ("close", cfg["request_repo"], 70, True),
            ("comments", cfg["request_repo"], 70),
        ])
        clone = str(self.paths.clone)
        tree = str(self.paths.worktrees / "70")
        archive = self.paths.root / "archive" / "request-70"
        self.assertEqual(boundaries.git_events, [
            (("gh", "repo", "clone", cfg["product_repo"], clone), ""),
            (("git", "-C", clone, "fetch", "-q", "origin",
              cfg["product_base"]), ""),
            (("git", "-C", clone, "checkout", "-q", "--detach",
              f"origin/{cfg['product_base']}"), ""),
            (("git", "-C", clone, "worktree", "prune"), ""),
            (("git", "-C", clone, "rev-parse", "--verify", "-q",
              "report/70"), ""),
            (("git", "-C", clone, "ls-remote", "--exit-code", "origin",
              "report/70"), ""),
            (("git", "-C", clone, "worktree", "add", tree, "report/70"), ""),
            (("git", "-C", tree, "diff", "--name-only",
              f"origin/{cfg['product_base']}...HEAD"), ""),
            (("git", "-C", clone, "worktree", "remove", "--force", tree), ""),
            (("git", "-C", tree, "diff", "--name-only",
              f"origin/{cfg['product_base']}...HEAD"), ""),
            ((sys.executable, str(ht.HERE.parent / "retro_digest.py"),
              "--task", "R-70", "--archive", str(archive), "--outcome",
              "no_changes", "--attempt", "1", "--started",
              "2026-11-23T12:00:00Z"), ""),
        ])
        self.assertEqual(boundaries.launch_events, [
            (
                70,
                "hass-agents/worktrees/70",
                ELIDED_PROMPT_ARGUMENTS["request 70"],
            ),
        ])
        self.assertIn("request #70", boundaries.launch_events[0][2])
        expected = self.legacy(
            history=[{
                "at": "2026-11-23T12:00:00Z",
                "detail": "nothing to change",
                "issue": 70,
                "outcome": "no_changes",
            }],
            opaque_extension={"preserve": ["ordinary", 9]},
        )
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/state.json": self.saved_bytes(expected),
            ".local/state/hass-triage/tick.lock": b"4242",
            "hass-agents/archive/request-70/status.json": (
                b'{\n  "state": "no_changes",\n'
                b'  "summary": "nothing to change"\n}\n'
            ),
            "hass-agents/archive/request-70/worker.log.tail":
                b"recordless launcher fixture\n",
            "hass-agents/logs/70-1.log": b"recordless launcher fixture\n",
            "hass-agents/status/70.json":
                b'{"state": "no_changes", "summary": "nothing to change"}',
        })
        self.assertEqual(boundaries.forget_events, [
            (self.paths.worktrees / "70", self.home),
        ])

    def test_recordless_manual_busy_paused_and_asymmetric_preview_modes(self):
        """Fails if: busy, pause or preview paths perform any extra launch, Git or drop work."""
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        issue = t.issue(72)
        gh = RecordlessTraceGitHub({cfg["request_repo"]: [issue]})
        self.write_raw(self.paths.state, self.legacy(
            opaque_extension={"preserve": ["manual", 6]}
        ))
        boundaries = RecordlessBoundaries(self.home)

        with ht.writer_lock(self.paths) as admitted:
            self.assertTrue(admitted)
            self.assertEqual(
                self.main_golden(["run-issue", "72"], cfg, gh, boundaries),
                (
                    1,
                    "another runner writer is active; run-issue refused\n",
                    "",
                ),
            )
            self.assertEqual(
                self.main_golden(["run-job", "researcher"], cfg, gh, boundaries),
                (
                    1,
                    "another runner writer is active; run-job refused\n",
                    "",
                ),
            )
        self.assertEqual(
            self.main_golden(["pause"], cfg, gh, boundaries),
            (0, "Paused: no new work starts until `resume`.\n", ""),
        )
        self.assertTrue(self.paths.paused.exists())
        self.assertEqual(
            self.main_golden(["run-job", "researcher"], cfg, gh, boundaries),
            (0, "paused\n", ""),
        )

        preview = self.main_golden(
            ["run-issue", "72", "--dry-run"], cfg, gh, boundaries
        )
        self.assertEqual((preview[0], preview[2]), (0, ""))
        self.assertTrue(
            preview[1].startswith(
                "# Fenton Home triage agent: request #72\n"
            ),
        )
        self.assertIn("report/72", preview[1])
        self.assertIn("## The request", preview[1])
        self.assertEqual(
            json.loads(self.paths.state.read_text())["opaque_extension"],
            {"preserve": ["manual", 6]},
        )
        self.assertEqual(
            self.main_golden(["resume"], cfg, gh, boundaries),
            (0, "Resumed.\n", ""),
        )
        self.assertFalse(self.paths.paused.exists())
        self.assertEqual(gh.events, [
            ("issue", cfg["request_repo"], 72),
        ])
        self.assertEqual(boundaries.git_events, [])
        self.assertEqual(boundaries.launch_events, [])
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/state.json":
                json.dumps(self.legacy(
                    opaque_extension={"preserve": ["manual", 6]}
                )).encode(),
            ".local/state/hass-triage/tick.lock": b"4242",
        })
        self.assertEqual(boundaries.forget_events, [])

    def test_recordless_status_formats_under_real_lock_with_independent_queue_error(
        self, expected_custody=_PA_EMPTY_CUSTODY
    ):
        """Fails if: locked status stops being read-only, bounded or byte-identical."""
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        primary = self.legacy(
            opaque_extension={"preserve": ["status", 7]}
        )
        self.write_raw(self.paths.state, primary)
        retained_nightly = ht.Paths(self.cfg, self.home, "nightly-").state
        self.write_raw(retained_nightly, "{")
        retro = ht.Paths(self.cfg, self.home, "retro-").state
        self.write_raw(retro, self.legacy(queue=[], done=[]))
        gh = RecordlessQueueErrorGitHub({cfg["request_repo"]: []})
        boundaries = RecordlessBoundaries(self.home)
        self.assert_pa_custody_loader(
            cfg,
            expected_custody,
            _PA_MALFORMED_NIGHTLY_JSON_FIELDS["state_loads"],
        )
        self.assert_pa_locked_status(
            cfg,
            gh,
            boundaries,
            (
                with_custody_text(
                    _PA_MALFORMED_NIGHTLY_STATUS_TEXT, _CT_REQUEST_72
                )
                if expected_custody is _PA_REQUEST_72_CUSTODY
                else _PA_MALFORMED_NIGHTLY_STATUS_TEXT
            ),
            _PA_MALFORMED_NIGHTLY_JSON_FIELDS,
            _PA_MALFORMED_NIGHTLY_JSON_FIELDS["state_loads"],
            _PA_MALFORMED_NIGHTLY_JSON_FIELDS["queue"],
            _PA_MALFORMED_NIGHTLY_JSON_FIELDS["nightly_queue"],
            _PA_MALFORMED_NIGHTLY_JSON_FIELDS["retro_queue"],
            (
                (("open", cfg["request_repo"]),),
                (("open", cfg["request_repo"]),),
            ),
            (
                (("open", cfg["request_repo"]),),
                (("open", cfg["request_repo"]),),
            ),
            {
                ".local/state/hass-triage/state-nightly.json": b"{",
                ".local/state/hass-triage/state-retro.json":
                    json.dumps(self.legacy(queue=[], done=[])).encode(),
                ".local/state/hass-triage/state.json":
                    json.dumps(primary).encode(),
                ".local/state/hass-triage/tick.lock": b"4242",
            },
            expected_custody=expected_custody,
            expected_custody_text=(
                _CT_REQUEST_72
                if expected_custody is _PA_REQUEST_72_CUSTODY
                else _PA_ABSENT
            ),
        )
        self.assertEqual(
            gh.events,
            [("open", cfg["request_repo"])] * 2,
        )

    def test_custody_pa_locked_status_profiles(self):
        """Fails if: a P-a fixture changes legacy status or its read-only seams."""
        integrated = self.integrated_job_seeds()
        profiles = [
            (
                "healthy readable recordless",
                self.legacy(),
                self.legacy(),
                False,
                _PA_EMPTY_CUSTODY,
            ),
            (
                "healthy empty-v1",
                self.legacy(
                    custody={"version": 1, "records": {}}
                ),
                self.legacy(
                    custody={"version": 1, "records": {}}
                ),
                False,
                _PA_EMPTY_CUSTODY,
            ),
            (
                "valid request 42",
                self.legacy(custody=self.request_seed(42).aggregate()),
                self.legacy(),
                False,
                _PA_REQUEST_42_CUSTODY,
            ),
            (
                "valid nightly 52",
                self.legacy(),
                self.legacy(custody=self.nightly_seed(52).aggregate()),
                False,
                _PA_NIGHTLY_52_CUSTODY,
            ),
            (
                "request 72 and nightly 72",
                self.legacy(custody=self.request_seed(72).aggregate()),
                self.legacy(custody=self.nightly_seed(72).aggregate()),
                False,
                _PA_SAME_NUMBER_72_CUSTODY,
            ),
            (
                "integrated job then retro",
                self.legacy(custody=integrated.aggregate()),
                self.legacy(),
                False,
                _PA_INTEGRATED_CUSTODY,
            ),
            (
                "integrated retro then job",
                self.legacy(custody=CustodySeeds(
                    tuple(reversed(integrated.items))
                ).aggregate()),
                self.legacy(),
                False,
                _PA_INTEGRATED_CUSTODY,
            ),
            (
                "retained nightly and failing request queue",
                self.legacy(custody=self.request_seed(42).aggregate()),
                self.legacy(custody=self.nightly_seed(52).aggregate()),
                True,
                _PA_RETAINED_NIGHTLY_CUSTODY,
            ),
        ]

        def reset():
            shutil.rmtree(self.home, ignore_errors=True)
            self.home.mkdir()

        for (
            label, primary, nightly, queue_error, expected_custody
        ) in profiles:
            with self.subTest(profile=label):
                reset()
                cfg = dict(self.cfg)
                cfg["schedules"] = {}
                self.write_raw(self.paths.state, primary)
                nightly_path = ht.Paths(
                    self.cfg, self.home, "nightly-"
                ).state
                self.write_raw(nightly_path, nightly)
                if label == "healthy readable recordless":
                    self.assertNotIn("custody", ht.State(self.paths.state).data)
                    self.assertNotIn("custody", ht.State(nightly_path).data)
                elif label == "healthy empty-v1":
                    self.assertIn("custody", ht.State(self.paths.state).data)
                    self.assertIn("custody", ht.State(nightly_path).data)
                if queue_error:
                    cfg["nightly"] = None
                    gh = RecordlessQueueErrorGitHub({
                        cfg["request_repo"]: [],
                    })
                    expected_text = _PA_QUEUE_ERROR_STATUS_TEXT
                    expected_json = _PA_QUEUE_ERROR_JSON_FIELDS
                    expected_queue_events = (
                        (("open", cfg["request_repo"]),),
                        (("open", cfg["request_repo"]),),
                    )
                    expected_remote_events = (
                        (("open", cfg["request_repo"]),),
                        (("open", cfg["request_repo"]),),
                    )
                else:
                    gh = RecordlessTraceGitHub({
                        cfg["request_repo"]: [],
                        cfg["nightly"]["repo"]: [],
                    })
                    expected_text = _PA_HEALTHY_STATUS_TEXT
                    expected_json = _PA_HEALTHY_JSON_FIELDS
                    expected_queue_events = (
                        (
                            ("open", cfg["request_repo"]),
                            ("open", cfg["nightly"]["repo"]),
                        ),
                        (
                            ("open", cfg["request_repo"]),
                            ("open", cfg["nightly"]["repo"]),
                        ),
                    )
                    expected_remote_events = (
                        (
                            ("open", cfg["request_repo"]),
                            ("open", cfg["nightly"]["repo"]),
                        ),
                        (
                            ("open", cfg["request_repo"]),
                            ("open", cfg["nightly"]["repo"]),
                        ),
                    )
                self.assert_pa_custody_loader(
                    cfg, expected_custody, expected_json["state_loads"]
                )
                expected_files = {
                    ".local/state/hass-triage/state.json":
                        json.dumps(primary).encode(),
                    ".local/state/hass-triage/state-nightly.json":
                        json.dumps(nightly).encode(),
                    ".local/state/hass-triage/tick.lock": b"4242",
                }
                expected_custody_text = {
                    "valid request 42": _CT_REQUEST_42,
                    "valid nightly 52": _CT_NIGHTLY_52,
                    "request 72 and nightly 72": (
                        _CT_NIGHTLY_72 + _CT_REQUEST_72
                    ),
                    "integrated job then retro": _CT_JOB + _CT_RETRO,
                    "integrated retro then job": _CT_JOB + _CT_RETRO,
                    "retained nightly and failing request queue": (
                        _CT_NIGHTLY_52 + _CT_REQUEST_42
                    ),
                }.get(label, _PA_ABSENT)
                if expected_custody_text is not _PA_ABSENT:
                    expected_text = with_custody_text(
                        expected_text, expected_custody_text
                    )
                self.assert_pa_locked_status(
                    cfg,
                    gh,
                    RecordlessBoundaries(self.home),
                    expected_text,
                    expected_json,
                    expected_json["state_loads"],
                    expected_json["queue"],
                    expected_json["nightly_queue"],
                    expected_json["retro_queue"],
                    expected_queue_events,
                    expected_remote_events,
                    expected_files,
                    expected_custody=expected_custody,
                    expected_custody_text=expected_custody_text,
                )
                if label == "healthy readable recordless":
                    with self.subTest(
                        expectation="supplied custody JSON"
                    ):
                        self.assert_pa_locked_status(
                            cfg,
                            RecordlessTraceGitHub({
                                cfg["request_repo"]: [],
                                cfg["nightly"]["repo"]: [],
                            }),
                            RecordlessBoundaries(self.home),
                            expected_text,
                            expected_json,
                            expected_json["state_loads"],
                            expected_json["queue"],
                            expected_json["nightly_queue"],
                            expected_json["retro_queue"],
                            expected_queue_events,
                            expected_remote_events,
                            expected_files,
                            expected_custody={
                                "version": 1,
                                "records": [],
                                "faults": [],
                            },
                        )
                    with self.subTest(
                        expectation="wrong supplied custody type"
                    ), self.assertRaisesRegex(
                        AssertionError,
                        "custody JSON type at custody.version",
                    ):
                        self.assert_pa_locked_status(
                            cfg,
                            RecordlessTraceGitHub({
                                cfg["request_repo"]: [],
                                cfg["nightly"]["repo"]: [],
                            }),
                            RecordlessBoundaries(self.home),
                            expected_text,
                            expected_json,
                            expected_json["state_loads"],
                            expected_json["queue"],
                            expected_json["nightly_queue"],
                            expected_json["retro_queue"],
                            expected_queue_events,
                            expected_remote_events,
                            expected_files,
                            expected_custody={
                                "version": True,
                                "records": [],
                                "faults": [],
                            },
                        )
                    with self.subTest(
                        expectation="omitted custody JSON"
                    ), self.assertRaisesRegex(
                        AssertionError,
                        "custody JSON decoded root is present",
                    ):
                        self.assert_pa_locked_status(
                            cfg,
                            RecordlessTraceGitHub({
                                cfg["request_repo"]: [],
                                cfg["nightly"]["repo"]: [],
                            }),
                            RecordlessBoundaries(self.home),
                            expected_text,
                            expected_json,
                            expected_json["state_loads"],
                            expected_json["queue"],
                            expected_json["nightly_queue"],
                            expected_json["retro_queue"],
                            expected_queue_events,
                            expected_remote_events,
                            expected_files,
                        )
                    with self.subTest(
                        expectation="supplied custody text"
                    ), self.assertRaisesRegex(
                        AssertionError, "custody text stdout comparison"
                    ):
                        expected_text_with_custody = (
                            expected_text[0],
                            expected_text[1]
                            + "custody record request:42\n",
                            expected_text[2],
                        )
                        self.assert_pa_locked_status(
                            cfg,
                            RecordlessTraceGitHub({
                                cfg["request_repo"]: [],
                                cfg["nightly"]["repo"]: [],
                            }),
                            RecordlessBoundaries(self.home),
                            expected_text_with_custody,
                            expected_json,
                            expected_json["state_loads"],
                            expected_json["queue"],
                            expected_json["nightly_queue"],
                            expected_json["retro_queue"],
                            expected_queue_events,
                            expected_remote_events,
                            expected_files,
                            expected_custody_text=(
                                "custody record request:42\n"
                            ),
                        )
                if label == "valid request 42":
                    wrong_line = _CT_REQUEST_42.replace(
                        "age 0s;", "age 1s;"
                    )
                    self.assertNotEqual(wrong_line, _CT_REQUEST_42)
                    with self.subTest(
                        expectation="supplied custody text line only"
                    ), self.assertRaisesRegex(
                        AssertionError,
                        "supplied line is missing from expected text",
                    ):
                        self.assert_pa_locked_status(
                            cfg,
                            RecordlessTraceGitHub({
                                cfg["request_repo"]: [],
                                cfg["nightly"]["repo"]: [],
                            }),
                            RecordlessBoundaries(self.home),
                            expected_text,
                            expected_json,
                            expected_json["state_loads"],
                            expected_json["queue"],
                            expected_json["nightly_queue"],
                            expected_json["retro_queue"],
                            expected_queue_events,
                            expected_remote_events,
                            expected_files,
                            expected_custody=expected_custody,
                            expected_custody_text=wrong_line,
                        )
                    with self.subTest(
                        expectation="custody text equality operands"
                    ), self.assertRaisesRegex(
                        AssertionError,
                        "custody text stdout comparison",
                    ):
                        self.assert_pa_locked_status(
                            cfg,
                            RecordlessTraceGitHub({
                                cfg["request_repo"]: [],
                                cfg["nightly"]["repo"]: [],
                            }),
                            RecordlessBoundaries(self.home),
                            with_custody_text(
                                _PA_HEALTHY_STATUS_TEXT, wrong_line
                            ),
                            expected_json,
                            expected_json["state_loads"],
                            expected_json["queue"],
                            expected_json["nightly_queue"],
                            expected_json["retro_queue"],
                            expected_queue_events,
                            expected_remote_events,
                            expected_files,
                            expected_custody=expected_custody,
                            expected_custody_text=wrong_line,
                        )
                    with self.subTest(
                        expectation="omitted custody text operand"
                    ), self.assertRaisesRegex(
                        AssertionError,
                        "custody text comparison",
                    ):
                        self.assert_pa_locked_status(
                            cfg,
                            RecordlessTraceGitHub({
                                cfg["request_repo"]: [],
                                cfg["nightly"]["repo"]: [],
                            }),
                            RecordlessBoundaries(self.home),
                            expected_text,
                            expected_json,
                            expected_json["state_loads"],
                            expected_json["queue"],
                            expected_json["nightly_queue"],
                            expected_json["retro_queue"],
                            expected_queue_events,
                            expected_remote_events,
                            expected_files,
                            expected_custody=expected_custody,
                        )

    def test_custody_status_samples_clock_once_and_clamps_ages(self):
        """Fails if: one report sample or floor/clamp age arithmetic is skipped."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        queue_events = (
            (
                ("open", cfg["request_repo"]),
                ("open", cfg["nightly"]["repo"]),
            ),
            (
                ("open", cfg["request_repo"]),
                ("open", cfg["nightly"]["repo"]),
            ),
        )
        seed = self.request_seed(42)
        aggregate = seed.aggregate()
        record = self.fixture_record(aggregate, seed)
        record.update({
            "phase": "pending",
            "original_outcome": {
                "trust": "untrusted",
                "exit_code": -7,
            },
            "bindings": {
                "agents/review": {
                    "disposition": "awaiting_review_wiring",
                    "tip": "unreadable",
                    "reason": "pr_checks_failed",
                    "since": "2026-11-23T11:58:00Z",
                    "attempts": 0,
                },
            },
            "notices": {
                "agents/review": {
                    "b" * 40: {
                        "needs_pr": {
                            "state": "uncertain",
                            "since": "2026-11-23T11:59:00Z",
                        },
                        "non_owner_stall": {
                            "state": "confirmed",
                            "since": "2026-11-23T11:57:00Z",
                            "remote_identity": {
                                "repository": "private/issues",
                                "number": 17,
                            },
                        },
                    },
                },
            },
        })
        record.pop("release_proof")
        cases = (
            (
                datetime(
                    2026, 11, 23, 11, 59, 30, 900000,
                    tzinfo=timezone.utc,
                ),
                (0, 90, 30, 150),
                (
                    _CT_SIGNED_RECORD_0
                    + _CT_REVIEW_BINDING_90
                    + _CT_UNCERTAIN_NOTICE_30
                    + _CT_CONFIRMED_NOTICE_150
                ),
            ),
            (
                datetime(
                    2026, 11, 23, 13, 0,
                    tzinfo=timezone.utc,
                ),
                (3600, 3720, 3660, 3780),
                (
                    _CT_SIGNED_RECORD_3600
                    + _CT_REVIEW_BINDING_3720
                    + _CT_UNCERTAIN_NOTICE_3660
                    + _CT_CONFIRMED_NOTICE_3780
                ),
            ),
        )
        for sample, ages, custody_text in cases:
            with self.subTest(sample=sample.isoformat()):
                shutil.rmtree(self.home, ignore_errors=True)
                self.home.mkdir()
                primary = self.legacy(custody=aggregate)
                nightly = self.legacy()
                self.write_raw(self.paths.state, primary)
                self.write_raw(nightly_path, nightly)
                expected = json.loads(json.dumps(
                    _PB_TWO_NOTICE_CLASSES_CUSTODY
                ))
                expected_record = expected["records"][0]
                expected_record["age_seconds"] = ages[0]
                expected_record["bindings"][0]["age_seconds"] = ages[1]
                expected_record["notices"][0]["age_seconds"] = ages[2]
                expected_record["notices"][1]["age_seconds"] = ages[3]
                expected_files = {
                    ".local/state/hass-triage/state.json":
                        json.dumps(primary).encode(),
                    ".local/state/hass-triage/state-nightly.json":
                        json.dumps(nightly).encode(),
                    ".local/state/hass-triage/tick.lock": b"4242",
                }
                self.assert_pa_locked_status(
                    cfg,
                    RecordlessTraceGitHub({
                        cfg["request_repo"]: [],
                        cfg["nightly"]["repo"]: [],
                    }),
                    RecordlessBoundaries(self.home),
                    with_custody_text(
                        _PA_HEALTHY_STATUS_TEXT, custody_text
                    ),
                    _PA_HEALTHY_JSON_FIELDS,
                    [],
                    [],
                    [],
                    [],
                    queue_events,
                    queue_events,
                    expected_files,
                    expected_custody=expected,
                    expected_custody_text=custody_text,
                    test_clock=sample,
                )

    def test_custody_status_orders_records_across_selected_stores(self):
        """Fails if: request/nightly concatenation replaces global record order."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        request = self.request_seed(42)
        product = CustodySeed(
            repository="example/product",
            intake="request",
            producer="request:7",
            generation="g7",
            branch="refs/heads/report/7",
            archive_name="request-7",
            archive_session="request-7-seed",
            source_repository=cfg["request_repo"].lower(),
        )
        nightly = self.nightly_seed(52)
        self.write_raw(
            self.paths.state,
            self.legacy(custody=CustodySeeds((request, product)).aggregate()),
        )
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        self.write_raw(
            nightly_path,
            self.legacy(custody=nightly.aggregate()),
        )
        request_state = ht.State(self.paths.state)
        nightly_state = ht.State(nightly_path)
        expected = [
            ("example/product", "request", "request:7", "g7"),
            ("sfenton/native-home", "nightly", "nightly:52",
             "nightly-52-g1"),
            ("sfenton/native-home", "request", "request:42",
             "request-42-g1"),
        ]
        for states in (
            (("request", request_state), ("nightly", nightly_state)),
            (("nightly", nightly_state), ("request", request_state)),
        ):
            with self.subTest(stores=[store for store, _state in states]):
                projected = ht.custody_status(
                    states,
                    datetime(
                        2026, 11, 23, 12, 0,
                        tzinfo=timezone.utc,
                    ),
                )
                actual = [
                    (
                        record["repository"],
                        record["intake"],
                        record["producer"],
                        record["generation"],
                    )
                    for record in projected["records"]
                ]
                self.assertEqual(actual, expected)
                self.assertEqual(projected["faults"], [])

    def test_custody_status_orders_within_parent_at_projection_boundary(self):
        """Fails if: loader-sorted bindings or notices mask display insertion order."""
        state = mock.Mock()
        state.load_faults = []
        state.vetted_custody_records = ((
            (
                "sfenton/native-home",
                "request",
                "request:42",
                "request-42-g1",
            ),
            {
                "phase": "pending",
                "since": "2026-11-23T12:00:00Z",
                "bindings": {
                    "agents/beta": {
                        "disposition": "needs_pr",
                        "tip": "absent",
                        "since": "2026-11-23T11:59:00Z",
                    },
                    "agents/alpha": {
                        "disposition": "owner_wait",
                        "tip": "a" * 40,
                        "since": "2026-11-23T11:58:00Z",
                    },
                },
            },
            (
                (
                    ("agents/review", "b" * 40, "non_owner_stall"),
                    {
                        "state": "confirmed",
                        "since": "2026-11-23T11:57:00Z",
                        "remote_identity": {
                            "repository": "private/issues",
                            "number": 17,
                        },
                    },
                ),
                (
                    ("agents/review", "b" * 40, "needs_pr"),
                    {
                        "state": "uncertain",
                        "since": "2026-11-23T11:59:00Z",
                    },
                ),
            ),
        ),)
        projected = ht.custody_status(
            (("request", state),),
            datetime(
                2026, 11, 23, 13, 0, tzinfo=timezone.utc
            ),
        )
        record = projected["records"][0]
        self.assertEqual(
            [binding["lane"] for binding in record["bindings"]],
            ["agents/alpha", "agents/beta"],
        )
        self.assertEqual(
            [notice["fault_class"] for notice in record["notices"]],
            ["needs_pr", "non_owner_stall"],
        )

    def test_custody_status_orders_faults_and_preserves_load_order(self):
        """Fails if: custody faults concatenate stores or reorder legacy loads."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        request = {
            "version": 1,
            "records": {
                "../outside": {
                    "request": {},
                },
                "sfenton/native-home": {
                    "request": {
                        "request:42": {
                            "../generation": {
                                "phase": "release_authorized",
                            },
                        },
                    },
                },
            },
        }
        nightly_seed = self.nightly_seed(53)
        nightly = nightly_seed.aggregate()
        self.fixture_record(nightly, nightly_seed)["phase"] = "invalid"
        primary_value = self.legacy(custody=request)
        nightly_value = self.legacy(custody=nightly)
        self.write_raw(self.paths.state, primary_value)
        self.write_raw(nightly_path, nightly_value)
        request_state = ht.State(self.paths.state)
        nightly_state = ht.State(nightly_path)
        request_loads = [
            _PB_REPOSITORY_NAMESPACE_FAULT,
            _PB_GENERATION_KEY_FAULT,
        ]
        expected_loads = request_loads + [
            _PB_NIGHTLY_53_PHASE_FAULT,
        ]
        expected_custody = {
            "version": 1,
            "records": [],
            "faults": [
                _PB_NIGHTLY_53_PHASE_FAULT,
                _PB_REPOSITORY_NAMESPACE_FAULT,
                _PB_GENERATION_KEY_FAULT,
            ],
        }
        sample = datetime(
            2026, 11, 23, 12, 0, tzinfo=timezone.utc
        )
        for states in (
            (("request", request_state), ("nightly", nightly_state)),
            (("nightly", nightly_state), ("request", request_state)),
        ):
            with self.subTest(stores=[store for store, _state in states]):
                projected = ht.custody_status(states, sample)
                self.assertEqual(projected, expected_custody)
        actual_loads = request_state.load_projection("request")
        actual_loads += nightly_state.load_projection("nightly")
        self.assertEqual(actual_loads, expected_loads)
        self.assert_pa_custody_loader(
            cfg,
            expected_custody,
            expected_loads,
            storage_facts={},
        )
        expected_text = (
            0,
            "paused: False   installed: False   running: no\n"
            "self-changes: running\n"
            "auth: claude logged in\n"
            "state store request: namespace (exists yes, scope store, "
            "version 1, key unknown)\n"
            "state store request: key (exists yes, scope record, "
            "version 1, key "
            '{"repository":"sfenton/native-home","intake":"request",'
            '"producer":"request:42"})\n'
            "state store nightly: phase (exists yes, scope record, "
            "version 1, key "
            '{"repository":"sfenton/native-home","intake":"nightly",'
            '"producer":"nightly:53","generation":"nightly-53-g1"})\n'
            "queue: empty\n"
            "nightly queue: empty\n",
            "",
        )
        repositories = (
            cfg["request_repo"],
            cfg["nightly"]["repo"],
        )
        queue_events = (
            tuple(("open", repository) for repository in repositories),
            tuple(("open", repository) for repository in repositories),
        )
        expected_files = {
            ".local/state/hass-triage/state.json":
                json.dumps(primary_value).encode(),
            ".local/state/hass-triage/state-nightly.json":
                json.dumps(nightly_value).encode(),
            ".local/state/hass-triage/tick.lock": b"4242",
        }
        custody_text = (
            _CT_NIGHTLY_53_PHASE_FAULT
            + _CT_REPOSITORY_NAMESPACE_FAULT
            + _CT_GENERATION_KEY_FAULT
        )
        self.assert_pa_locked_status(
            cfg,
            RecordlessTraceGitHub({
                repository: [] for repository in repositories
            }),
            RecordlessBoundaries(self.home),
            with_custody_text(expected_text, custody_text),
            {
                "queue": [],
                "nightly_queue": [],
                "state_loads": expected_loads,
                "retro_queue": [],
            },
            expected_loads,
            [],
            [],
            [],
            queue_events,
            queue_events,
            expected_files,
            expected_custody=expected_custody,
            expected_custody_text=custody_text,
        )

    def test_pa_locked_status_rejects_remote_log_mismatches_before_call(self):
        """Fails if: a fake and its expected remote log disagree silently or reach status."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        queue_events = ((), ())
        cases = (
            (
                "log absent with expectations",
                FakeGitHub([]),
                queue_events,
            ),
            (
                "log present without expectations",
                RecordlessTraceGitHub({
                    cfg["request_repo"]: [],
                    cfg["nightly"]["repo"]: [],
                }),
                None,
            ),
        )
        with mock.patch.object(self, "main_golden") as status:
            for label, gh, remote_events in cases:
                with self.subTest(case=label), self.assertRaisesRegex(
                    AssertionError,
                    "expected remote events must match the fake event log",
                ):
                    self.assert_pa_locked_status(
                        cfg,
                        gh,
                        RecordlessBoundaries(self.home),
                        _PA_HEALTHY_STATUS_TEXT,
                        _PA_HEALTHY_JSON_FIELDS,
                        [],
                        [],
                        [],
                        [],
                        queue_events,
                        remote_events,
                        {},
                    )
            status.assert_not_called()

    def test_pa_locked_status_empty_trace_rejects_real_observer_call(self):
        """Fails if: a real observer call inside the command trace passes the empty projection gate."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        primary = self.legacy(
            custody=self.request_seed(42).aggregate()
        )
        nightly = self.legacy()
        self.write_raw(self.paths.state, primary)
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        self.write_raw(nightly_path, nightly)
        opens = (
            ("open", cfg["request_repo"]),
            ("open", cfg["nightly"]["repo"]),
        )
        expected_files = {
            ".local/state/hass-triage/state.json":
                json.dumps(primary).encode(),
            ".local/state/hass-triage/state-nightly.json":
                json.dumps(nightly).encode(),
            ".local/state/hass-triage/tick.lock": b"4242",
        }
        arguments = (
            cfg,
            RecordlessTraceGitHub({
                cfg["request_repo"]: [],
                cfg["nightly"]["repo"]: [],
            }),
            RecordlessBoundaries(self.home),
            with_custody_text(
                _PA_HEALTHY_STATUS_TEXT, _CT_REQUEST_42
            ),
            _PA_HEALTHY_JSON_FIELDS,
            [],
            [],
            [],
            [],
            (opens, opens),
            (opens, opens),
            expected_files,
        )
        kwargs = {
            "expected_custody": _PA_REQUEST_42_CUSTODY,
            "expected_custody_text": _CT_REQUEST_42,
        }
        self.assert_pa_locked_status(*arguments, **kwargs)

        real_main_golden = self.main_golden

        def with_observer_call(argv, observed_cfg, *args, **call_kwargs):
            result = real_main_golden(
                argv, observed_cfg, *args, **call_kwargs
            )
            ht._observe_custody_tree(
                ht.Paths(observed_cfg, self.home), "request:42"
            )
            return result

        with mock.patch.object(
            self, "main_golden", side_effect=with_observer_call
        ), self.assertRaisesRegex(
            AssertionError,
            "custody projection trace for status",
        ):
            self.assert_pa_locked_status(*arguments, **kwargs)

    def test_pa_loader_rejects_age_change_before_storage_or_clock(self):
        """Fails if: a P-a age change passes the legacy empty-shape guard."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        self.write_raw(
            self.paths.state,
            self.legacy(
                custody=self.request_seed(42).aggregate()
            ),
        )
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        self.write_raw(nightly_path, self.legacy())
        changed = json.loads(json.dumps(_PA_REQUEST_42_CUSTODY))
        changed["records"][0]["age_seconds"] = 1
        with mock.patch.object(ht, "State") as state, \
                mock.patch.object(ht, "now") as clock, \
                mock.patch.object(ht, "main") as status_main, \
                mock.patch.object(
                    self, "assert_pa_locked_status"
                ) as status:
            with self.assertRaisesRegex(
                AssertionError, "custody record age_seconds"
            ):
                self.assert_pa_custody_loader(cfg, changed, [])
        state.assert_not_called()
        clock.assert_not_called()
        status_main.assert_not_called()
        status.assert_not_called()

    def test_custody_pb_locked_status_rows_6_7(self):
        """Fails if: binding or same-head notice inputs change P's old status."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        queue_events = (
            (
                ("open", cfg["request_repo"]),
                ("open", cfg["nightly"]["repo"]),
            ),
            (
                ("open", cfg["request_repo"]),
                ("open", cfg["nightly"]["repo"]),
            ),
        )
        alpha_payload = {
            "disposition": "owner_wait",
            "tip": "a" * 40,
            "pull": 7,
            "reviewed_head": "b" * 40,
            "reason": "non_owner_stall",
            "since": "2026-11-23T11:58:00Z",
            "attempts": 2,
            "next": {
                "kind": "retry",
                "at": "2026-11-23T13:00:00Z",
            },
        }
        beta_payload = {
            "disposition": "needs_pr",
            "tip": "absent",
            "reason": "ai_review_failed",
            "since": "2026-11-23T11:59:00Z",
            "next": {"kind": "retry"},
        }
        uncertain_payload = {
            "state": "uncertain",
            "since": "2026-11-23T11:59:00Z",
        }
        confirmed_payload = {
            "state": "confirmed",
            "since": "2026-11-23T11:57:00Z",
            "remote_identity": {
                "repository": "private/issues",
                "number": 17,
            },
        }
        profiles = []
        seed = self.request_seed(42)
        for binding_lanes in (
            ("agents/alpha", "agents/beta"),
            ("agents/beta", "agents/alpha"),
        ):
            aggregate = seed.aggregate()
            record = self.fixture_record(aggregate, seed)
            record.update({
                "phase": "pending",
                "original_outcome": {
                    "trust": "clean_end",
                    "exit_code": 0,
                    "state": "done",
                },
                "attempts": 0,
                "reason": "reserved",
                "next": {"kind": "human"},
            })
            record.pop("release_proof")
            bindings = {
                "agents/alpha": alpha_payload,
                "agents/beta": beta_payload,
            }
            record["bindings"] = {
                lane: json.loads(json.dumps(bindings[lane]))
                for lane in binding_lanes
            }
            profiles.append((
                f"two bindings {' then '.join(binding_lanes)}",
                aggregate,
                _PB_TWO_BINDINGS_CUSTODY,
            ))
        for notice_classes in (
            ("needs_pr", "non_owner_stall"),
            ("non_owner_stall", "needs_pr"),
        ):
            aggregate = seed.aggregate()
            record = self.fixture_record(aggregate, seed)
            record.update({
                "phase": "pending",
                "original_outcome": {
                    "trust": "untrusted",
                    "exit_code": -7,
                },
                "bindings": {
                    "agents/review": {
                        "disposition": "awaiting_review_wiring",
                        "tip": "unreadable",
                        "reason": "pr_checks_failed",
                        "since": "2026-11-23T11:58:00Z",
                        "attempts": 0,
                    },
                },
            })
            record.pop("release_proof")
            payloads = {
                "needs_pr": uncertain_payload,
                "non_owner_stall": confirmed_payload,
            }
            record["notices"] = {
                "agents/review": {
                    "b" * 40: {
                        fault_class: json.loads(
                            json.dumps(payloads[fault_class])
                        )
                        for fault_class in notice_classes
                    },
                },
            }
            profiles.append((
                f"two notice classes {' then '.join(notice_classes)}",
                aggregate,
                _PB_TWO_NOTICE_CLASSES_CUSTODY,
            ))

        for label, aggregate, expected_custody in profiles:
            with self.subTest(profile=label):
                shutil.rmtree(self.home, ignore_errors=True)
                self.home.mkdir()
                primary = self.legacy(custody=aggregate)
                nightly = self.legacy()
                self.write_raw(self.paths.state, primary)
                self.write_raw(nightly_path, nightly)
                self.assert_pa_custody_loader(
                    cfg,
                    expected_custody,
                    [],
                    storage_facts={},
                )
                expected_files = {
                    ".local/state/hass-triage/state.json":
                        json.dumps(primary).encode(),
                    ".local/state/hass-triage/state-nightly.json":
                        json.dumps(nightly).encode(),
                    ".local/state/hass-triage/tick.lock": b"4242",
                }
                custody_text = (
                    _CT_TWO_BINDINGS_RECORD
                    + _CT_ALPHA_BINDING
                    + _CT_BETA_BINDING
                    if expected_custody is _PB_TWO_BINDINGS_CUSTODY
                    else (
                        _CT_SIGNED_RECORD_0
                        + _CT_REVIEW_BINDING_120
                        + _CT_UNCERTAIN_NOTICE_60
                        + _CT_CONFIRMED_NOTICE_180
                    )
                )
                self.assert_pa_locked_status(
                    cfg,
                    RecordlessTraceGitHub({
                        cfg["request_repo"]: [],
                        cfg["nightly"]["repo"]: [],
                    }),
                    RecordlessBoundaries(self.home),
                    with_custody_text(
                        _PA_HEALTHY_STATUS_TEXT, custody_text
                    ),
                    _PA_HEALTHY_JSON_FIELDS,
                    [],
                    [],
                    [],
                    [],
                    queue_events,
                    queue_events,
                    expected_files,
                    expected_custody=expected_custody,
                    expected_custody_text=custody_text,
                )

    def test_custody_pb_locked_status_rows_12_14(self):
        """Fails if: a bad sibling, bad notice or retro store changes P's old status."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        retro_path = ht.Paths(cfg, self.home, "retro-").state
        queue_events = (
            (
                ("open", cfg["request_repo"]),
                ("open", cfg["nightly"]["repo"]),
            ),
            (
                ("open", cfg["request_repo"]),
                ("open", cfg["nightly"]["repo"]),
            ),
        )
        safe_notice = {
            "state": "intent",
            "since": "2026-01-01T00:00:00Z",
        }
        bad_notice = {
            "state": "unknown",
            "since": "2026-01-01T00:00:00Z",
        }
        profiles = []
        request_42 = self.request_seed(42)
        request_43 = self.request_seed(43)
        for order in (
            (request_42, request_43),
            (request_43, request_42),
        ):
            aggregate = CustodySeeds(order).aggregate()
            self.fixture_record(aggregate, request_43)["phase"] = "invalid"
            profiles.append((
                f"bad request phase {[item.producer for item in order]}",
                self.legacy(custody=aggregate),
                self.legacy(),
                None,
                _PB_BAD_REQUEST_PHASE_CUSTODY,
                _PB_BAD_REQUEST_PHASE_STATUS_TEXT,
                [_PB_REQUEST_43_PHASE_FAULT],
            ))
        nightly_52 = self.nightly_seed(52)
        nightly_53 = self.nightly_seed(53)
        for order in (
            (nightly_52, nightly_53),
            (nightly_53, nightly_52),
        ):
            aggregate = CustodySeeds(order).aggregate()
            self.fixture_record(aggregate, nightly_53)["phase"] = "invalid"
            profiles.append((
                f"bad nightly phase {[item.producer for item in order]}",
                self.legacy(),
                self.legacy(custody=aggregate),
                None,
                _PB_BAD_NIGHTLY_PHASE_CUSTODY,
                _PB_BAD_NIGHTLY_PHASE_STATUS_TEXT,
                [_PB_NIGHTLY_53_PHASE_FAULT],
            ))
        for notice_order in (
            ("agents/safe", "agents/bad"),
            ("agents/bad", "agents/safe"),
        ):
            aggregate = request_42.aggregate()
            payloads = {
                "agents/safe": (
                    "a" * 40,
                    safe_notice,
                ),
                "agents/bad": (
                    "b" * 40,
                    bad_notice,
                ),
            }
            self.fixture_record(aggregate, request_42)["notices"] = {
                lane: {
                    payloads[lane][0]: {
                        "needs_pr": json.loads(
                            json.dumps(payloads[lane][1])
                        ),
                    },
                }
                for lane in notice_order
            }
            profiles.append((
                f"bad request notice {notice_order}",
                self.legacy(custody=aggregate),
                self.legacy(),
                None,
                _PB_BAD_REQUEST_NOTICE_CUSTODY,
                _PB_BAD_REQUEST_NOTICE_STATUS_TEXT,
                [_PB_REQUEST_NOTICE_FAULT],
            ))
        for notice_order in (
            ("agents/safe", "agents/bad"),
            ("agents/bad", "agents/safe"),
        ):
            aggregate = nightly_52.aggregate()
            payloads = {
                "agents/safe": (
                    "a" * 40,
                    safe_notice,
                ),
                "agents/bad": (
                    "b" * 40,
                    bad_notice,
                ),
            }
            self.fixture_record(aggregate, nightly_52)["notices"] = {
                lane: {
                    payloads[lane][0]: {
                        "needs_pr": json.loads(
                            json.dumps(payloads[lane][1])
                        ),
                    },
                }
                for lane in notice_order
            }
            profiles.append((
                f"bad nightly notice {notice_order}",
                self.legacy(),
                self.legacy(custody=aggregate),
                None,
                _PB_BAD_NIGHTLY_NOTICE_CUSTODY,
                _PB_BAD_NIGHTLY_NOTICE_STATUS_TEXT,
                [_PB_NIGHTLY_NOTICE_FAULT],
            ))
        profiles.append((
            "primary job and retro beside forbidden retro custody",
            self.legacy(
                custody=self.integrated_job_seeds().aggregate()
            ),
            self.legacy(),
            self.legacy(
                queue=[],
                done=[],
                custody={"version": 1, "records": {}},
            ),
            _PB_PRIMARY_RETRO_CUSTODY,
            _PB_RETRO_NAMESPACE_STATUS_TEXT,
            [_PB_RETRO_NAMESPACE_FAULT],
        ))

        for (
            label, primary, nightly, retro, expected_custody,
            expected_text, expected_state_loads,
        ) in profiles:
            with self.subTest(profile=label):
                shutil.rmtree(self.home, ignore_errors=True)
                self.home.mkdir()
                self.write_raw(self.paths.state, primary)
                self.write_raw(nightly_path, nightly)
                if retro is not None:
                    self.write_raw(retro_path, retro)
                self.assert_pa_custody_loader(
                    cfg,
                    expected_custody,
                    expected_state_loads,
                    storage_facts={},
                )
                expected_files = {
                    ".local/state/hass-triage/state.json":
                        json.dumps(primary).encode(),
                    ".local/state/hass-triage/state-nightly.json":
                        json.dumps(nightly).encode(),
                    ".local/state/hass-triage/tick.lock": b"4242",
                }
                if retro is not None:
                    expected_files[
                        ".local/state/hass-triage/state-retro.json"
                    ] = json.dumps(retro).encode()
                expected_json = {
                    "queue": [],
                    "nightly_queue": [],
                    "state_loads": expected_state_loads,
                    "retro_queue": [],
                }
                custody_text = (
                    _CT_REQUEST_42
                    + _CT_REQUEST_43_PHASE_FAULT
                    if expected_custody
                    is _PB_BAD_REQUEST_PHASE_CUSTODY
                    else (
                        _CT_NIGHTLY_52
                        + _CT_NIGHTLY_53_PHASE_FAULT
                    )
                    if expected_custody
                    is _PB_BAD_NIGHTLY_PHASE_CUSTODY
                    else (
                        _CT_REQUEST_42
                        + _CT_SAFE_JAN_NOTICE
                        + _CT_REQUEST_NOTICE_FAULT
                    )
                    if expected_custody
                    is _PB_BAD_REQUEST_NOTICE_CUSTODY
                    else (
                        _CT_NIGHTLY_52
                        + _CT_SAFE_JAN_NOTICE
                        + _CT_NIGHTLY_NOTICE_FAULT
                    )
                    if expected_custody
                    is _PB_BAD_NIGHTLY_NOTICE_CUSTODY
                    else (
                        _CT_JOB
                        + _CT_RETRO
                        + _CT_RETRO_NAMESPACE_FAULT
                    )
                )
                self.assert_pa_locked_status(
                    cfg,
                    RecordlessTraceGitHub({
                        cfg["request_repo"]: [],
                        cfg["nightly"]["repo"]: [],
                    }),
                    RecordlessBoundaries(self.home),
                    with_custody_text(
                        expected_text,
                        custody_text,
                    ),
                    expected_json,
                    expected_state_loads,
                    [],
                    [],
                    [],
                    queue_events,
                    queue_events,
                    expected_files,
                    expected_custody=expected_custody,
                    expected_custody_text=custody_text,
                )

    def test_custody_pb_locked_status_row_16(self):
        """Fails if: a record, binding or notice canary leaks into P's loader or streams."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        queue_events = (
            (
                ("open", cfg["request_repo"]),
                ("open", cfg["nightly"]["repo"]),
            ),
            (
                ("open", cfg["request_repo"]),
                ("open", cfg["nightly"]["repo"]),
            ),
        )
        profiles = []
        request_42 = self.request_seed(42)
        aggregate = request_42.aggregate()
        record = self.fixture_record(aggregate, request_42)
        record["opaque"] = {"token": "record-canary-token"}
        record["target"]["future"] = {"token": "target-canary-token"}
        profiles.append((
            "opaque record and target extras",
            aggregate,
            _PA_REQUEST_42_CUSTODY,
            [],
            _PA_HEALTHY_STATUS_TEXT,
            _PA_HEALTHY_JSON_FIELDS,
            ("record-canary-token", "target-canary-token"),
        ))

        request_43 = self.request_seed(43)
        for order in (
            (request_42, request_43),
            (request_43, request_42),
        ):
            aggregate = CustodySeeds(order).aggregate()
            bad = self.fixture_record(aggregate, request_43)
            bad.update({
                "phase": "pending",
                "bindings": {
                    "agents/canary": {
                        "disposition": "owner_wait",
                        "tip": "unreadable",
                        "reason": "binding-canary-exception",
                        "since": "2026-11-23T11:59:00Z",
                    },
                },
            })
            bad.pop("release_proof")
            profiles.append((
                f"rejected binding reason {[item.producer for item in order]}",
                aggregate,
                _PB_BAD_BINDING_CUSTODY,
                [_PB_REQUEST_43_TYPE_FAULT],
                _PB_BAD_BINDING_STATUS_TEXT,
                {
                    "queue": [],
                    "nightly_queue": [],
                    "state_loads": [_PB_REQUEST_43_TYPE_FAULT],
                    "retro_queue": [],
                },
                ("binding-canary-exception",),
            ))

        for notice_order in (
            ("agents/safe", "agents/bad"),
            ("agents/bad", "agents/safe"),
        ):
            aggregate = request_42.aggregate()
            payloads = {
                "agents/safe": {
                    "state": "intent",
                    "since": "2026-11-23T11:59:00Z",
                },
                "agents/bad": {
                    "state": "RuntimeError: notice-canary-exception",
                    "since": "2026-11-23T11:59:00Z",
                },
            }
            self.fixture_record(aggregate, request_42)["notices"] = {
                lane: {
                    ("a" if lane == "agents/safe" else "b") * 40: {
                        "needs_pr": json.loads(json.dumps(payloads[lane])),
                    },
                }
                for lane in notice_order
            }
            profiles.append((
                f"exception-like notice {notice_order}",
                aggregate,
                _PB_BAD_NOON_NOTICE_CUSTODY,
                [_PB_REQUEST_NOTICE_FAULT],
                _PB_BAD_REQUEST_NOTICE_STATUS_TEXT,
                {
                    "queue": [],
                    "nightly_queue": [],
                    "state_loads": [_PB_REQUEST_NOTICE_FAULT],
                    "retro_queue": [],
                },
                ("RuntimeError: notice-canary-exception",),
            ))

        for (
            label, aggregate, expected_custody, expected_state_loads,
            expected_text, expected_json, canaries,
        ) in profiles:
            with self.subTest(profile=label):
                shutil.rmtree(self.home, ignore_errors=True)
                self.home.mkdir()
                primary = self.legacy(custody=aggregate)
                nightly = self.legacy()
                self.write_raw(self.paths.state, primary)
                self.write_raw(nightly_path, nightly)
                self.assert_pa_custody_loader(
                    cfg,
                    expected_custody,
                    expected_state_loads,
                    storage_facts={"stored_unknown_next": ()},
                )
                loaded = ht.State(self.paths.state)
                handoff = repr(loaded.vetted_custody_records)
                diagnostics = repr(loaded.load_projection("request"))
                for canary in canaries:
                    self.assertNotIn(canary, handoff)
                    self.assertNotIn(canary, diagnostics)
                expected_files = {
                    ".local/state/hass-triage/state.json":
                        json.dumps(primary).encode(),
                    ".local/state/hass-triage/state-nightly.json":
                        json.dumps(nightly).encode(),
                    ".local/state/hass-triage/tick.lock": b"4242",
                }
                custody_text = (
                    _CT_REQUEST_42
                    if expected_custody is _PA_REQUEST_42_CUSTODY
                    else _CT_REQUEST_42
                    + _CT_REQUEST_43_TYPE_FAULT
                    if expected_custody is _PB_BAD_BINDING_CUSTODY
                    else (
                        _CT_REQUEST_42
                        + _CT_SAFE_NOON_NOTICE
                        + _CT_REQUEST_NOTICE_FAULT
                    )
                )
                stdout = self.assert_pa_locked_status(
                    cfg,
                    RecordlessTraceGitHub({
                        cfg["request_repo"]: [],
                        cfg["nightly"]["repo"]: [],
                    }),
                    RecordlessBoundaries(self.home),
                    with_custody_text(
                        expected_text,
                        custody_text,
                    ),
                    expected_json,
                    expected_state_loads,
                    [],
                    [],
                    [],
                    queue_events,
                    queue_events,
                    expected_files,
                    expected_custody=expected_custody,
                    expected_custody_text=custody_text,
                )
                for canary in canaries:
                    self.assertNotIn(canary, stdout[0])
                    self.assertNotIn(canary, stdout[1])

    def test_custody_text_groups_children_before_later_legacy_output(self):
        """Fails if: parent groups, past heads or fault order cross post-mortem output."""
        cfg = dict(self.cfg)
        cfg["schedules"] = {}
        seed = self.request_seed(42)
        template = self.fixture_record(seed.aggregate(), seed)
        first = json.loads(json.dumps(template))
        first.update({
            "phase": "pending",
            "original_outcome": {"trust": "untrusted"},
            "attempts": 0,
            "reason": "reserved",
            "next": {"kind": "human"},
            "bindings": {
                "agents/review": {
                    "disposition": "owner_wait",
                    "tip": "a" * 40,
                    "pull": 7,
                    "since": "2026-11-23T11:59:00Z",
                    "attempts": 0,
                    "next": {
                        "kind": "retry",
                        "at": "2026-11-23T13:00:00Z",
                    },
                },
            },
            "notices": {
                "agents/review": {
                    "b" * 40: {
                        "needs_pr": {
                            "state": "unsent",
                            "since": "2026-11-23T11:59:00Z",
                        },
                    },
                },
            },
        })
        first.pop("release_proof")
        second = json.loads(json.dumps(template))
        second.update({
            "phase": "pending",
            "bindings": {
                "agents/review": {
                    "disposition": "needs_pr",
                    "tip": "a" * 40,
                    "reason": "ai_review_failed",
                    "since": "2026-11-23T11:59:00Z",
                    "next": {"kind": "retry"},
                },
            },
            "notices": {
                "agents/review": {
                    "b" * 40: {
                        "needs_pr": {
                            "state": "intent",
                            "since": "2026-11-23T11:59:00Z",
                        },
                    },
                },
            },
        })
        second.pop("release_proof")
        second.pop("original_outcome")
        aggregate = {
            "version": 1,
            "records": {
                seed.repository: {
                    "request": {
                        "request:42": {
                            "request-42-l3-g1": first,
                            "request-42-l3-g2": second,
                        },
                    },
                },
            },
        }
        primary = self.legacy(custody=aggregate)
        nightly = self.legacy(
            custody={"version": 2, "records": {}}
        )
        retro = self.legacy(
            queue=[{"task": "R-60"}],
            done=[],
        )
        self.write_raw(self.paths.state, primary)
        nightly_path = ht.Paths(cfg, self.home, "nightly-").state
        self.write_raw(nightly_path, nightly)
        retro_path = ht.Paths(cfg, self.home, "retro-").state
        self.write_raw(retro_path, retro)
        expected_loads = [_L3_CUSTODY["faults"][0]]
        self.assert_pa_custody_loader(
            cfg,
            _L3_CUSTODY,
            expected_loads,
            storage_facts={},
        )
        custody_text = (
            _CT_L3_RECORD_1
            + _CT_L3_BINDING_1
            + _CT_L3_UNSENT_NOTICE
            + _CT_L3_RECORD_2
            + _CT_L3_BINDING_2
            + _CT_L3_INTENT_NOTICE
            + _CT_L3_NIGHTLY_VERSION_FAULT
        )
        expected_text = with_custody_text(_L3_STATUS_TEXT, custody_text)
        repositories = (cfg["request_repo"], cfg["nightly"]["repo"])
        opens = tuple(("open", repository) for repository in repositories)
        expected_files = {
            ".local/state/hass-triage/state.json":
                json.dumps(primary).encode(),
            ".local/state/hass-triage/state-nightly.json":
                json.dumps(nightly).encode(),
            ".local/state/hass-triage/state-retro.json":
                json.dumps(retro).encode(),
            ".local/state/hass-triage/tick.lock": b"4242",
        }
        text, _encoded = self.assert_pa_locked_status(
            cfg,
            RecordlessTraceGitHub({
                repository: [] for repository in repositories
            }),
            RecordlessBoundaries(self.home),
            expected_text,
            {
                "queue": [],
                "nightly_queue": [],
                "state_loads": expected_loads,
                "retro_queue": ["R-60"],
            },
            expected_loads,
            [],
            [],
            ["R-60"],
            (opens, opens),
            (opens, opens),
            expected_files,
            expected_custody=_L3_CUSTODY,
            expected_custody_text=custody_text,
        )
        self.assertNotIn("custody:\n", text)

    def test_custody_pb_locked_status_supplements(self):
        """Fails if: a P-b2 supplement changes P's legacy loader or status output."""
        configured = dict(self.cfg)
        configured["schedules"] = {}
        unconfigured = dict(configured)
        unconfigured["nightly"] = None
        nightly_path = ht.Paths(configured, self.home, "nightly-").state
        profiles = []
        profiles.append((
            "mixed legacy and scoped type",
            unconfigured,
            self.legacy(
                jobs=[],
                custody={"version": 1, "records": []},
            ),
            None,
            _PB_MIXED_TYPE_CUSTODY,
            [
                {"store": "request", "kind": "type", "exists": "yes"},
                _PB_SCOPED_STORE_TYPE_FAULT,
            ],
            _PB_MIXED_TYPE_STATUS_TEXT,
            {"stored_unknown_next": ()},
        ))
        profiles.append((
            "unsupported custody header",
            unconfigured,
            self.legacy(custody={"version": 2, "records": {}}),
            None,
            _PB_UNSUPPORTED_VERSION_CUSTODY,
            [_PB_UNSUPPORTED_VERSION_FAULT],
            _PB_UNSUPPORTED_VERSION_STATUS_TEXT,
            {"stored_unknown_next": ()},
        ))
        unbound = {
            "version": 1,
            "records": {
                "example/product": {
                    "request": {
                        "request:7": {
                            "g1": {
                                "phase": "unknown",
                                "since": "2026-11-23T12:00:00Z",
                                "bindings": {},
                                "notices": {
                                    "agents/bad": [],
                                    "agents/safe": {
                                        "a" * 40: {
                                            "needs_pr": {
                                                "state": "intent",
                                                "since":
                                                    "2026-11-23T12:59:00Z",
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        }
        profiles.append((
            "unbound notice prefix",
            unconfigured,
            self.legacy(custody=unbound),
            None,
            _PB_UNBOUND_CUSTODY,
            [_PB_UNBOUND_NOTICE_FAULT],
            _PB_UNBOUND_NOTICE_STATUS_TEXT,
            {
                "without_target": (
                    ("example/product", "request", "request:7", "g1"),
                ),
                "stored_unknown_next": (),
            },
        ))
        nightly_seed = self.nightly_seed(52)
        profiles.append((
            "duplicate request JSON with valid nightly",
            configured,
            '{"history":[],"history":[]}',
            self.legacy(custody=nightly_seed.aggregate()),
            _PA_NIGHTLY_52_CUSTODY,
            [{"store": "request", "kind": "parse", "exists": "yes"}],
            _PB_REQUEST_PARSE_STATUS_TEXT,
            {"stored_unknown_next": ()},
        ))
        request_seed = self.request_seed(42)
        profiles.append((
            "configured missing nightly",
            configured,
            self.legacy(custody=request_seed.aggregate()),
            None,
            _PA_REQUEST_42_CUSTODY,
            [{
                "store": "nightly",
                "kind": "not_found",
                "exists": "no",
                "installation": "unknown",
            }],
            _PB_MISSING_NIGHTLY_STATUS_TEXT,
            {"stored_unknown_next": ()},
        ))
        for reverse in (False, True):
            aggregate = request_seed.aggregate()
            good_record = self.fixture_record(aggregate, request_seed)
            generations = {
                "../generation": {"phase": "release_authorized"},
                "request-42-g1": good_record,
            }
            repositories = {
                "../outside": {"request": {}},
                "sfenton/native-home": {
                    "request": {
                        "request:42": generations,
                    },
                },
            }
            if reverse:
                generations = dict(reversed(list(generations.items())))
                repositories = {
                    "sfenton/native-home": {
                        "request": {
                            "request:42": generations,
                        },
                    },
                    "../outside": {"request": {}},
                }
            profiles.append((
                f"unbounded keys {'reversed' if reverse else 'forward'}",
                configured,
                self.legacy(custody={
                    "version": 1,
                    "records": repositories,
                }),
                self.legacy(),
                _PB_UNBOUNDED_CUSTODY,
                [
                    _PB_REPOSITORY_NAMESPACE_FAULT,
                    _PB_GENERATION_KEY_FAULT,
                ],
                _PB_UNBOUNDED_STATUS_TEXT,
                {"stored_unknown_next": ()},
            ))

        for (
            label, cfg, primary, nightly, expected_custody,
            expected_state_loads, expected_text, storage_facts,
        ) in profiles:
            with self.subTest(profile=label):
                shutil.rmtree(self.home, ignore_errors=True)
                self.home.mkdir()
                self.write_raw(self.paths.state, primary)
                if nightly is not None:
                    self.write_raw(nightly_path, nightly)
                self.assert_pa_custody_loader(
                    cfg,
                    expected_custody,
                    expected_state_loads,
                    storage_facts=storage_facts,
                )
                expected_files = {
                    ".local/state/hass-triage/state.json": (
                        primary.encode()
                        if isinstance(primary, str)
                        else json.dumps(primary).encode()
                    ),
                    ".local/state/hass-triage/tick.lock": b"4242",
                }
                if nightly is not None:
                    expected_files[
                        ".local/state/hass-triage/state-nightly.json"
                    ] = json.dumps(nightly).encode()
                repositories = (cfg["request_repo"],)
                if cfg["nightly"]:
                    repositories += (cfg["nightly"]["repo"],)
                opens = tuple(("open", repo) for repo in repositories)
                queue_events = (
                    opens,
                    opens,
                )
                expected_json = {
                    "queue": [],
                    "nightly_queue": [],
                    "state_loads": expected_state_loads,
                    "retro_queue": [],
                }
                custody_text = (
                    _CT_SCOPED_STORE_TYPE_FAULT
                    if expected_custody is _PB_MIXED_TYPE_CUSTODY
                    else _CT_UNSUPPORTED_REQUEST_VERSION_FAULT
                    if expected_custody
                    is _PB_UNSUPPORTED_VERSION_CUSTODY
                    else (
                        _CT_UNBOUND_RECORD
                        + _CT_UNBOUND_SAFE_NOTICE
                        + _CT_UNBOUND_NOTICE_FAULT
                    )
                    if expected_custody is _PB_UNBOUND_CUSTODY
                    else _CT_NIGHTLY_52
                    if expected_custody
                    is _PA_NIGHTLY_52_CUSTODY
                    else _CT_REQUEST_42
                    if expected_custody
                    is _PA_REQUEST_42_CUSTODY
                    else (
                        _CT_REQUEST_42
                        + _CT_REPOSITORY_NAMESPACE_FAULT
                        + _CT_GENERATION_KEY_FAULT
                    )
                )
                self.assert_pa_locked_status(
                    cfg,
                    RecordlessTraceGitHub({
                        repo: [] for repo in repositories
                    }),
                    RecordlessBoundaries(self.home),
                    with_custody_text(
                        expected_text,
                        custody_text,
                    ),
                    expected_json,
                    expected_state_loads,
                    [],
                    [],
                    [],
                    queue_events,
                    queue_events,
                    expected_files,
                    expected_custody=expected_custody,
                    expected_custody_text=custody_text,
                    test_clock=(
                        datetime(
                            2026, 11, 23, 13, 0,
                            tzinfo=timezone.utc,
                        )
                        if label == "unbound notice prefix"
                        else None
                    ),
                )
                if label == "configured missing nightly":
                    inventory = self.file_inventory()
                    missing = (
                        ".local/state/hass-triage/state-nightly.json"
                    )
                    self.assertNotIn(missing, inventory)
                    control_cfg = dict(cfg)
                    control_cfg["nightly"] = None
                    self.assert_pa_custody_loader(
                        control_cfg,
                        _PA_REQUEST_42_CUSTODY,
                        [],
                        storage_facts={"stored_unknown_next": ()},
                    )

    def test_recordless_request_post_launch_save_failure_preserves_disk_authority(self):
        """Fails if: request 81 save failure changes containment, prompt normalization or last committed bytes."""
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        issue = t.issue(81, created="2026-10-01T00:00:00Z")
        gh = RecordlessTraceGitHub({cfg["request_repo"]: [issue]})
        self.write_raw(self.paths.state, self.legacy(
            opaque_extension={"preserve": ["request-save", 8]}
        ))
        boundaries = RecordlessBoundaries(
            self.home,
            statuses={81: {
                "state": "blocked",
                "summary": "worker stopped",
            }},
        )
        original_save = ht.State.save
        primary_saves = 0

        def save(state):
            nonlocal primary_saves
            if state.path == self.paths.state:
                primary_saves += 1
                if primary_saves == 4:
                    raise ht.StateSaveError(state.path.name, "file_sync")
            return original_save(state)

        with mock.patch.object(
            ht.State, "save", autospec=True, side_effect=save
        ):
            result = self.main_golden(
                ["run-issue", "81"], cfg, gh, boundaries
            )

        self.assertEqual(result, (
            4,
            "",
            "error: state persistence failed during file_sync "
            "for state.json\n",
        ))
        self.assertEqual(primary_saves, 4)
        self.assertEqual(gh.events, [
            ("issue", cfg["request_repo"], 81),
            ("labels", cfg["request_repo"], 81, ("In Progress",), ()),
            ("comments", cfg["request_repo"], 81),
            ("comment", cfg["request_repo"], 81,
             "**Picked up** (triage agent)\n\n"
             "Started working on this (attempt 1). Progress shows up here as "
             "comments.\n\n<!-- hass-triage:81:pickup -->"),
            ("comments", cfg["request_repo"], 81),
            ("comment", cfg["request_repo"], 81,
             "**Stopped** (triage agent)\n\nworker stopped\n\n"
             "Reply here (or comment `/retry`) and the agent picks it up "
             "again on its next run.\n\n"
             "<!-- hass-triage:81:blocked -->"),
            ("labels", cfg["request_repo"], 81, ("Blocked",),
             ("In Progress", "Merging", "Needs Decision")),
            ("comments", cfg["request_repo"], 81),
        ])
        clone = str(self.paths.clone)
        tree = str(self.paths.worktrees / "81")
        archive = self.paths.root / "archive" / "request-81"
        self.assertEqual(boundaries.git_events, [
            (("gh", "repo", "clone", cfg["product_repo"], clone), ""),
            (("git", "-C", clone, "fetch", "-q", "origin",
              cfg["product_base"]), ""),
            (("git", "-C", clone, "checkout", "-q", "--detach",
              f"origin/{cfg['product_base']}"), ""),
            (("git", "-C", clone, "worktree", "prune"), ""),
            (("git", "-C", clone, "rev-parse", "--verify", "-q",
              "report/81"), ""),
            (("git", "-C", clone, "ls-remote", "--exit-code", "origin",
              "report/81"), ""),
            (("git", "-C", clone, "worktree", "add", tree,
              "report/81"), ""),
            (("git", "-C", tree, "diff", "--name-only",
              f"origin/{cfg['product_base']}...HEAD"), ""),
            ((sys.executable, str(ht.HERE.parent / "retro_digest.py"),
              "--task", "R-81", "--archive", str(archive), "--outcome",
              "blocked:blocked", "--attempt", "1", "--started",
              "2026-11-23T12:00:00Z"), ""),
        ])
        self.assertEqual(boundaries.launch_events, [
            (
                81,
                "hass-agents/worktrees/81",
                ELIDED_PROMPT_ARGUMENTS["request 81"],
            ),
        ])
        reopened = json.loads(self.paths.state.read_text())
        self.assertEqual(reopened["current"]["issue"], 81)
        self.assertEqual(reopened["attempts"], {"81": 1})
        self.assertEqual(reopened["history"], [])
        self.assertEqual(reopened["opaque_extension"], {
            "preserve": ["request-save", 8]
        })
        self.assertTrue(
            (self.paths.root / "archive" / "request-81" / "status.json").is_file()
        )
        expected = self.legacy(
            archive_sessions={
                "request-81": {
                    "name": "request-81",
                    "path": tree,
                    "session": "request-81-10cf3364c1d1",
                },
            },
            attempts={"81": 1},
            current={
                "archive_name": "request-81",
                "archive_session": "request-81-10cf3364c1d1",
                "attempt": 1,
                "issue": 81,
                "log": str(self.paths.log(81, 1)),
                "started": "2026-11-23T12:00:00Z",
            },
            opaque_extension={"preserve": ["request-save", 8]},
        )
        request_snapshot = {
            "number": 81,
            "title": "[Bug] Thing 81",
            "body": "It broke",
            "author": "SFenton",
            "labels": [],
            "snapshot_at": "2026-11-23T12:00:00Z",
        }
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/state.json": self.saved_bytes(expected),
            ".local/state/hass-triage/tick.lock": b"4242",
            "hass-agents/archive/request-81/status.json":
                b'{\n  "state": "blocked",\n'
                b'  "summary": "worker stopped"\n}\n',
            "hass-agents/archive/request-81/worker.log.tail":
                b"recordless launcher fixture\n",
            "hass-agents/logs/81-1.log":
                b"recordless launcher fixture\n",
            "hass-agents/requests/81.json":
                json.dumps(request_snapshot, indent=2).encode(),
            "hass-agents/status/81.json":
                b'{"state": "blocked", "summary": "worker stopped"}',
        })
        self.assertEqual(boundaries.forget_events, [])

    def test_every_seed_fixture_is_coherent_under_the_wire_contract(self):
        """Fails if: R221-1, R221-2, R221-3 or R221-4 leaves an incoherent seed fixture."""
        for scenario, fixture in self.custody_fixtures().items():
            store, seed, queue_sources, other_sessions = fixture
            aggregate = seed.aggregate()
            self.assertEqual(aggregate["version"], 1)
            for repository, intakes in aggregate["records"].items():
                self.assertEqual(repository, self.cfg["product_repo"].lower())
                for intake, producers in intakes.items():
                    for producer, generations in producers.items():
                        for generation, record in generations.items():
                            with self.subTest(
                                scenario=scenario,
                                store=store,
                                intake=intake,
                                producer=producer,
                                generation=generation,
                            ):
                                target = record["target"]
                                if producer.startswith(
                                    ("request:", "nightly:")
                                ):
                                    expected_repository = (
                                        self.cfg["request_repo"].lower()
                                        if producer.startswith("request:")
                                        else self.cfg["nightly"]["repo"].lower()
                                    )
                                    self.assertEqual(
                                        target["source_repository"],
                                        expected_repository,
                                    )
                                    self.assertEqual(
                                        intake,
                                        "nightly"
                                        if producer.startswith("nightly:")
                                        else "request",
                                    )
                                elif producer.startswith(("job:", "retro:")):
                                    self.assertNotIn(
                                        "source_repository", target
                                    )
                                    self.assertEqual(intake, "request")
                                else:
                                    self.fail(f"unexpected producer {producer!r}")
                                expected_store = (
                                    "nightly"
                                    if intake == "nightly"
                                    else "primary"
                                )
                                self.assertEqual(store, expected_store)
                                if producer.startswith("retro:"):
                                    sources = {
                                        task: (archive, queued)
                                        for task, archive, queued
                                        in queue_sources
                                    }
                                    task = producer.removeprefix("retro:")
                                    self.assertIn(task, sources)
                                    archive, queued = sources[task]
                                    self.assertIsNotNone(archive)
                                    self.assertIsNotNone(queued)
                                    self.assertEqual(
                                        target["source_archive"], archive
                                    )
                                    self.assertEqual(
                                        target["source_queued"], queued
                                    )
                                    self.assertNotIn("/", archive)
                                    self.assertNotIn("\\", archive)
                                else:
                                    self.assertNotIn(
                                        "source_archive", target
                                    )
                                    self.assertNotIn(
                                        "source_queued", target
                                    )
                                self.assertEqual(
                                    record["phase"], "release_authorized"
                                )
                                self.assertEqual(record["bindings"], {})
                                self.assertEqual(
                                    record["original_outcome"]["trust"],
                                    "clean_end",
                                )
                                self.assertEqual(
                                    record["original_outcome"]["exit_code"],
                                    0,
                                )
                                self.assertIn(
                                    record["original_outcome"]["state"],
                                    ("done", "no_changes"),
                                )
                                self.assertTrue(
                                    target["branch"].startswith(
                                        "refs/heads/"
                                    )
                                )
                                for branch in record["pre_refs"]:
                                    self.assertTrue(
                                        branch.startswith("refs/heads/")
                                    )
                                self.assertEqual(
                                    record["release_proof"],
                                    {
                                        "inventory": "positive_empty",
                                        "unlanded": "verified_none",
                                        "archive_name":
                                            target["archive_name"],
                                        "archive_session":
                                            target["archive_session"],
                                        "archive_disposition": "archived",
                                    },
                                )
                                self.assertNotIn(
                                    target["archive_session"],
                                    other_sessions,
                                )
            path = self.logical_path(store)
            self.write_raw(path, self.legacy(custody=aggregate))
            loaded = ht.State(path)
            self.assertTrue(
                loaded.writable,
                (scenario, loaded.load_faults),
            )
            self.assertEqual(
                loaded.vetted_custody_records[0][0][0],
                self.cfg["product_repo"].lower(),
            )

    def test_custody_seeded_phase_and_notice_variants_are_inert(self):
        """Fails if: a valid phase or notice state changes a full decision golden."""
        def reset():
            shutil.rmtree(self.home, ignore_errors=True)
            self.home.mkdir()
            ht._PRINTED.clear()

        single_scenarios = (
            (
                "quiet",
                self.custody_fixture("quiet request"),
                self.test_recordless_quiet_tick_has_fixed_ordered_transcript_and_opaque_bytes,
            ),
            (
                "self-change",
                self.custody_fixture("self-change pause"),
                self.test_recordless_tick_self_change_pause_stops_retro_dispatch,
            ),
            (
                "maintenance",
                self.custody_fixture("maintenance"),
                self.test_recordless_tick_routes_merging_parked_recovery_and_stored_finish,
            ),
            (
                "integrated job and retro",
                self.custody_fixture("integrated job and retro"),
                self.test_recordless_scheduled_manual_job_and_retro_reach_both_saves_and_enqueue,
            ),
            (
                "tamper",
                self.custody_fixture("tamper 71"),
                self.test_recordless_run_issue_tamper_routes_block_and_disarms_pull,
            ),
            (
                "ordinary",
                self.custody_fixture("ordinary request 70"),
                self.test_recordless_ordinary_request_finishes_successfully,
            ),
            (
                "post-launch",
                self.custody_fixture("post-launch request 81"),
                self.test_recordless_request_post_launch_save_failure_preserves_disk_authority,
            ),
        )
        for scenario, seed, golden in single_scenarios:
            for label, variant in self.custody_variants(seed):
                with self.subTest(scenario=scenario, case=label):
                    reset()
                    with self.seeded_golden(variant):
                        golden()

        for scenario, primary_seed, nightly_seed, golden in (
            (
                "priority",
                self.custody_fixture("priority request"),
                self.custody_fixture("priority nightly"),
                self.test_recordless_both_admissions_choose_priority_and_keep_fixed_bytes,
            ),
            (
                "drained",
                self.custody_fixture("drained request"),
                self.custody_fixture("drained nightly"),
                self.test_recordless_idle_primary_reads_nightly_queue_before_job_work,
            ),
        ):
            for producer, seed in (
                ("primary", primary_seed),
                ("nightly", nightly_seed),
            ):
                for label, variant in self.custody_variants(seed):
                    with self.subTest(
                        scenario=scenario, producer=producer, case=label
                    ):
                        reset()
                        with self.seeded_golden(
                            variant
                            if producer == "primary"
                            else primary_seed,
                            variant
                            if producer == "nightly"
                            else nightly_seed,
                        ):
                            golden()

        for label, variant in self.custody_variants(
            self.custody_fixture("valid acknowledgement")
        ):
            with self.subTest(scenario="acknowledgement", case=label):
                reset()
                self.assert_valid_acknowledgement_pair(variant)

        direct_scenarios = (
            (
                "request 63 path absent",
                self.custody_fixture("request 63 path absent"),
                self.assert_request_63_path_absent_no_drop,
            ),
            (
                "old retro pre-drop",
                self.custody_fixture("old retro pre-drop"),
                self.assert_old_retro_tree_pre_drop_pair,
            ),
            (
                "stopped retro",
                self.custody_fixture("identified stopped retro pair"),
                self.assert_identified_stopped_retro_pair,
            ),
        )
        for scenario, seed, assertion in direct_scenarios:
            for label, variant in self.custody_variants(seed):
                with self.subTest(scenario=scenario, case=label):
                    reset()
                    assertion(variant)

    def test_seeded_quiet_tick_preserves_fixed_legacy_transcript_and_bytes(self):
        """Fails if: a valid installed request seed changes quiet selection, saves or bytes."""
        with self.seeded_golden(self.custody_fixture("quiet request")):
            self.test_recordless_quiet_tick_has_fixed_ordered_transcript_and_opaque_bytes()

    def test_seeded_priority_admission_preserves_both_intake_goldens(self):
        """Fails if: valid request and nightly seeds change dry priority, siblings or order."""
        with self.seeded_golden(
            self.custody_fixture("priority request"),
            self.custody_fixture("priority nightly"),
        ):
            self.test_recordless_both_admissions_choose_priority_and_keep_fixed_bytes()

    def test_seeded_drained_intakes_preserve_nightly_idle_callback(self):
        """Fails if: valid seeds change the drained request or nightly idle transcript."""
        with self.seeded_golden(
            self.custody_fixture("drained request"),
            self.custody_fixture("drained nightly"),
        ):
            self.test_recordless_idle_primary_reads_nightly_queue_before_job_work()

    def test_seeded_self_change_pause_preserves_stopped_retro_dispatch(self):
        """Fails if: an installed historical request seed changes the self-change stop or pause."""
        with self.seeded_golden(
            self.custody_fixture("self-change pause")
        ):
            self.test_recordless_tick_self_change_pause_stops_retro_dispatch()

    def test_seeded_maintenance_preserves_all_reached_request_paths(self):
        """Fails if: valid request 62-67 seeds change a maintenance branch or byte."""
        with self.seeded_golden(self.custody_fixture("maintenance")):
            self.test_recordless_tick_routes_merging_parked_recovery_and_stored_finish()

    def test_seeded_job_retro_and_regression_preserve_the_integrated_golden(self):
        """Fails if: valid job and retro seeds change any integrated legacy effect."""
        with self.seeded_golden(
            self.custody_fixture("integrated job and retro")
        ):
            self.test_recordless_scheduled_manual_job_and_retro_reach_both_saves_and_enqueue()

    def test_seeded_tamper_preserves_block_and_disarm_effects(self):
        """Fails if: a valid request 71 seed changes tamper classification or effects."""
        with self.seeded_golden(self.custody_fixture("tamper 71")):
            self.test_recordless_run_issue_tamper_routes_block_and_disarms_pull()

    def test_seeded_ordinary_request_preserves_positive_empty_cleanup(self):
        """Fails if: a valid request 70 seed changes no-changes cleanup or bytes."""
        with self.seeded_golden(
            self.custody_fixture("ordinary request 70")
        ):
            self.test_recordless_ordinary_request_finishes_successfully()

    def test_seeded_manual_controls_preserve_precedence_and_preview(self):
        """Fails if: a valid request 72 seed adds work to busy, paused or preview paths."""
        with self.seeded_golden(
            self.custody_fixture("manual controls 72")
        ):
            self.test_recordless_manual_busy_paused_and_asymmetric_preview_modes()

    def test_seeded_locked_status_preserves_both_read_only_formats(self):
        """Fails if: a valid primary seed changes status or the retained malformed sibling."""
        with self.seeded_golden(
            self.custody_fixture("locked status 72")
        ):
            self.test_recordless_status_formats_under_real_lock_with_independent_queue_error(
                _PA_REQUEST_72_CUSTODY
            )

    def test_seeded_post_launch_save_failure_preserves_last_committed_bytes(self):
        """Fails if: a valid request 81 seed changes save failure authority or output."""
        with self.seeded_golden(
            self.custody_fixture("post-launch request 81")
        ):
            self.test_recordless_request_post_launch_save_failure_preserves_disk_authority()

    def assert_valid_acknowledgement_pair(self, seed):
        old = "a" * 40
        head = "b" * 40
        cfg = dict(self.cfg)
        cfg["workflow_base"] = cfg["product_base"]
        cfg["nightly"] = None
        primary = self.legacy()
        expected_primary = seeded_expected(primary, seed)
        self.write_raw(self.paths.state, expected_primary)
        base = self.paths.state_dir / "workflow-base.json"
        pause = self.paths.state_dir / "SELF_CHANGE_PAUSED"
        pause_info = self.paths.state_dir / "SELF_CHANGE_PAUSED.json"
        gh = RecordlessAckGitHub(
            {cfg["request_repo"]: []}, old, head
        )
        boundaries = RecordlessAckBoundaries(self.home, old, head)
        land = self.paths.root / "land" / cfg["product_repo"].split("/")[-1]
        (land / ".git").mkdir(parents=True, exist_ok=True)

        def seed_pause():
            base.parent.mkdir(parents=True, exist_ok=True)
            base.write_text(json.dumps({"main": old}, indent=2, sort_keys=True))
            pause.write_text("unexpected workflow base move\n")
            pause_info.write_text(json.dumps({
                "base": "main",
                "sha": head,
                "expected": old,
                "moves": [],
                "when": "tick",
                "at": "2026-11-23T12:00:00Z",
            }))

        seed_pause()
        accepted = self.main_golden(["ack-base", head], cfg, gh, boundaries)
        self.assertEqual(accepted, (
            0,
            "Accepted bbbbbbbbbb as the workflow base; "
            "SELF_CHANGE_PAUSED cleared.\n",
            "",
        ))
        seed_pause()
        verified = self.main_golden(
            ["ack-verified"], cfg, gh, boundaries
        )
        self.assertEqual(verified, (
            0,
            "Accepted 1 PR merges: #17; head bbbbbbbbbb; "
            "SELF_CHANGE_PAUSED cleared.\n",
            "",
        ))
        self.assertEqual(gh.events, [
            ("requirements", cfg["product_repo"], "main"),
            ("commit_record", cfg["product_repo"], head),
            ("commit_pulls", cfg["product_repo"], head),
            ("checks", cfg["product_repo"], head),
        ])
        self.assertEqual(boundaries.launch_events, [])
        self.assertEqual(boundaries.forget_events, [])
        ack_log = {
            "at": "2026-11-23T12:00:00Z",
            "contexts": ["pr-checks"],
            "from": old,
            "mode": "verified",
            "prs": [17],
            "session": "owner",
            "to": head,
        }
        self.assertEqual(self.file_bytes(), {
            ".local/state/hass-triage/ack.lock": b"",
            ".local/state/hass-triage/ack-log.jsonl":
                (json.dumps(ack_log, sort_keys=True) + "\n").encode(),
            ".local/state/hass-triage/state.json":
                json.dumps(expected_primary).encode(),
            ".local/state/hass-triage/tick.lock": b"4242",
            ".local/state/hass-triage/workflow-base.json":
                json.dumps({"main": head}, indent=2, sort_keys=True).encode(),
        })

    def test_valid_primary_acknowledgements_match_recordless_and_seeded_inputs(self):
        """Fails if: a valid seeded primary changes either acknowledgement's base or audit effects."""
        for label, seed in (
            ("recordless", None),
            (
                "seeded",
                self.custody_fixture("valid acknowledgement"),
            ),
        ):
            with self.subTest(case=label):
                for name in ("ack.lock", "ack-log.jsonl"):
                    (self.paths.state_dir / name).unlink(missing_ok=True)
                self.assert_valid_acknowledgement_pair(seed)

    def assert_identified_stopped_retro_pair(self, seed):
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        source = self.paths.root / "archive" / "held-input"
        source.mkdir(parents=True)
        queue = [{
            "task": "held-retro",
            "archive": str(source),
            "queued": "2026-11-22T12:00:00Z",
            "triggers": ["owner_correction"],
            "touched": [],
        }]
        primary = seeded_expected(
            self.legacy(opaque_extension={"preserve": ["stop-pair", 1]}),
            seed,
        )
        retro = self.legacy(queue=queue, done=[])
        self.write_raw(self.paths.state, primary)
        self.write_raw(
            ht.Paths(cfg, self.home, "retro-").state,
            retro,
        )
        pause = self.paths.state_dir / "SELF_CHANGE_PAUSED"
        pause.parent.mkdir(parents=True, exist_ok=True)
        pause.write_text("identified stop fixture\n")
        runner = self.runner(FakeGitHub([]))
        with mock.patch("sys.stdout", new=io.StringIO()) as out, \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            self.assertIsNone(runner.run_retro())
        self.assertEqual(out.getvalue(), (
            "retro: paused (PAUSED file); queued post-mortems wait\n"
        ))
        self.assertEqual(err.getvalue(), "")
        self.assertEqual(self.commands, [])
        self.assertEqual(self.prompts, [])
        self.assertEqual(self.paths.state.read_bytes(), json.dumps(primary).encode())
        self.assertEqual(
            ht.Paths(cfg, self.home, "retro-").state.read_bytes(),
            json.dumps(retro).encode(),
        )

    def test_identified_stopped_retro_recordless_control(self):
        """Fails if: an identified queue item is not stopped before Git or dispatch."""
        self.assert_identified_stopped_retro_pair(None)

    def test_identified_stopped_retro_seeded_pair(self):
        """Fails if: a valid stopped-retro seed changes stop, pause or suppressed dispatch."""
        self.assert_identified_stopped_retro_pair(
            self.custody_fixture("identified stopped retro pair")
        )

    def assert_request_63_path_absent_no_drop(self, seed):
        tree = self.paths.worktrees / "63"
        label = "request-63"
        initial = self.legacy(
            archive_sessions={
                label: {
                    "name": label,
                    "session": "request-63-installed",
                    "path": str(tree),
                },
            },
            opaque_extension={"preserve": ["request-63", 1]},
        )
        self.write_raw(
            self.paths.state,
            seeded_expected(initial, seed),
        )
        runner = self.runner(FakeGitHub([]))
        archive_gate = mock.Mock(return_value=True)
        runner.archive_before_change = archive_gate
        with mock.patch.object(
            runner, "_drop_worktree"
        ) as drop, mock.patch.object(
            ht.t3launch, "forget"
        ) as forget:
            self.assertTrue(runner.cleanup(63))
        archive_gate.assert_called_once_with(
            label, 63, tree, label, "request-63-installed",
            evidence=True, digest=False,
        )
        drop.assert_not_called()
        forget.assert_not_called()
        expected = self.legacy(
            opaque_extension={"preserve": ["request-63", 1]}
        )
        self.assertEqual(
            self.paths.state.read_bytes(),
            self.expected_seeded_bytes(expected, seed),
        )

    def test_request_63_path_absent_reaches_no_drop_recordless(self):
        """Fails if: absent request 63 unexpectedly enters the worktree drop boundary."""
        self.assert_request_63_path_absent_no_drop(None)

    def test_request_63_path_absent_reaches_no_drop_seeded(self):
        """Fails if: a valid request 63 seed causes an absent-tree cleanup to drop."""
        self.assert_request_63_path_absent_no_drop(
            self.custody_fixture("request 63 path absent")
        )

    def assert_old_retro_tree_pre_drop_pair(self, seed):
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        task = "old-retro"
        key = f"retro-{task}"
        tree = self.paths.worktrees / key
        tree.mkdir(parents=True)
        source = self.paths.root / "archive" / "old-input"
        source.mkdir(parents=True)
        queued = "2026-11-22T12:00:00Z"
        queue = [{
            "task": task,
            "archive": str(source),
            "queued": queued,
            "triggers": ["owner_correction"],
            "touched": [],
        }]
        prior = {
            "name": "retro-old-input",
            "session": "retro-old-input-prior",
            "path": str(tree),
        }
        primary = self.legacy(
            archive_sessions={key: prior},
            opaque_extension={"preserve": ["old-retro", 4]},
        )
        self.write_raw(
            self.paths.state,
            seeded_expected(primary, seed),
        )
        retro = self.legacy(queue=queue, done=[])
        self.write_raw(
            ht.Paths(cfg, self.home, "retro-").state,
            retro,
        )
        status = {
            "state": "done",
            "summary": "old tree retro completed",
        }
        gh = RecordlessTraceGitHub({cfg["request_repo"]: []})
        boundaries = RecordlessBoundaries(
            self.home,
            statuses={key: (status, task)},
        )
        archive_calls = []

        def archive_before(
                _runner, label, n, path, name, session,
                evidence=False, digest=False,
        ):
            archive_calls.append((
                label, n, path, name, session, evidence, digest
            ))
            return True

        with mock.patch.object(
            ht.Runner, "archive_before_change",
            autospec=True, side_effect=archive_before,
        ):
            result = self.main_golden(["tick"], cfg, gh, boundaries)

        self.assertEqual(result, (0, "", ""))
        self.assertEqual(boundaries.launch_events, [(
            key,
            "hass-agents/worktrees/retro-old-retro",
            ELIDED_PROMPT_ARGUMENTS["retro"],
        )])
        expected_session = "retro-old-retro-bc9b9b0ea1cf"
        self.assertEqual(archive_calls, [
            (
                key, key, tree, "retro-old-input",
                "retro-old-input-prior", True, False,
            ),
            (
                key, key, tree, "retro-old-input",
                expected_session, False, False,
            ),
        ])
        removes = [
            index for index, (args, _cwd) in enumerate(
                boundaries.git_events
            )
            if isinstance(args, tuple)
            and "worktree" in args
            and "remove" in args
        ]
        adds = [
            index for index, (args, _cwd) in enumerate(
                boundaries.git_events
            )
            if isinstance(args, tuple)
            and "worktree" in args
            and "add" in args
            and "-B" in args
        ]
        self.assertEqual(len(removes), 2)
        self.assertEqual(len(adds), 1)
        self.assertLess(removes[0], adds[0])
        self.assertGreater(removes[1], adds[0])
        self.assertEqual(boundaries.persistence_events, [
            ("drop", "hass-agents/worktrees/retro-old-retro"),
            ("drop", "hass-agents/worktrees/retro-old-retro"),
        ])
        self.assertEqual(boundaries.forget_events, [
            (tree, self.home),
            (tree, self.home),
        ])
        expected_primary = self.legacy(
            archive_sessions={
                key: {
                    "name": "retro-old-input",
                    "session": expected_session,
                    "path": str(tree),
                },
            },
            history=[{
                "at": "2026-11-23T12:00:00Z",
                "detail": task,
                "issue": key,
                "outcome": "retro:done",
            }],
            opaque_extension={"preserve": ["old-retro", 4]},
        )
        expected_retro = self.legacy(
            queue=[],
            done=[{
                "task": task,
                "archive": str(source),
                "queued": queued,
                "triggers": ["owner_correction"],
                "touched": [],
                "archive_name": "retro-old-input",
                "archive_session": expected_session,
                "outcome": "done",
                "finished": "2026-11-23T12:00:00Z",
                "summary": "old tree retro completed",
            }],
        )
        self.assertEqual(
            self.paths.state.read_bytes(),
            self.expected_seeded_bytes(expected_primary, seed),
        )
        self.assertEqual(
            ht.Paths(cfg, self.home, "retro-").state.read_bytes(),
            self.saved_bytes(expected_retro),
        )
        reopened_primary = ht.State(self.paths.state)
        self.assertEqual(
            reopened_primary.data,
            seeded_expected(expected_primary, seed),
        )

    def test_old_retro_tree_reaches_pre_drop_recordless_control(self):
        """Fails if: an old retro tree is not dropped before add with a separate final drop."""
        self.assert_old_retro_tree_pre_drop_pair(None)

    def test_old_retro_tree_reaches_pre_drop_seeded_pair(self):
        """Fails if: a valid identified retro seed changes old-tree pre-drop or final-drop effects."""
        self.assert_old_retro_tree_pre_drop_pair(
            self.custody_fixture("old retro pre-drop")
        )


if __name__ == "__main__":
    unittest.main()
