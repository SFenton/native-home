# TestFlight

> **What:** how S+H gets to TestFlight: the App Store Connect record, privacy manifests, export compliance and the upload script. **Read when:** uploading a build, adding an API that needs a privacy-manifest reason, or adding a bundle.

## The record

- App Store Connect app **S+H**, Apple ID `6828605693`, bundle `com.sfenton.home`, SKU `com.sfenton.home`, team `3Q9X8JX23S`.
- **Internal TestFlight only** for now (no external testers, no App Review submission).
- **No Watch app is shipped or registered** (owner, 2026-10-29). Do not register `com.sfenton.home.watchkitapp`; `FentonHomeWatch` stays out of the `FentonHome` scheme until the watchOS scope in [watchos.md](../../design/apple/watchos.md) is built.

## Upload

```bash
python3 tools/bg_run.py testflight -- tools/release/testflight_upload.sh [--tag ios/v…] [--build N]
```

The script runs `xcodegen`, archives (`FentonHome`, Release, `generic/platform=iOS`) in a `devcap` build hold, then `xcodebuild -exportArchive` with [`ExportOptions-testflight.plist`](../../../tools/release/ExportOptions-testflight.plist) (`app-store-connect`, `destination: upload`, automatic signing), which signs and uploads in one step. The version comes from `versioning.py build-settings` for the newest `ios/v*` tag (override with `--tag`); the build number defaults to `date -u +%Y%m%d%H%M` and must grow per upload. The tag only names the version: `HassGitSHA` is the checkout's HEAD. The script never creates or pushes a tag. Signing needs the Apple ID signed in to Xcode; a password, 2FA or Keychain prompt is the owner's step. `tools/release/ios_ipa_build.sh` (CI) makes the same archive but exports an IPA without uploading. CI does not call it for TestFlight: `testflight_queue.py` calls it per version with `--source <worktree of the tag>`, `--no-devcap` is for an unshared runner, and `--asc-key-path/--asc-key-id/--asc-issuer-id` (or `ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID`) switch signing and upload to the App Store Connect API key (all three or none).

## From a merge to TestFlight (CI)

Owner flow (2026-10-29): **merge to `main` → `pr-checks` passes → version bump (tag `ios/v<YYMM.DD.NN>`) → build → upload to internal TestFlight.** Only a version bump reaches TestFlight; no push, pull request or branch builds or uploads.

