# TestFlight

> **What:** how S+H gets to TestFlight: the App Store Connect record, privacy manifests, export compliance and the upload script. **Read when:** uploading a build, adding an API that needs a privacy-manifest reason, or adding a bundle.

## The record

- App Store Connect app **S+H**, Apple ID `6828605693`, bundle `com.sfenton.home`, SKU `com.sfenton.home`, team `3Q9X8JX23S`.
- **Internal TestFlight only** for now (no external testers, no App Review submission).
- **No Watch app is shipped or registered** (owner, 2026-10-29). Do not register `com.sfenton.home.watchkitapp`; `FentonHomeWatch` stays out of the `FentonHome` scheme until the watchOS scope in [watchos.md](../../design/apple/watchos.md) is built.

## Upload (manual fallback)

The release pipeline uploads every version itself ([below](#from-a-merge-to-testflight-ci)). This script is the owner's manual local fallback, for a build the pipeline cannot make (a branch build, the pipeline disabled, a first upload before the secrets exist):

```bash
python3 tools/bg_run.py testflight -- tools/release/testflight_upload.sh [--tag ios/v…] [--build N]
```

The script runs `xcodegen`, archives (`FentonHome`, Release, `generic/platform=iOS`) in a `devcap` build hold, then `xcodebuild -exportArchive` with [`ExportOptions-testflight.plist`](../../../tools/release/ExportOptions-testflight.plist) (`app-store-connect`, `destination: upload`, automatic signing), which signs and uploads in one step. The version comes from `versioning.py build-settings` for the newest `ios/v*` tag (override with `--tag`); the build number defaults to `date -u +%Y%m%d%H%M` and must grow per upload. The tag only names the version: `HassGitSHA` is the checkout's HEAD. The script never creates or pushes a tag. Signing needs the Apple ID signed in to Xcode; a password, 2FA or Keychain prompt is the owner's step. `--source <dir>` builds another checkout, `--no-devcap` is for an unshared machine, and `--asc-key-path/--asc-key-id/--asc-issuer-id` (or `ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID`) switch signing and upload to the App Store Connect API key (all three or none). `tools/release/ios_ipa_build.sh` is the pipeline's script: it makes the archive and the IPA, and with `--upload` sends that archive to TestFlight.

## From a merge to TestFlight (CI)

Owner flow (2026-11-10): **merge to `main` → version bump (tag `ios/v<YYMM.DD.NN>`) → signed release IPA as a workflow artifact → the same archive uploaded to internal TestFlight.** One workflow, [`ios-release.yml`](../../../.github/workflows/ios-release.yml), does all of it on a push to `main`; it runs no tests, no coverage and no simulator and does not wait for `pr-checks` (the pull request that landed passed it at the merge gate). Only a version bump produces an IPA or reaches TestFlight; no pull request or other branch builds or uploads. There is **no switch variable and no gate**: every bumped version is uploaded (the owner rejected a `HASS_TESTFLIGHT_ENABLED` variable as one more thing to forget).

```
push to main ─► ios-release.yml / bump (ubuntu, no secrets) ─► tag ios/v… (skipped: no app change, already tagged, behind)
                                          │
                                          └─► ios-release.yml / ipa (hosted macOS, environment release-signing)
                                                 temp keychain + 2 certificates, archive + export ─► artifact FentonHome-<version> (30 days)
                                                 ─► ios_ipa_build.sh --upload: -exportArchive of the SAME archive, destination upload ─► TestFlight
```

| Step | Workflow | Notes |
|---|---|---|
| Merge gate | [`pr-checks.yml`](../../../.github/workflows/pr-checks.yml) | Runs on the pull request and on the push to `main`; it gates the merge, not the release. The release pipeline starts from the same push in parallel and does not wait for it. |
| Bump | [`ios-release.yml`](../../../.github/workflows/ios-release.yml) job `bump` | `push` to `main` (and "Run workflow"). Tags `GITHUB_SHA` with `versioning.py bump --push`; always on (it needs no secrets) and dispatches nothing. Outputs the tag, empty when nothing was bumped. "Run workflow" with `tag` rebuilds that existing tag without bumping; `force` bumps without app changes. |
| Signed IPA | `ios-release.yml` job `ipa` | Only when a tag came out and `HOSTED_MACOS` is `on`. GitHub-hosted `xcode-27` runner (`HOSTED_XCODE_LABEL`, `HOSTED_DEVELOPER_DIR`), job in the `release-signing` environment (main only), `contents: read`. Temporary keychain with the two certificates, the Admin API key in a temp file, `tools/release/ios_ipa_build.sh` (hosted mode, no devcap), then `actions/upload-artifact` of the IPA and dSYMs. The IPA is **not** attached to the GitHub Release: the repository is public and release assets are anonymous and permanent. |
| TestFlight upload | `ios-release.yml` job `ipa`, step "Upload to TestFlight" | After the artifact is saved: `ios_ipa_build.sh TAG BUILD --upload`, a second `xcodebuild -exportArchive` on the archive the build step left, with [`ExportOptions-testflight.plist`](../../../tools/release/ExportOptions-testflight.plist) (`destination: upload`), `-allowProvisioningUpdates` and the API key, under the idle watchdog (300 s on a hosted runner). No variable gates it; a failure fails the job. The step summary says `uploaded to TestFlight: <version> (<build>)`. An `always()` step last deletes the keychain, p12 files and key. |

**Retry.** An upload that failed leaves the signed IPA artifact in place. Actions → ios-release → Run workflow on `main` with `tag` = `ios/v<version>` rebuilds that tag and uploads it again with a new build number (the build number is the UTC `YYYYMMDDHHMM`, so it grows). A build number App Store Connect already has is refused, which is why a retry rebuilds instead of re-sending the old archive.

**Pause.** `gh workflow disable ios-release.yml` stops the bump, the build and the upload; `gh workflow enable ios-release.yml` resumes. A merge made while it is disabled bumps with the next push after re-enabling (a bump is a function of the commit, see below).

### Dropped runs lose nothing

GitHub keeps **one pending run per concurrency group**: when a third run queues behind a running one, the second is cancelled even with `cancel-in-progress: false`. So the bump must not depend on "one run per merge". It does not: a bump is a function of the commit, "tag `head_sha` if app files changed since the previous tag". The newest head always covers every merge before it (their commits are its ancestors, and notes are the net since the previous tag), and an older head that runs late is skipped as `behind_previous_tag`. A dropped pending bump loses no change, only a version number that never existed. Uploads follow the tags the pipeline cut: each version builds once, in order of the runs, with a build number that rises with the clock.

### Cost

The whole pipeline runs on a GitHub-hosted macOS runner (the `xcode-27` image, as the `pr-checks` macOS jobs), so it costs hosted macOS minutes (free on a public repository) and not the Mac's time; the upload adds a few minutes to the `ipa` job. The bump takes seconds. There is no self-hosted runner in the release path any more.

### Dry run

How to test the pipeline without shipping. `ios-release.yml` has no **dry_run** ticked option (the retired TestFlight workflow had one), so a dry run is local, and a real run always ships:

- `tools/release/ios_ipa_build.sh ios/v<version> <build> --dry-run` prints the archive and export commands without running them.
- `tools/release/ios_ipa_build.sh ios/v<version> <build> --upload --dry-run` prints the TestFlight upload `xcodebuild -exportArchive` command (no key is read, nothing is sent).
- `tools/release/testflight_upload.sh --dry-run --tag ios/v…` does the same for the manual script.
- The workflow's own checks run in `pr-checks` as lint tests (`tools/release/tests/test_release_workflows.py`): the upload step's order and absence of a gate, the secrets, the retired path.
- To rehearse on the runner, "Run workflow" with `tag` rebuilds an existing version and uploads it again (a new build number, so it is a real upload to the Internal group); to stop anything shipping, `gh workflow disable ios-release.yml` first.

### Release pipeline: owner checklist

Done by the owner; no agent creates, reads or prints a certificate, a key or a profile ([signing guard](../../workflow/agent-roster.md)). The `bump` job needs none of this and already runs; the `ipa` job fails with `ios-release cannot sign` naming every secret still missing, and the rest of this list is what clears it. Why this recipe: the research note `hosted-ios-signing` (in `build/research`, not tracked; its finding is that an API key alone mints orphan certificates on a fresh runner) (nothing ran on a hosted runner with real certificates before the first post-merge run, which is the probe).

1. **Environment.** Create `release-signing` and limit it to `main`, so the workflow of a pushed branch cannot read the secrets: Settings → Environments → New environment → Deployment branches → Selected branches → `main`. Or with `gh api -X PUT repos/$PRIVATE_APP_REPO/environments/release-signing -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'`, then `gh api -X POST repos/$PRIVATE_APP_REPO/environments/release-signing/deployment-branch-policies -f name=main`.
2. **Apple Distribution certificate.** On the MacBook, Keychain Access → login → My Certificates → "Apple Distribution: … (3Q9X8JX23S)" (expand it: the certificate **and** its private key) → Export… → `.p12` with a password. Then `base64 -i dist.p12 | gh secret set APPLE_DISTRIBUTION_P12_BASE64 --env release-signing`, `gh secret set APPLE_DISTRIBUTION_P12_PASSWORD --env release-signing` (type the password), and delete `dist.p12`.
3. **Apple Development certificate.** The same for one "Apple Development: …" identity of the team (the one the MacBook runner uses, or a dedicated CI identity, which limits the blast radius): `APPLE_DEVELOPMENT_P12_BASE64` and `APPLE_DEVELOPMENT_P12_PASSWORD`. Why two: an automatically signed archive signs with Development and the export re-signs with Distribution. A Development profile needs at least one registered device on the team.
4. **API key.** App Store Connect → Users and Access → Integrations → a Team Key with the **Admin** role (a role cannot be changed after creation; cloud-managed signing and the upload need Admin): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (the `.p8` contents) as secrets of the **`release-signing`** environment. The same key signs the profiles and uploads the build. Then delete the `.p8` from Downloads (or keep it in your password manager).
5. **Revoke stray certificates.** In the developer portal (Certificates), revoke the "Created via API" ones left by earlier experiments before the first run, or Apple's certificate cap may already be reached.
6. **First run.** Merge anything that changes app code, or Actions → ios-release → Run workflow with `force`. Check the log for "2 valid identities", the artifact `FentonHome-<version>` on the run page, the step summary line `uploaded to TestFlight: <version> (<build>)` (the build shows in TestFlight after App Store Connect has processed it, and the Internal group receives it automatically), and that the portal's certificate list shows **no new** "Created via API" entry. If the archive or export reports "no profile", add the app ids in the portal or fall back to manual signing (research option C).
7. **Yearly.** A distribution or development certificate lasts one year. Before it expires create a new one, export it as above and update the two secrets; an expired one makes the identity check fail (fewer than two identities) or sends Xcode to cloud signing, which can mint an orphan certificate.

There is nothing else to set: no `HASS_TESTFLIGHT_ENABLED`, no `testflight` environment, no self-hosted runner. (If the stale `HASS_TESTFLIGHT_ENABLED` or `HASS_VERSION_BUMP_ENABLED` variable still exists, delete it.) Repository variables: `HOSTED_MACOS` must be `on` (the one switch for every hosted macOS job, `pr-checks` included; the `ipa` job is skipped without it). Optional: `HOSTED_XCODE_LABEL` and `HOSTED_DEVELOPER_DIR` (the same ones `pr-checks` uses; the defaults are `xcode-27` and Xcode 27.1).

### Default server (manual uploads only)

The sign-in Server field's default (`HASS_DEFAULT_SERVER`) is **blank in the hosted artifact build and in the pipeline's TestFlight upload**: the pipeline never receives it, and a lint test enforces that. It is set only for a manual `tools/release/testflight_upload.sh` run, from the owner's own shell (`HASS_DEFAULT_SERVER=… tools/release/testflight_upload.sh`), never from a workflow secret. Never a repository variable: the repository is public, a variable is printed in plain text by a step's `env:` block, and it would be compiled into a downloadable artifact. The scripts print `***` for it in a dry run and pass it to `xcodebuild` as the build setting `HASS_DEFAULT_SERVER` when it is non-empty (it lands in Info.plist, [auth](auth.md#default-server-hass_default_server)). Unset, new installs start with a blank Server field; existing installs keep their server from the Keychain. No signing, key or profile step reads it.

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
