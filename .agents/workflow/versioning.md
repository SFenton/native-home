# Versioning

> **What:** how S+H gets its version: `YYMM.DD.NN` tags, how a build is stamped, and the `Release-Note` trailers. Ported from FestivalNativeApps (`tools/release/versioning.py`, iOS only). **Read when:** cutting a version, building a release archive, writing a commit that users will notice, or touching `tools/release/**`, the version keys in `apple/project.yml`, or `AppBuildInfo`.

## The scheme

`YYMM.DD.NN` (owner scheme shared with FestivalNativeApps): the **UTC date** of the bump plus a counter that restarts at `01` each day, at most 99 a day. `2610.26.01` is the first version cut on 2026-10-26. A clock behind the newest tag keeps counting on that tag's day, so versions never go backwards.

The ledger is **annotated git tags `ios/v<YYMM.DD.NN>`** on `main` commits. Nothing is committed to bump, so `main` stays clean. The iPhone/iPad app, the widget and notification extensions and the Watch app are one product with one version.

| Store field | Value |
|---|---|
| `CFBundleShortVersionString` (`MARKETING_VERSION`) | the version, three integers (App Store Connect reads `2610.26.01` as 2610.26.1) |
| `CFBundleVersion` (`CURRENT_PROJECT_VERSION`) | a build number that rises with every upload (the CI run number, or `date -u +%Y%m%d%H%M`) |
| `HassGitSHA` (`HASS_GIT_SHA`) | the tagged commit; `dev` locally |

Home Assistant sees the same text: `MobileAppDevice.appVersion` registers `"<marketing> (<build>)"` as `app_version`.

## Cutting a version

```bash
git fetch origin main && git worktree add --detach build/release-wt origin/main && cd build/release-wt   # never the shared primary checkout
python3 tools/release/versioning.py bump --push     # tags HEAD ios/v<next> only if app files changed
```