Uploads start on `main` (the port landed there on 2026-11-05, #308; release tags live there). The runner's `testflight_after` dispatches only for a landing on the product base (`main`).

```
merge to main ─► pr-checks (push to main) ─ success ─► version-bump (workflow_run, head_sha) ─► tag ios/v… ─► dispatch ios-release-build
                                            │                                                                       │
                                  failed/cancelled: no bump                                    testflight_queue.py run: oldest pending first
                                                                                               archive + upload (API key) ─► ledger tag ios/tf/<version>
```

| Step | Workflow | Notes |
|---|---|---|
| CI gate | [`pr-checks.yml`](../../../.github/workflows/pr-checks.yml) | Already existed: repo checks, Python tool tests (`tools/run_tool_tests.sh`, now including the release-queue and workflow lint tests), Release build, `swift test`. Runs on the self-hosted runners (Release build on the MacBook, `swift test`, repo checks and tool tests on the Mac mini, the scope and aggregate jobs on either Mac), so no macOS-hosted minutes. |
| Bump | [`version-bump.yml`](../../../.github/workflows/version-bump.yml) | `workflow_run` of `pr-checks` on `main`, only when it concluded `success` for a `push`, and bumps exactly `workflow_run.head_sha`. Gated by `HASS_VERSION_BUMP_ENABLED`. After pushing the tag it dispatches `ios-release-build.yml` (only when `HASS_TESTFLIGHT_ENABLED` is `true`; a tag pushed with `GITHUB_TOKEN` starts no workflow). It does not dispatch `ios-release.yml` (owner, 2026-10-29), which runs only by hand or on a manually pushed tag. |
| Build and upload | [`ios-release-build.yml`](../../../.github/workflows/ios-release-build.yml) | `workflow_dispatch` only (inputs `version_tag`, `dry_run`), `main` only, job in the `testflight` environment, gated by `HASS_TESTFLIGHT_ENABLED` (a dry run is exempt). Writes the API key from the environment secrets to a temp file, runs `testflight_queue.py run`, deletes the key in an `always()` step. |

### Runner dispatch (owner, 2026-11-03)

TestFlight upload of a reviewed build is autonomous. After the triage runner lands a lane or a product pull request that changed `apple/**` on `main`, it dispatches `ios-release-build.yml` itself (`gh workflow run ... --ref main`, from `hass_triage.py`, never from an agent: their deny list keeps `gh workflow*`). It dispatches at most once an hour, only when `tools/triage/config.json` `testflight_autoupload` is true (default) and the repository variable `HASS_TESTFLIGHT_ENABLED` is `true`; each dispatch is in the runner state (`testflight`), `hass_triage.py status` and the weekly digest. The queue is idempotent, so this wake-up beside the bump's own is harmless. Certificates, profiles and the App Store Connect key stay owner-only.

### Ordering guarantee

GitHub keeps **one pending run per concurrency group**: when a third run queues behind a running one, the second is cancelled even with `cancel-in-progress: false`. So neither the bump nor the build may depend on "one run per merge". They do not:

- **Bump.** A bump is a function of the commit: "tag `head_sha` if app files changed since the previous tag". The newest CI-passed head always covers every merge before it (their commits are its ancestors, and notes are the net since the previous tag), and an older head that runs late is skipped as `behind_previous_tag`. So a dropped pending bump loses no change, only a version number that never existed. A failed or cancelled `pr-checks` run on a head (`pr-checks` cancels superseded `main` runs) bumps nothing; the next green head does.
- **Build.** The queue is in git. `testflight_queue.py run` lists every `ios/v*` tag reachable from `main` that has **no `ios/tf/<version>` ledger tag** newer than the newest ledger entry, and uploads them **oldest first**, one at a time (each from a worktree of its own tag, so the app source is that tag's, the tooling the workflow commit's). After each upload it writes the annotated ledger tag `ios/tf/<version>` (message `build=<N> …`) and pushes it, then re-reads tags, so a version that landed meanwhile joins the same run. The dispatch only *wakes* a run; a dropped wake-up is harmless because the next run (or a manual one) catches up. A failed upload stops the loop with the failing exit code: nothing newer jumps the queue, and the next run starts with the same version.
- **Build numbers** are `max(UTC YYYYMMDDHHMM, newest ledgered build + 1)`, so they strictly rise in upload order even if the clock is behind or two uploads share a minute.
- **Why a tag ledger and not an App Store Connect query:** it needs no extra API code or token scope, is visible in `git tag -l 'ios/tf/*' -n1`, and is written with the workflow token. If an upload succeeds and the ledger push then fails (retried 3 times), the next run uploads that version again with a higher build number: a duplicate build, never a missing one. The ledger tags match no workflow trigger (`ios-release.yml` listens to `ios/v*`).
- **First enable:** with no ledger the queue starts at the dispatched `version_tag` (the bump passes its tag), or the newest tag; the 2610.xx tags that exist now are history and are never uploaded. To re-upload a version, delete its `ios/tf/<version>` tag (`git push origin :refs/tags/ios/tf/<version>`) and dispatch.

### Cost

The release workflows run on the self-hosted MacBook runner `hass-mac` (owner decision 2026-10-28; `pr-checks` `repo-checks` and `swift-test`, `tool-tests` and nightly coverage run on the Mac mini runner `host-mini` since 2026-10-30, and `scope` and the aggregate run on either Mac since 2026-11-05, [ci](../../workflow/ci.md#the-runners)), so there are no GitHub-hosted macOS minutes (billed at 10x on a private repo, and an `xcode-27` runner label like FestivalNativeApps uses is not available to a user-owned repo). Cost is the Mac's time: about 20 to 30 minutes of one runner slot per version (archive, upload), and it queues behind other jobs while the Mac is asleep. No new CI workflow was added: `pr-checks` is the gate, and a separate macOS CI would only repeat it. The bump itself takes seconds.

### Dry run

Actions → ios-release-build → Run workflow on `main` with **dry_run** ticked (works before any secret or variable exists): it fetches tags, lists what is pending and prints the `xcodebuild archive` / `-exportArchive` commands per version with the build number each would get; it uploads nothing and writes no tag. Locally: `python3 tools/release/testflight_queue.py pending` and `… run --dry-run --no-fetch`; the script alone: `tools/release/testflight_upload.sh --dry-run --tag ios/v…`.

### Enabling it (owner checklist)

Done by the owner; nothing here creates, reads or prints a key. State on 2026-10-29: variable `HASS_VERSION_BUMP_ENABLED=true` already exists; no `HASS_TESTFLIGHT_ENABLED`, no secrets, no environments.

1. App Store Connect → Users and Access → Integrations → App Store Connect API → generate a **Team Key** with the **Admin** role (cloud-managed signing needs it). Download `AuthKey_<KEYID>.p8` **once**; note the Key ID and the Issuer ID shown above the table.
2. Create the environment and restrict it to `main`:
   `gh api -X PUT repos/$PRIVATE_APP_REPO/environments/testflight`, then
   `gh api -X PUT repos/$PRIVATE_APP_REPO/environments/testflight -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'` and
   `gh api -X POST repos/$PRIVATE_APP_REPO/environments/testflight/deployment-branch-policies -f name=main`.
   (Environments on a private repo need a paid GitHub plan. If GitHub refuses, say so: the fallback is repository secrets with the workflow's own `github.ref == 'refs/heads/main'` guard, which a branch workflow could bypass, so it is weaker.)
3. Store the three secrets in the environment:
   `gh secret set ASC_KEY_ID --env testflight --repo "$PRIVATE_APP_REPO"`, `gh secret set ASC_ISSUER_ID --env testflight --repo "$PRIVATE_APP_REPO"`, `gh secret set ASC_PRIVATE_KEY --env testflight --repo "$PRIVATE_APP_REPO" < AuthKey_<KEYID>.p8`. Then delete the `.p8` from Downloads (or keep it in your password manager).
4. Mac runner: the runner's user must be logged in with an unlocked login keychain ([ci](../../workflow/ci.md), "Keychain on the runner"); with the API key, Apple holds the distribution certificate, the Mac only needs an Apple Development identity for the archive, which Xcode reuses or creates.
5. Dry run once (above), then `gh variable set HASS_TESTFLIGHT_ENABLED --body true --repo "$PRIVATE_APP_REPO"`. The next green merge that changes app code bumps, builds and uploads. `HASS_VERSION_BUMP_ENABLED` is already `true`; set it to `false` to stop tagging, `HASS_TESTFLIGHT_ENABLED` to `false` to stop uploading (tags keep being cut; the queue uploads them when re-enabled, oldest first, starting after the newest ledger entry).
6. To upload the very first build now without waiting for a merge: Run workflow with no inputs on `main` (newest tag), or with `version_tag`.

### Default server variable

The sign-in Server field's default is the repository **variable** `HASS_DEFAULT_SERVER` (not a secret), set by the owner: `gh variable set HASS_DEFAULT_SERVER --body <server url> --repo "$PRIVATE_APP_REPO"`. `ios-release.yml` and `ios-release-build.yml` read it as `vars.HASS_DEFAULT_SERVER` into the environment, and `ios_ipa_build.sh` / `testflight_upload.sh` pass it to `xcodebuild` as the build setting `HASS_DEFAULT_SERVER` when it is non-empty (it lands in Info.plist, [auth](auth.md#default-server-hass_default_server)). Unset, new installs start with a blank Server field; existing installs keep their server from the Keychain. No signing, key or profile step reads it.

## Privacy manifests

`PrivacyInfo.xcprivacy` sits in the source folder of the app and of each extension (`Apps/iOS`, `Apps/Widgets`, `Apps/NotificationService`, `Apps/NotificationContent`); xcodegen adds each to its target's resources. Statically linked packages (HassCore, HassDesign, HassUI) call the APIs inside every bundle that links them, so each bundle declares what its linked code uses. All declare `NSPrivacyTracking` false, no tracking domains and no collected data types: data goes only to the person's own Home Assistant server, never to us.

| Category | Reason | Why | Bundles |
|---|---|---|---|
| UserDefaults | `CA92.1`, `1C8F.1` | App's own settings; the app group `group.com.sfenton.home` shared with the extensions (`ActivityAppIconStore`, `RememberedAccount`) | all four |
| File timestamp | `C617.1` | Modification dates of files in the app's own container: image cache trimming (`ImagePipeline`), backdrop render pruning, MetricKit payload ordering, the executable's build date | app, widgets (link HassDesign) |

**Disk space is not declared and not read (owner, 2026-10-29).** The app used to report a `Storage` sensor to Home Assistant. Apple's only display reason, `85F4.1`, says disk space "may not be sent off-device" except over the local network to another of the person's devices, never over the Internet; the other reasons (`E174.1` check before writing, `7D9E.1` user bug report, `B728.1` health research) do not fit. So the sensor was removed, and `test_no_bundle_reads_or_declares_disk_space` keeps the manifests clean while the scan fails if a disk-space API comes back. Bringing the sensor back needs an owner decision and a reason Apple accepts.

Add a category here and in the manifests when code starts calling another required-reason API (system boot time, active keyboards, user-defaults in a new bundle). `tools/release/tests/test_testflight.py` fails when a manifest, its tracking-free content or the encryption key disappears, or when code uses an undeclared category (below).

### Required-reason APIs

**The guard.** `RequiredReasonScan` in `tools/release/tests/test_testflight.py` (run by `tools/run_tool_tests.sh`, so by CI) maps each shipped bundle to the Swift it compiles: its app folder (plus `Apps/Shared` for the app and widgets), and the transitive closure of the Swift package targets that `project.yml` links, resolved through `Package.swift` target dependencies (no hard-coded list). It strips comments, matches the symbols in `CATEGORY_PATTERNS` (Apple's five categories, Swift and C spellings) and fails with file, symbol, bundle and missing category if the bundle's manifest lacks that category. Tests, the Watch app and `HassTestSupport` are not scanned. It checks the category, not the reason: pick the reason by hand from Apple's page. A new symbol Apple adds goes in `CATEGORY_PATTERNS`. Matching is by name, so an unrelated `creationDate` also trips it; rename or narrow the pattern.

**What Apple provides** ([list](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)): Apple states a missing reason produces an email after upload processing (ITMS-91053), and App Store Connect rejects the build. We found no Apple tool that flags a missing API reason before upload: the Xcode Organizer "Generate Privacy Report" aggregates the privacy manifests of the app and its SDKs (data types, tracking domains), it does not scan code. `xcodebuild -exportArchive` with `destination: upload` and `altool --validate-app` validate signing and bundle structure and do not report ITMS-91053 (unverified here; the email is the first signal we know of). A binary-level `nm -u` scan of the archive would also work but adds nothing the source scan misses, so it is not in `testflight_upload.sh`.

**What others do:** a grep of source or dependency binaries against Apple's list, as in JetBrains' [required-reason finder](https://kotlinlang.org/docs/apple-privacy-manifest.html) and the community [`xcprivacy`](https://pypi.org/project/xcprivacy/) linter (beta, third party); otherwise projects rely on Apple's email. `home-assistant/iOS` and `FestivalNativeApps` track no `PrivacyInfo.xcprivacy` at all.

## Export compliance

`ITSAppUsesNonExemptEncryption: false` in the app's Info (`apple/project.yml`): the app uses only the system's standard HTTPS/TLS, which is exempt, so App Store Connect does not ask about encryption on every build.
