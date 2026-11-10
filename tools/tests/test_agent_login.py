"""``tools/agent_login.py``: the agent account's login is a non-secret setting; empty means today's behaviour."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import agent_login  # noqa: E402


class AgentLoginTests(unittest.TestCase):
    def test_empty_config_resolves_to_nothing_and_only_the_owner_is_own(self):
        """Fails if: an unset agent_login lets any login but SFenton count as the agents' own (the empty case must equal today's)."""
        for configured in (None, "", "   ", 5, "bad login!", "-x"):
            self.assertEqual(agent_login.resolve(configured), "", configured)
        self.assertEqual(agent_login.own_logins(None), frozenset({"sfenton"}))
        self.assertTrue(agent_login.is_own("SFenton", None))
        for other in ("sh-agent", "", None, 3):
            self.assertFalse(agent_login.is_own(other, None), other)
            self.assertFalse(agent_login.is_agent(other, None), other)

    def test_the_config_value_is_used_and_no_process_setting_overrides_it(self):
        """Fails if: resolve() reads anything but the config value (a FENTON_AGENT_LOGIN prefix would then widen the author gates)."""
        self.assertEqual(agent_login.resolve("sh-agent"), "sh-agent")
        with mock.patch.dict(os.environ, {"FENTON_AGENT_LOGIN": "stranger"}):
            self.assertEqual(agent_login.resolve("sh-agent"), "sh-agent")
            self.assertEqual(agent_login.resolve(""), "")
            self.assertFalse(agent_login.is_own("stranger", ""))
            self.assertEqual(agent_login.own_logins(None), frozenset({"sfenton"}))

    def test_the_agent_login_is_own_but_a_third_login_is_not(self):
        """Fails if: the configured login is refused, a third login is accepted, or the comparison is case-sensitive (GitHub's is not)."""
        self.assertTrue(agent_login.is_own("sh-agent", "sh-agent"))
        self.assertTrue(agent_login.is_own("SH-Agent", "sh-agent"))
        self.assertTrue(agent_login.is_own("SFenton", "sh-agent"))
        self.assertFalse(agent_login.is_own("mallory", "sh-agent"))
        self.assertTrue(agent_login.is_agent("sh-agent", "sh-agent"))
        self.assertFalse(agent_login.is_agent("SFenton", "sh-agent"))

    def test_the_owner_as_agent_login_counts_as_none(self):
        """Fails if: naming the owner as the agent turns the owner into an 'agent' (is_agent true for SFenton)."""
        self.assertEqual(agent_login.resolve("sfenton"), "")
        self.assertFalse(agent_login.is_agent("SFenton", "SFenton"))

    def test_configured_reads_the_config_file_and_tolerates_junk(self):
        """Fails if: a missing, unreadable, non-object or non-string agent_login raises instead of reading as empty."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            self.assertEqual(agent_login.configured(path), "")
            for text, want in (('{"agent_login": "sh-agent"}', "sh-agent"), ('{"agent_login": ""}', ""), ('{"agent_login": 3}', ""),
                               ("{}", ""), ("[]", ""), ("not json", "")):
                path.write_text(text)
                self.assertEqual(agent_login.configured(path), want, text)

    def test_the_shipped_config_leaves_agent_login_empty(self):
        """Fails if: tools/triage/config.json ships a non-empty agent_login (the owner fills it; the repo never names the account)."""
        config = Path(__file__).resolve().parents[1] / "triage" / "config.json"
        self.assertEqual(json.loads(config.read_text())["agent_login"], "")


if __name__ == "__main__":
    unittest.main()
