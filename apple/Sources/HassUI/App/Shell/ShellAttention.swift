import HassCore

/// The attention count the Profile button shows, shared with the app icon badge.
@MainActor
public enum ShellAttention {
    /// Overdue chores plus expired food; zero until the viewer is a known resident, as on the web.
    public static func count(store: EntityStore?, viewerUserId: String?) -> Int {
        guard let store, let viewer = ChoresConfig.Resident.forUserId(viewerUserId) else { return 0 }
        return ProfileSummary.counts(viewer: viewer, store: store).attention
    }
}
