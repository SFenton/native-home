# Profile photos

> **What:** the decision and rules for showing a person's Home Assistant photo in place of their initials. **Read when:** you touch the Profile button, the Account header, the People rows, or anything that draws a person.

Proposal: [profile-photos](mockups/proposals/profile-photos/profile-photos.html) (2026-10-27). Pattern: [avatar](../patterns/avatar.md).

## Goal

Alex and Sam have a photo on their Home Assistant `person` entity. The app fetches it on launch, keeps it on the device, and draws it instead of their initials on the Profile button, the Account sheet header and the People at Home rows. It fades in, out or across when the server's picture changes. Sign-out deletes every cached photo.

## Decision

Owner brief 2026-10-27, "mockups and animated mockups, propose code, implement": taken as the go-ahead for the recommended options.

- **Option A, photo fills the disc** (over B, photo with an identity ring). A 0.5 pt hairline outlines it on every surface (white 28% on dark, black 18% on light). Chore colours stay on the initials fallback.
- **Fade: `MotionTokens.state`** (0.6 s ease-in-out; 0.2 s under Reduce Motion) through `motionSafeAnimation`. No new token.

## Rules

- **Source.** `person.*` `entity_picture` through `EntityStore`; no second request path for state. The signed-in user's person is the one whose `user_id` equals `auth/current_user`'s id. Every person with a picture gets a photo (guests too).
- **Change signal.** The picture path, with `token`, `authSig` and `access_token` removed (`ImagePipeline.key(for:)`). The same path is revalidated with `If-None-Match` / `If-Modified-Since` at most once per launch.
- **Never delete on doubt.** A photo is deleted only when the person's entity has loaded and has no `entity_picture`. A failed or offline request, or an entity that has not arrived, keeps the cached file.
- **Cold launch.** The cached photo draws on the first frame with no fade. A fade plays only when the image changes while the view is on screen.
- **Replace.** A new photo fades in over the old one, never through the initials.
- **Storage.** Application Support, one file and one sidecar per person, excluded from backup. Sign-out and an expired session (`AppSession.signOut()`) delete all of it and the in-memory images. The store has a lock-guarded generation that sign-out bumps: a download that began before a sign-out can neither recreate the folder nor delete or replace a file the next session saved (a late result is refused, not cleaned up).
- **Auth.** The Bearer token is sent only when the picture URL's scheme, host and port equal the signed-in server's (so over https only in practice); a redirect to another origin drops it. Only `http` and `https` pictures are fetched.
- **Limits.** A photo response is at most 5 MB (streamed, whole request 30 s) and 50 megapixels by its header, and must decode before it is stored; anything else keeps the cache. A failed picture is not asked for again for five minutes (a new picture path is asked at once), so a 404 is not retried on every position update. The same bytes sent again change nothing on screen.
- **Accessibility.** The avatar stays decorative; the name is read from the button or row. The bar disc stays 44 pt; the Account avatar and rows scale with Dynamic Type.
- **Unchanged.** The Duo rail group keeps the person symbol; the welcome-back sign-in monogram keeps initials.

## Owner answers (2026-10-27)

- **Expired session:** yes, a refused token also deletes the cached photos (`sessionExpired()` calls `signOut()`); the welcome-back sign-in shows initials.
- **Guests:** yes, People at Home shows a photo for every `person.*` with a picture, guests included, not only the two residents.
