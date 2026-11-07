import Foundation

/// Keeps one webhook per Home Assistant user, so signing in again as the same person reuses the phone's
/// `mobile_app` device instead of adding another (contract v1, rule 2). The production store is
/// ``KeychainMobileAppRegistrationStore``.
///
/// It is also the ``MobileAppWebhookSource`` location and sensors send through: the signed-in user's webhook, read
/// when each command is sent, so a re-registration takes effect at once and sign-out stops every sender.
public protocol MobileAppRegistrationStore: MobileAppWebhookSource {
    /// The saved registration for a user, if any.
    func registration(server: HassServer, userID: String) -> MobileAppRegistration?
    /// Saves a registration, replacing the user's previous one.
    func save(_ registration: MobileAppRegistration)
    /// Forgets a user's registration (Home Assistant deleted it).
    func remove(server: HassServer, userID: String)
    /// The registration of the user signed in now: notification buttons, location and sensors use it.
    var active: MobileAppRegistration? { get }
    /// Marks the signed-in user's registration; nil after sign-out.
    func setActive(_ registration: MobileAppRegistration?)
    /// Removals not yet confirmed by Home Assistant; they outlive a relaunch.
    var pendingUnregisters: [PendingUnregister] { get }
    /// Queues a removal to retry.
    func addPending(_ entry: PendingUnregister)
    /// Drops a removal that was confirmed (or can never succeed).
    func removePending(_ entry: PendingUnregister)
}

public extension MobileAppRegistrationStore {
    /// The signed-in user's webhook, or nil when signed out or not registered yet.
    func currentWebhook() async -> MobileAppWebhook? { active?.webhook }
}
