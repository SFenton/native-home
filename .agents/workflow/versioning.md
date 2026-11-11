# Versioning

> **What:** how S+H gets its version, how a build is stamped, and the release-note trailers. **Read when:** writing a commit, cutting a version, building a release archive, or touching `tools/release/`.

## Versions

- A version is `YYMM.DD.NN`: the UTC date of the bump plus a counter that restarts each day. Versions never go backwards.
- The ledger is annotated git tags `ios/v<version>` on `main` commits. A version is cut by `tools/release/versioning.py bump`, never by a commit.
- A bump happens only when files under the app paths changed after the previous tag; docs, tests, mockups and tooling never mint a version. The path list is `PLATFORMS` in `versioning.py`.
- The app, its extensions, the widget and the Watch app are one product with one version.
- `ios/released/<version>` tags mark what shipped to the App Store.

## Builds

- A release build is stamped with the output of `versioning.py build-settings`; nobody types the version numbers by hand. Local and simulator builds stay `0.1.0 (1)`.
- The stamp reaches every target, so all of them ship matching versions.
- `ios-release.yml` builds, signs and uploads every bumped version to TestFlight ([testflight](../platforms/apple/testflight.md)). The signed build stays a workflow artifact, never a public release asset.
- A version is cut or built from a detached worktree, never the shared primary checkout.
- Signing and the release pipeline are [owner-only](autonomy.md#owner-only).

## Release notes

Release notes are assembled from commit-message trailers on the first-parent history between two tags. Every commit that touches the app paths carries one; `tools/ship.sh --note` adds it.

| Trailer | Use |
|---|---|
| `Release-Note: <Category>: <text>` | A change a person will notice |
| `Release-Note-iOS: <text>` | iOS only; wins over the generic note |
| `Release-Note: none` | Nothing user-facing |
| `Release-Note-Replaces: <earlier note>` | Drops the earlier note this change replaces |
| `Release-Note-Tester: <text>` | For testers only: a fix to something no release had |

- A note starts with a category from `CATEGORIES` in `versioning.py`, is specific, and uses the user's words.
- Each merged pull request is one entry. Notes are the net difference: a replaced note and a reverted change drop out.
- `versioning.py check-notes` exits 1 when a change touches the app paths without a trailer; `versioning.py pending-notes` lists what the next release adds.
- A work-in-progress commit on a lane needs no trailer; the squash or the pull request carries it.
