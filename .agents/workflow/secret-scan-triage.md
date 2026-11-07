# Secret scan triage (2026-11-07)

`tools/history_secret_scan.sh` ran gitleaks 8.30.1 over every commit on every branch and found 22 matches. Each was triaged from its structure only; no value was printed or recorded. All 22 are false positives, so the repository needs no history rewrite and no rotation. Their fingerprints are in the root `.gitleaksignore`, which the script passes with `--gitleaks-ignore-path` ([ci](ci.md)).

| Rule | Count | Where | Why it is a false positive |
|---|---|---|---|
| generic-api-key | 7 | tool tests (`test_ha_change`, `test_hass_triage`, `test_jev_sections`, `test_products_cache`) | short placeholder fixtures |
| generic-api-key | 4 | app build-info and About settings tests (history only) | a git SHA fixture under the build-info key |
| generic-api-key | 2 | scan item model tests | idempotency keys the test asserts |
| generic-api-key | 2 | a mockup proposal page | a mockup card id |
| private-key | 3 | `test_redact` | one is labelled fake; the PEM block is built in code |
| jwt | 2 | `test_redact` | a token with only a `sub` claim and a short signature, not a Home Assistant token |
| curl-auth-header | 2 | `test_redact` | a fake bearer value |

**Adding a line to `.gitleaksignore`:** triage the new finding the same way (structure and context, never the value), add its fingerprint (`commit:file:rule:line`), and extend this table.

## `.gitleaks.toml` (path-scoped allowlist)

`.gitleaksignore` fingerprints include the commit sha, so they do not match in a fresh orphan snapshot (the public release). The root `.gitleaks.toml` extends the default rules (`useDefault = true`) and allowlists the triaged fake test fixtures by file and rule, with no global allowlist. `tools/history_secret_scan.sh` passes it with `--config`; gitleaks also auto-discovers it at the repo root.

Rules for adding an entry:

- One `[[allowlists]]` block per file, with `targetRules` listing only the rule ids that fired, and a `^`-anchored, escaped path to that one file (no directory globs, no unanchored paths).
- A comment pointing here, after triaging the finding by structure only (never print the value); a reviewer must approve the entry.
- Scan from the repo root with relative paths (`gitleaks git`, or `gitleaks dir .`). The anchors fail closed for an absolute-path `dir` scan, which reports findings instead of staying silent.
- `test_history_secret_scan.py` checks that every path exists and that nothing is allowlisted globally.
