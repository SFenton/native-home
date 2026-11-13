---
name: secret-scan-triage
description: Triages a secret-scan finding and, for a false positive, adds a narrowly scoped allow entry. Use when gitleaks or tools/history_secret_scan.sh reports a finding.
---
# Secret scan triage

> **What:** how to judge one secret-scan finding and record a false positive. **Read when:** `tools/history_secret_scan.sh` or a gitleaks run reports a finding. Rules: [security](../../workflow/security.md#credentials).

1. **Judge from structure and context only.** Read the rule id, the file and the line's shape. Never print, copy or record the matched value.
2. **A real secret** is reported to the owner for rotation. Add no allow entry and do not rewrite history yourself.
3. **A false positive in history** gets its fingerprint (`commit:file:rule:line`) in the root `.gitleaksignore`.
4. **A false positive in a fixture file** also gets a path-scoped entry in the root `.gitleaks.toml`:
   - one `[[allowlists]]` block per file;
   - `targetRules` lists only the rule ids that fired;
   - the path is `^`-anchored and escaped, naming that one file: no directory globs, no global allowlist;
   - a comment says why the finding is a false positive.
5. **Scan again** from the repo root with relative paths: `tools/history_secret_scan.sh` exits 0 on a clean scan.
6. **Test.** Run `python3 -m unittest tools.tests.test_history_secret_scan`: every allowlisted path exists and nothing is allowlisted globally.
7. **Review.** The entry lands only with a reviewer's approval; say in the pull request what the finding is and why it is safe.
