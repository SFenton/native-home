# Avatar

> **What:** how a person is drawn as a disc (photo or initials), and how their Home Assistant photo is synced, cached and removed. **Read when:** you draw a person (Profile button, Account header, People rows, anything new), or touch sign-out.

Decision and rules: [design/profile-photos](../design/profile-photos.md). Proposal: [profile-photos](../design/mockups/proposals/profile-photos/profile-photos.html).

## Canonical components

| Piece | Where | Does |
|---|---|---|
| `AvatarView(initials:fill:image:diameter:font:)` | `HassDesign/Avatar/AvatarView.swift` | The one disc. Initials always underneath, photo layer(s) above, 0.5 pt hairline on the photo (white 28% dark, black 18% light), decorative (`accessibilityHidden`). Never draw a person's monogram by hand. |
| `AvatarFade` | `HassDesign/Avatar/AvatarFade.swift` | The layer state machine (none to photo, photo to none, photo to photo). Pure, unit tested. |
| `PersonAvatars`, `AvatarBox` | `HassCore/Profile/PersonAvatars.swift` | `@MainActor @Observable`: one box per `person.*` id (`image`, `revision`), the viewer's person, the sync. In the environment (`AppSession.avatars`). |
| `AvatarSyncPlan` | `HassCore/Profile/AvatarSyncPlan.swift` | Pure `plan(cached:serverPicture:entityLoaded:validatedThisLaunch:)`: `keep`, `revalidate`, `download`, `replace`, `delete`. |
| `PersonAvatarSyncer` | `HassCore/Profile/PersonAvatarSyncer.swift` | Carries a plan out: conditional request, host-scoped Bearer token, store, off-main decode. |
| `PersonAvatarStore` | `HassCore/Profile/PersonAvatarStore.swift` | `Application Support/PersonAvatars`: `<id>.photo` and `<id>.json` per person, `viewer.txt`; excluded from backup. |

## Rules

- **Where it shows.** Profile button (44 pt, signed-in user's person), Account header (84 pt `@ScaledMetric`, same person), every `PersonRow` (36 pt) that has a picture. The Duo rail group keeps the person symbol in SwiftUI; the UIKit rail item draws the photo or monogram as an image (owner, 2026-11-01); `SignInMonogram` keeps initials.
- **Viewer.** The `person.*` entity whose `user_id` equals `auth/current_user`'s id (`AvatarSyncPlan.personID(forUser:in:)`), remembered in `viewer.txt` so a cold launch knows whose photo the button draws before the network answers. `ProfileButton.Presentation` still resolves from the name; a photo never changes it.
- **Change signal.** `entity_picture` minus `token`, `authSig`, `access_token` (`AvatarSyncPlan.pictureKey`, the same rule as `ImagePipeline.key(for:)`; a test pins the list). Same key: one conditional request (`If-None-Match` / `If-Modified-Since`) per launch; a `304` keeps the bytes.
- **Matrix.** No photo and a picture: download, fade in over the initials. Photo and a new picture: download, cross-fade photo to photo (the old layer stays underneath until the new one is in; never through the initials). Photo and a loaded entity with no picture: delete the file, fade onto the initials. Anything else keeps what is there.
- **Never delete on doubt.** Only `AvatarSyncPlan.Action.delete` removes a photo, and only for a *live* (not snapshot) loaded entity without a picture; sign-out removes everything. A failed request, a body over 5 MB or 50 MP, bytes that do not decode (never stored), offline or an entity that has not arrived keeps the cache. Sync does nothing until the store is `.live`. A failure cools down for 5 minutes per picture path. `PersonAvatarStore.generation` (bumped by `removeAll()`) makes writes from a session that has ended refuse themselves, so a late download neither recreates the folder nor deletes the next session's file.
- **Cold launch.** `PersonAvatars.box(for:)` decodes the cached photo (one 512 px ImageIO thumbnail, once per person per launch; stored files passed the download gate) the first time a view asks, so the first frame has the photo and `AvatarView` starts settled, with no fade. A file over 1 MP or one that does not decode never costs the first frame: it is decoded off the main actor, or deleted. A fade plays only when `image` changes while the view is on screen; a change during a fade waits for it (`AvatarFade` coalesces), and the initials disc is hidden once a photo is settled so a transparent photo shows no monogram.
- **Motion.** `MotionTokens.state` (0.6 s; `stateReduced` 0.2 s under Reduce Motion), recorded in `MotionAudit` ("Avatar") and `measuresMotion("Avatar.photo")`. No new duration.
- **Auth.** The Bearer token is sent only when scheme, host and port equal the signed-in server's (`PersonAvatarSyncer.sendsToken`); only `http`/`https` pictures resolve (relative paths against `HassServer.baseURL`); a redirect to another origin drops the header.
- **Main thread.** Observation covers person boxes, `EntityStore.freshness` and `EntityStore.peopleRevision` (bumped only when a `person.*` appears or goes) only, so a light changing never reaches this code; a person's GPS tick (same picture) returns before any disk work. The request, file write and decode run off the main actor; the main actor writes one box once.
- **Sign-out.** `AppSession.signOut()` (so `sessionExpired()` too) calls `PersonAvatars.removeAll()`: stops the watcher, cancels requests, deletes the directory, clears every box. A request that finishes afterwards deletes what it stored.
- **Decoration.** The avatar is `accessibilityHidden`; labels, values and identifiers (`nav.profile`, `account.header`, `profile.person.*`) are unchanged.
- **Gallery.** `FENTON_GALLERY=profile` with `FENTON_GALLERY_PHOTOS=1` shows generated photos for the two demo residents.

## Why not `ImagePipeline`

Photos need to outlive cache trimming (Caches is purgeable, `Clear Image Cache` and the 200 MB trim would drop them), be keyed by person rather than URL, be deleted when the server drops the picture, and be wiped on sign-out. `ImagePipeline` is a size-budgeted URL cache. The avatar store reuses its key rule and the same ImageIO thumbnail technique, nothing else.

## Tests

`HassCoreTests/PersonAvatarTests.swift` (plan matrix, store, syncer with a stub `URLProtocol`, `PersonAvatars` sync and wipe), `HassDesignTests/AvatarFadeTests.swift` (state machine, render), `HassUITests/ProfilePhotoTests.swift` (button, header and row with and without a photo, AX5), `AppSessionTests.signingOutDeletesEveryCachedPhoto`, `YourSummaryFlowTests.photosChangeNothingTheDriverCanRead`.

- **Owned files** (also in `contracts/patterns.json`): `AvatarImage.swift`, `AvatarBox+Image.swift`.
