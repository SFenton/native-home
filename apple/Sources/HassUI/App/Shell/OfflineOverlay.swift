/// The offline chip's spoken copy (the chip itself is `UKOfflineChip`).
enum OfflineOverlay {
    /// What is spoken when the chip appears (`true`) or clears.
    static func announcement(isOffline: Bool) -> String {
        isOffline ? "You're offline. Showing the last values." : "Back online."
    }
}
