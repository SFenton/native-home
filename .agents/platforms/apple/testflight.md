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

Owner flow (2026-11-09): **merge to `main` → version bump (tag `ios/v<YYMM.DD.NN>`) → signed release IPA as a workflow artifact, and, when `HASS_TESTFLIGHT_ENABLED` is `true`, the upload to internal TestFlight.** One workflow, [`ios-release.yml`](../../../.github/workflows/ios-release.yml), does the first two on a push to `main`; it runs no tests, no coverage and no simulator and does not wait for `pr-checks` (the pull request that landed passed it at the merge gate). Only a version bump produces an IPA or reaches TestFlight; no pull request or other branch builds or uploads.

Uploads start on `main` (the port landed there on 2026-11-05, #308; release tags live there). The runner's `testflight_after` dispatches only for a landing on the product base (`main`).

```
push to main ─► ios-release.yml / bump (ubuntu, no secrets) ─► tag ios/v… (skipped: no app change, already tagged, behind)
                                          │
                                          ├─► ios-release.yml / ipa (hosted macOS, environment release-signing)
                                          │      temp keychain + 2 certificates, archive + export ─► artifact FentonHome-<version> (30 days)
                                          │
                                          └─► (HASS_TESTFLIGHT_ENABLED=true) dispatch ios-release-build ─► testflight_queue.py run:
                                                 oldest pending first, archive + upload (API key) ─► ledger tag ios/tf/<version>
```

| Step | Workflow | Notes |
|---|---|---|
| Merge gate | [`pr-checks.yml`](../../../.github/workflows/pr-checks.yml) | Runs on the pull request and on the push to `main`; it gates the merge, not the release. The release pipeline starts from the same push in parallel and does not wait for it. |
| Bump | [`ios-release.yml`](../../../.github/workflows/ios-release.yml) job `bump` | `push` to `main` (and "Run workflow"). Tags `GITHUB_SHA` with `versioning.py bump --push`; always on (it needs no secrets). Dispatches `ios-release-build.yml` for the new tag only when `HASS_TESTFLIGHT_ENABLED` is `true` (a tag pushed with `GITHUB_TOKEN` starts no workflow). Outputs the tag, empty when nothing was bumped. "Run workflow" with `tag` rebuilds that existing tag without bumping; `force` bumps without app changes. |
| Signed IPA | `ios-release.yml` job `ipa` | Only when a tag came out and `HOSTED_MACOS` is `on`. GitHub-hosted `xcode-27` runner (`HOSTED_XCODE_LABEL`, `HOSTED_DEVELOPER_DIR`), job in the `release-signing` environment (main only), `contents: read`. Temporary keychain with the two certificates, the Admin API key in a temp file, `tools/release/ios_ipa_build.sh` (hosted mode, no devcap), then `actions/upload-artifact` of the IPA and dSYMs; an `always()` step deletes the keychain, p12 files and key. Until the secrets exist it fails with an error naming them. The IPA is **not** attached to the GitHub Release: the repository is public and release assets are anonymous and permanent. |
| Build and upload | [`ios-release-build.yml`](../../../.github/workflows/ios-release-build.yml) | `workflow_dispatch` only (inputs `version_tag`, `dry_run`), `main` only, job in the `testflight` environment, gated by `HASS_TESTFLIGHT_ENABLED` (a dry run is exempt). Writes the API key from the environment secrets to a temp file, runs `testflight_queue.py run`, deletes the key in an `always()` step. |

### Runner dispatch (owner, 2026-11-03)

TestFlight upload of a reviewed build is autonomous. After the triage runner lands a lane or a product pull request that changed `apple/**` on `main`, it dispatches `ios-release-build.yml` itself (`gh workflow run ... --ref main`, from `hass_triage.py`, never from an agent: their deny list keeps `gh workflow*`). It dispatches at most once an hour, only when `tools/triage/config.json` `testflight_autoupload` is true (default) and the repository variable `HASS_TESTFLIGHT_ENABLED` is `true`; each dispatch is in the runner state (`testflight`), `hass_triage.py status` and the weekly digest. The queue is idempotent, so this wake-up beside the bump's own is harmless. Certificates, profiles and the App Store Connect key stay owner-only.

### Ordering guarantee

GitHub keeps **one pending run per concurrency group**: when a third run queues behind a running one, the second is cancelled even with `cancel-in-progress: false`. So neither the bump nor the build may depend on "one run per merge". They do not:

- **Bump.** A bump is a function of the commit: "tag `head_sha` if app files changed since the previous tag". The newest CI-passed head always covers every merge before it (their commits are its ancestors, and notes are the net since the previous tag), and an older head that runs late is skipped as `behind_previous_tag`. So a dropped pending bump loses no change, only a version number that never existed. A failed or cancelled `pr-checks` run on a head (`pr-checks` cancels superseded `main` runs) bumps nothing; the next green head does.
- **Build.** The queue is in git. `testflight_queue.py run` lists every `ios/v*` tag reachable from `main` that has **no `ios/tf/<version>` ledger tag** newer than the newest ledger entry, and uploads them **oldest first**, one at a time (each from a worktree of its own tag, so the app source is that tag's, the tooling the workflow commit's). After each upload it writes the annotated ledger tag `ios/tf/<version>` (message `build=<N> …`) and pushes it, then re-reads tags, so a version that landed meanwhile joins the same run. The dispatch only *wakes* a run; a dropped wake-up is harmless because the next run (or a manual one) catches up. A failed upload stops the loop with the failing exit code: nothing newer jumps the queue, and the next run starts with the same version.
- **Build numbers** are `max(UTC YYYYMMDDHHMM, newest ledgered build + 1)`, so they strictly rise in upload order even if the clock is behind or two uploads share a minute.
- **Why a tag ledger and not an App Store Connect query:** it needs no extra API code or token scope, is visible in `git tag -l 'ios/tf/*' -n1`, and is written with the workflow token. If an upload succeeds and the ledger push then fails (retried 3 times), the next run uploads that version again with a higher build number: a duplicate build, never a missing one. The ledger tags match no workflow trigger (`ios-release.yml` starts only on a push to `main`).
- **First enable:** with no ledger the queue starts at the dispatched `version_tag` (the bump passes its tag), or the newest tag; the 2610.xx tags that exist now are history and are never uploaded. To re-upload a version, delete its `ios/tf/<version>` tag (`git push origin :refs/tags/ios/tf/<version>`) and dispatch.

### Cost

`ios-release-build.yml` (TestFlight) runs on the self-hosted MacBook runner `hass-mac` (owner decision 2026-10-28), about 20 to 30 minutes of one runner slot per version, queuing behind other jobs while the Mac is asleep. The signed IPA job of `ios-release.yml` runs on a GitHub-hosted macOS runner (the `xcode-27` image, as the `pr-checks` macOS jobs), so it costs hosted macOS minutes (free on a public repository) and not the Mac's time. The bump takes seconds.

### Dry run

Actions → ios-release-build → Run workflow on `main` with **dry_run** ticked (works before any secret or variable exists): it fetches tags, lists what is pending and prints the `xcodebuild archive` / `-exportArchive` commands per version with the build number each would get; it uploads nothing and writes no tag. Locally: `python3 tools/release/testflight_queue.py pending` and `… run --dry-run --no-fetch`; the script alone: `tools/release/testflight_upload.sh --dry-run --tag ios/v…`.

### Enabling it (owner checklist)

Done by the owner; nothing here creates, reads or prints a key. State on 2026-10-29: no `HASS_TESTFLIGHT_ENABLED`, no secrets, no environments. (`HASS_VERSION_BUMP_ENABLED` no longer exists as a switch: the bump in `ios-release.yml` always runs; the stale variable can be deleted.)

1. App Store Connect → Users and Access → Integrations → App Store Connect API → generate a **Team Key** with the **Admin** role (cloud-managed signing needs it). Download `AuthKey_<KEYID>.p8` **once**; note the Key ID and the Issuer ID shown above the table.
2. Create the environment and restrict it to `main`:
   `gh api -X PUT repos/$PRIVATE_APP_REPO/environments/testflight`, then
   `gh api -X PUT repos/$PRIVATE_APP_REPO/environments/testflight -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'` and
   `gh api -X POST repos/$PRIVATE_APP_REPO/environments/testflight/deployment-branch-policies -f name=main`.
   (Environments on a private repo need a paid GitHub plan. If GitHub refuses, say so: the fallback is repository secrets with the workflow's own `github.ref == 'refs/heads/main'` guard, which a branch workflow could bypass, so it is weaker.)
3. Store the three secrets in the environment:
   `gh secret set ASC_KEY_ID --env testflight --repo "$PRIVATE_APP_REPO"`, `gh secret set ASC_ISSUER_ID --env testflight --repo "$PRIVATE_APP_REPO"`, `gh secret set ASC_PRIVATE_KEY --env testflight --repo "$PRIVATE_APP_REPO" < AuthKey_<KEYID>.p8`. Then delete the `.p8` from Downloads (or keep it in your password manager).
4. Mac runner: the runner's user must be logged in with an unlocked login keychain ([ci](../../workflow/ci.md), "Keychain on the runner"); with the API key, Apple holds the distribution certificate, the Mac only needs an Apple Development identity for the archive, which Xcode reuses or creates.
5. Dry run once (above), then `gh variable set HASS_TESTFLIGHT_ENABLED --body true --repo "$PRIVATE_APP_REPO"`. The next merge that changes app code bumps, builds and uploads. Set `HASS_TESTFLIGHT_ENABLED` to `false` to stop uploading (tags keep being cut; the queue uploads them when re-enabled, oldest first, starting after the newest ledger entry). Tagging itself has no switch.
6. To upload the very first build now without waiting for a merge: Run workflow with no inputs on `main` (newest tag), or with `version_tag`.

### Release pipeline: owner checklist

Done by the owner; no agent creates, reads or prints a certificate, a key or a profile ([signing guard](../../workflow/agent-roster.md)). The `bump` job needs none of this and already runs; the `ipa` job fails with `ios-release cannot sign` naming every secret still missing, and the rest of this list is what clears it. Why this recipe: the research note `hosted-ios-signing` (in `build/research`, not tracked; its finding is that an API key alone mints orphan certificates on a fresh runner) (nothing ran on a hosted runner with real certificates before the first post-merge run, which is the probe).

1. **Environment.** Create `release-signing` and limit it to `main`, so the workflow of a pushed branch cannot read the secrets: Settings → Environments → New environment → Deployment branches → Selected branches → `main`. Or with `gh api` as in the TestFlight list below (`.../environments/release-signing`, `deployment_branch_policy[custom_branch_policies]=true`, then `.../deployment-branch-policies -f name=main`).
2. **Apple Distribution certificate.** On the MacBook, Keychain Access → login → My Certificates → "Apple Distribution: … (3Q9X8JX23S)" (expand it: the certificate **and** its private key) → Export… → `.p12` with a password. Then `base64 -i dist.p12 | gh secret set APPLE_DISTRIBUTION_P12_BASE64 --env release-signing`, `gh secret set APPLE_DISTRIBUTION_P12_PASSWORD --env release-signing` (type the password), and delete `dist.p12`.
3. **Apple Development certificate.** The same for one "Apple Development: …" identity of the team (the one the MacBook runner uses, or a dedicated CI identity, which limits the blast radius): `APPLE_DEVELOPMENT_P12_BASE64` and `APPLE_DEVELOPMENT_P12_PASSWORD`. Why two: an automatically signed archive signs with Development and the export re-signs with Distribution. A Development profile needs at least one registered device on the team.
4. **API key.** App Store Connect → Users and Access → Integrations → a Team Key with the **Admin** role (a role cannot be changed after creation; reuse the TestFlight key if it is Admin): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (the `.p8` contents) as secrets of the **`release-signing`** environment too (the `testflight` environment's copies are separate).
5. **Revoke stray certificates.** In the developer portal (Certificates), revoke the "Created via API" ones left by earlier experiments before the first run, or Apple's certificate cap may already be reached.
6. **First run.** Merge anything that changes app code, or Actions → ios-release → Run workflow with `force`. Check the log for "2 valid identities", the artifact `FentonHome-<version>` on the run page, and that the portal's certificate list shows **no new** "Created via API" entry. If the archive or export reports "no profile", add the app ids in the portal or fall back to manual signing (research option C).
7. **Yearly.** A distribution or development certificate lasts one year. Before it expires create a new one, export it as above and update the two secrets; an expired one makes the identity check fail (fewer than two identities) or sends Xcode to cloud signing, which can mint an orphan certificate.

Repository variables: `HOSTED_MACOS` must be `on` (the one switch for every hosted macOS job, `pr-checks` included; the `ipa` job is skipped without it). Optional: `HOSTED_XCODE_LABEL` and `HOSTED_DEVELOPER_DIR` (the same ones `pr-checks` uses; the defaults are `xcode-27` and Xcode 27.1).

- **Server default (once).** If `HASS_DEFAULT_SERVER` exists as a repository variable, copy its value into a `testflight` environment secret of the same name (`gh secret set HASS_DEFAULT_SERVER --env testflight`) and delete the variable (`gh variable delete HASS_DEFAULT_SERVER`). The signed IPA artifact of `ios-release.yml` never carries it.

### Default server variable

The sign-in Server field's default is the **secret** `HASS_DEFAULT_SERVER` of the `testflight` environment, set by the owner: `gh secret set HASS_DEFAULT_SERVER --env testflight --repo "$PRIVATE_APP_REPO"`. Never a repository variable: the repository is public, a variable is printed in plain text by a step's `env:` block, and it would also be compiled into a downloadable artifact. Only `ios-release-build.yml` (TestFlight, not public) reads it, as `secrets.HASS_DEFAULT_SERVER`, which GitHub masks in logs; the hosted `ios-release.yml` IPA never receives it, so the artifact IPA starts with a blank Server field (a lint test enforces both). The scripts still print `***` for it in a dry run, and `ios_ipa_build.sh` / `testflight_upload.sh` pass it to `xcodebuild` as the build setting `HASS_DEFAULT_SERVER` when it is non-empty (it lands in Info.plist, [auth](auth.md#default-server-hass_default_server)). Unset, new installs start with a blank Server field; existing installs keep their server from the Keychain. No signing, key or profile step reads it.

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
