import Foundation

/// What to do about one person's cached photo, given what is on disk and what Home Assistant says
/// (design: `.agents/design/profile-photos.md`, pattern: `.agents/patterns/avatar.md`).
///
/// A pure function so the whole matrix is unit tested without a network or a file system. The one rule that
/// matters most: **a photo is deleted only when the person's entity has loaded and has no picture**. Every other
/// doubt keeps the cache.
public enum AvatarSyncPlan {
    /// The step to take.
    public enum Action: Equatable, Sendable {
        /// Leave the cached photo (or the lack of one) as it is.
        case keep
        /// Same picture path as the cache, not yet asked this launch: conditional request (`If-None-Match` /
        /// `If-Modified-Since`); a `304` keeps the file.
        case revalidate
        /// Nothing cached and the server has a picture: fetch it, store it, fade from the initials.
        case download
        /// Cached, and the server's picture path changed: fetch it, store it, cross-fade photo to photo.
        case replace
        /// Cached, the entity has loaded and has no picture: delete the file, fade to the initials.
        case delete
    }

    /// Query items that only authorize a picture URL; they are not part of its identity. The same set as
    /// `ImagePipeline.volatileQueryItems` (HassCore cannot import HassDesign, so a test pins the list).
    public static let volatileQueryItems: Set<String> = ["token", "authSig", "access_token"]

    /// The change signal for a picture path: the path with ``volatileQueryItems`` removed, so a rotated token is not a
    /// new photo. Same rule as `ImagePipeline.key(for:)`.
    public static func pictureKey(_ picture: String) -> String {
        guard var components = URLComponents(string: picture) else { return picture }
        if let items = components.queryItems {
            let kept = items.filter { !volatileQueryItems.contains($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        return components.string ?? picture
    }

    /// Decides the step.
    /// - Parameters:
    ///   - cached: The sidecar of the photo on disk, nil when there is none.
    ///   - serverPicture: The person's `entity_picture` attribute; nil or empty when the entity has none.
    ///   - entityLoaded: The person's entity has arrived live. False (not loaded, snapshot only, offline) never deletes.
    ///   - validatedThisLaunch: The same path was already confirmed with the server in this launch.
    public static func plan(cached: PersonAvatarStore.Metadata?, serverPicture: String?, entityLoaded: Bool,
                            validatedThisLaunch: Bool = false) -> Action {
        // Not loaded: the server has not been heard from, so nothing changes (never delete on doubt).
        guard entityLoaded else { return .keep }
        let picture = serverPicture.flatMap { $0.isEmpty ? nil : $0 }
        switch (cached, picture) {
        case (nil, nil): return .keep
        case (nil, .some): return .download
        case (.some, nil): return .delete
        case let (.some(cached), .some(picture)):
            if cached.pictureKey != pictureKey(picture) { return .replace }
            return validatedThisLaunch ? .keep : .revalidate
        }
    }

    /// The `person.*` entity that belongs to a signed-in user: the one whose `user_id` attribute equals the user's id
    /// (the same match `HassConnection.isHomeConfirmedOverPublicURL` makes).
    public static func personID(forUser userID: String, in states: some Sequence<EntityState>) -> String? {
        states.first { $0.domain == "person" && $0.attributes["user_id"]?.string == userID }?.entityId
    }
}