- A bump happens only when files under the app paths changed since the previous tag (`PLATFORMS` in `versioning.py`: `apple/Sources`, `Package.swift`, `Package.resolved`, `project.yml`, `Apps`, `Design`; Markdown, `apple/Tests` and the two test app folders are excluded). Docs, tests, mockups and tooling never mint a version. `--force` overrides that.
- The first run tags the current `main` as the first version. Re-running on a tagged commit is a no-op (`already_tagged`); a commit older than the newest tag is skipped (`behind_previous_tag`).
- [`ios-release.yml`](../../.github/workflows/ios-release.yml) runs on every push to `main` (and by "Run workflow") and does not wait for `pr-checks` or run any test. Its `bump` job (ubuntu, no secrets, always on) tags `GITHUB_SHA` with `versioning.py bump`; a skipped bump (no app change, already tagged, behind the previous tag) ends the run. When a tag comes out, its `ipa` job (GitHub-hosted macOS, environment `release-signing`) builds and signs the IPA and keeps it as the workflow artifact `FentonHome-<version>` for 30 days, never as a public Release asset; the build number is the UTC `YYYYMMDDHHMM`, the same series as TestFlight. "Run workflow" with `tag` rebuilds an existing tag without bumping, `force` bumps without app changes. Tags are pushed with the workflow token, which triggers no workflow, which is why the `ipa` job is a job of the same workflow. After the artifact, the `ipa` job uploads the same archive to TestFlight (`ios_ipa_build.sh --upload`; no variable, no gate; every bumped version goes; retry with "Run workflow" and `tag`, pause with `gh workflow disable ios-release.yml`) ([ci](ci.md)). There are no `ios/tf/<version>` ledger tags any more. The flow, its ordering guarantee and the **owner checklist** (the `release-signing` environment, the seven secrets, yearly certificate renewal): [testflight](../platforms/apple/testflight.md#release-pipeline-owner-checklist).
- **Dropped runs lose nothing.** GitHub keeps one pending run per concurrency group, so a queued bump or build can be replaced. A bump depends only on the commit ("did app files change since the previous tag"), so the newest CI-passed head covers every earlier merge and an older head that runs late is `behind_previous_tag`. Each tag is built and uploaded by its own `ipa` run ([testflight](../platforms/apple/testflight.md)).
- Mark what shipped to the App Store by tagging `ios/released/<version>`; `pending-notes` compares against the newest such tag.

## Building a release archive

Local and simulator builds keep `0.1.0 (1)`: only a build that is handed the tag's numbers carries the version. Ask the tool for the exact `xcodebuild` arguments instead of typing them:

```bash
git worktree add --detach build/release-wt ios/v2610.26.01 && cd build/release-wt   # build the tagged commit in a detached worktree
cd apple && xcodegen generate
xcodebuild archive -project FentonHome.xcodeproj -scheme FentonHome -destination 'generic/platform=iOS' \
  $(python3 ../tools/release/versioning.py build-settings --tag ios/v2610.26.01 --build "$(date -u +%Y%m%d%H%M)")
```

`HASS_DEFAULT_SERVER` is a build setting too, but not a version: the sign-in default server, blank in every `ios-release.yml` build (the artifact and the TestFlight upload); only a manual local `testflight_upload.sh` run passes it on the command line, from the owner's own shell (never a repository variable) ([testflight](../platforms/apple/testflight.md#default-server-manual-uploads-only)); empty in `apple/project.yml`.

`build-settings` prints `MARKETING_VERSION=…`, `CURRENT_PROJECT_VERSION=…` and `HASS_GIT_SHA=…`, one per line. Command-line settings override `apple/project.yml`'s project-wide defaults for **every** target, so the app, both extensions, the widget and the Watch app (generated Info.plist) ship matching versions; a mismatch makes App Store Connect reject the embedded watch app. `describe --tag T [--build N]` prints the facts as JSON. `ReleaseVersionStampingTests` fails if a target stops reading these settings or the Watch app pins its own.

## Showing it

`AppBuildInfo.versionText(Bundle.main.infoDictionary)` formats `2610.26.01 (57) · 42edc57`; `spokenVersionText` is the VoiceOver reading (`2610.26.01, build 57, commit 42edc57`). A local build shows `0.1.0 (1)` with no commit. Settings → About → Version shows and copies it ([settings-version-row](../design/settings-version-row.md), proposal [mockup](../design/mockups/proposals/settings-version-row/settings-version-row.html)).

## Release-note trailers

Notes come from commit-message trailers on the first-parent history between two tags. Write one for any change a person will see, in the commit message (merged PRs are read through their commits):

```
Release-Note: Rooms: The room list loads faster.     any change that touched the app paths
Release-Note-iOS: Cameras: The live view opens sooner.    iOS only, wins over the generic note
Release-Note: none                                    nothing user-facing (refactor, internal fix)
Release-Note-Replaces: The room list loads slowly.    drop an earlier note this change supersedes
Release-Note-Tester: Fixed the new refresh crash.     for testers only (a fix to something no release had)
```

`tools/ship.sh "Subject" --note "Rooms: The room list loads faster."` adds the trailer to the commit. A note starts with a category from `CATEGORIES` in `versioning.py` (Home, Rooms, Security, Cameras, Climate, Lights, …, General) and a space; without one the keyword rules in `CATEGORY_RULES` guess. Notes are specific, in the user's words, never "Bug fixes and improvements".

Each merged pull request is one entry: its trailers, or its cleaned title (no `[Bug]` prefix or `(#n)` suffix) when it has none. Commits pushed straight to `main` without a trailer contribute nothing. Notes are the **net** difference: a `Release-Note-Replaces` target and anything a `This reverts commit` undoes drop out of the range.

- `versioning.py check-notes --base <sha> --head <sha> [--body-file pr.md]` exits 1 when a change touches the app paths without any `Release-Note…` trailer (`none` is fine). Run it before a PR; there is no CI gate yet.
- `versioning.py pending-notes [--released 2610.26.01]` lists what users will get that the latest release lacks: what a change may `Replaces`.

## Not ported (yet)

FestivalNativeApps also generates an in-app **What's New** (`WhatsNew.json`), TestFlight "What to Test" text and store text from these notes, and reads released versions from App Store Connect (the bump and the TestFlight archive/upload do run from GitHub Actions now, see above; there is no release train: every green app merge is a version). None of that exists here; the notes and tags are the inputs it will need. `TODO(orchestrator): port What's New once the owner wants it (propose-first applies: it is a new sheet).`

## Tests

`python3 -m unittest discover -s tools/release/tests -t .` (versions, tags, trailers, net notes and the CLI in throwaway git repos; no network), plus `test_release_workflows` (the workflow triggers, secrets, the upload step's order and the retired path as assertions; run by `tools/run_tool_tests.sh`) and `tools/tests/test_ipa_build.py` (the `--upload` dry run). Swift: `AppBuildInfoTests`, `ReleaseVersionStampingTests` in `HassCoreTests`.
