#if DEBUG
import Foundation
import HassCore
import HassDesign
import Observation
import SwiftUI

/// What iOS would say, scripted for the gallery pages: the notification answer, the Time Sensitive switch and the
/// location permission change as the journey taps, as they do for a person answering the system alerts.
@MainActor
final class SetupGallerySystem {
    var status: PushAuthorization
    var timeSensitive: TimeSensitiveSetting
    /// Whether the person taps Allow on the notification alert.
    let allows: Bool
    /// Every step the journey took, newest last.
    private(set) var actions: [String] = []

    init(environment: [String: String]) {
        let notifications = environment["FENTON_GALLERY_NOTIFICATIONS"] ?? "not-determined"
        status = switch notifications {
        case "denied": .denied
        case "not-determined": .notDetermined
        default: .granted
        }
        timeSensitive = switch environment["FENTON_GALLERY_TIME_SENSITIVE"] ?? "on" {
        case "off": .disabled
        case "unsupported": .notSupported
        default: .enabled
        }
        allows = environment["FENTON_GALLERY_ALLOW"] != "0"
    }

    func record(_ action: String) { actions.append(action) }

    var platform: PushPlatform {
        PushPlatform(
            device: { MobileAppDevice(marketingVersion: "1", build: "1", name: "Gallery", model: "iPhone18,1", osVersion: "27",
                                 deviceID: "gallery", apnsEnvironment: .sandbox) },
            authorization: { await MainActor.run { self.status } },
            timeSensitiveSetting: { await MainActor.run { self.timeSensitive } },
            requestAuthorization: {
                await MainActor.run {
                    self.record("notification alert")
                    if self.status == .notDetermined { self.status = self.allows ? .granted : .denied }
                    return self.allows
                }
            },
            registerForRemoteNotifications: {}, deliveredNotifications: { [] }, removeDelivered: { _ in }, openExternal: { _ in })
    }

    /// A push coordinator on this system, connected as a signed-in session would be.
    func makePush() -> PushCoordinator {
        let push = PushCoordinator(platform: platform, store: InMemoryMobileAppRegistrationStore(), isEnabled: false,
                                   defaults: UserDefaults(suiteName: "gallery-setup-\(UUID().uuidString)")!)
        push.simulateConnected()
        return push
    }
}

/// A location platform that answers like the person choosing the highlighted option in each alert.
@MainActor
final class GalleryLocationPlatform: LocationPlatform {
    var permission: LocationPermission
    var onEvent: (@MainActor (LocationPlatformEvent) -> Void)?

    init(_ permission: LocationPermission) { self.permission = permission }

    func requestWhenInUse() { answer(LocationPermission(authorization: .whenInUse)) }
    func requestAlways() { answer(LocationPermission(authorization: .always)) }
    func currentFix(timeout: TimeInterval, notBefore: Date?) async throws -> LocationFix { throw LocationPlatformError.unavailable }
    func lastKnownFix() async -> LocationFix? { nil }
    func openZoneMonitor() async {}
    func satisfiedRegions() async -> Set<String> { [] }
    func startSignificantChanges() {}
    func stopSignificantChanges() {}
    func monitor(_ regions: [PlannedRegion]) async {}
    func stopMonitoring() async {}

    private func answer(_ new: LocationPermission) {
        permission = new
        onEvent?(.permissionChanged(new))
    }
}

/// The Setup gallery's fixtures, shared with the UIKit port's gallery: the scripted system, and the coordinator over it with a
/// location platform that answers like the person choosing the highlighted option.
@MainActor
struct SetupGalleryFixtures {
    let system: SetupGallerySystem
    let setup: SetupCoordinator
    /// `FENTON_GALLERY_SETUP`: where the flow starts.
    let start: String

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let system = SetupGallerySystem(environment: environment)
        let push = system.makePush()
        let defaults = UserDefaults(suiteName: "gallery-setup-flow-\(UUID().uuidString)")!
        if environment["FENTON_GALLERY_LOCATION_SEEN"] == "1" { defaults.set(true, forKey: LocationCoordinator.offeredKey) }
        let location = LocationCoordinator(platform: GalleryLocationPlatform(.notDetermined), mobileApp: push.mobileApp,
                                           defaults: defaults)
        self.system = system
        self.setup = SetupCoordinator(push: push, location: location, defaults: defaults)
        start = environment["FENTON_GALLERY_SETUP"] ?? "flow"
    }
}

/// Gallery page for Settings → Notifications: the section in each state, in a list as the Settings page draws it. Opening
/// a row is recorded on the `Last action` line instead of leaving the app.
///
/// Environment: `FENTON_GALLERY_NOTIFICATIONS=not-determined|denied|on` and `FENTON_GALLERY_TIME_SENSITIVE=on|off|unsupported`.
@MainActor
struct NotificationSettingsGallery {
    /// The push coordinator on the scripted system, shared with the UIKit port's gallery.
    static func makePush(environment: [String: String]) -> PushCoordinator {
        var environment = environment
        // "on" is the granted state; the shared scripted system reads anything else as granted too.
        if environment["FENTON_GALLERY_NOTIFICATIONS"] == nil { environment["FENTON_GALLERY_NOTIFICATIONS"] = "on" }
        return SetupGallerySystem(environment: environment).makePush()
    }
}
#endif
