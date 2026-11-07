import Foundation
import HassCore
import HassUI
import UIKit
import UserNotifications

extension PushPlatform {
    /// UIKit and UserNotifications.
    @MainActor
    static let system = PushPlatform(
        device: { SystemDevice.current() },
        authorization: {
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .notDetermined: .notDetermined
            case .denied: .denied
            default: .granted
            }
        },
        timeSensitiveSetting: {
            switch await UNUserNotificationCenter.current().notificationSettings().timeSensitiveSetting {
            case .enabled: .enabled
            case .disabled: .disabled
            default: .notSupported
            }
        },
        requestAuthorization: {
            (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        },
        registerForRemoteNotifications: { UIApplication.shared.registerForRemoteNotifications() },
        deliveredNotifications: {
            await UNUserNotificationCenter.current().deliveredNotifications().map { notification in
                DeliveredNotification(identifier: notification.request.identifier,
                                      tag: PushPayload(userInfo: notification.request.content.userInfo)?.tag)
            }
        },
        removeDelivered: { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: $0) },
        openExternal: { UIApplication.shared.open($0) }
    )
}

/// This phone's registration facts (contract v1, rule 2).
enum SystemDevice {
    @MainActor
    static func current(bundle: Bundle = .main) -> MobileAppDevice {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        let profile = bundle.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
        return MobileAppDevice(
            marketingVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            name: UIDevice.current.name,
            model: hardwareModel(),
            osVersion: UIDevice.current.systemVersion,
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            apnsEnvironment: APNsEnvironment.detect(provisioningProfile: profile, isSimulator: isSimulator),
            appID: bundle.bundleIdentifier ?? PushApp.appID
        )
    }

    /// `hw.machine`, e.g. `iPhone18,1`; the simulator reports the device it simulates.
    static func hardwareModel() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(decoding: machine.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}

/// Whether push registers and prompts in this launch.
enum PushLaunchPolicy {
    /// Off for debug UI journeys (a test token, a reset launch, or the component gallery) unless `FENTON_PUSH=1`,
    /// so a journey never meets the permission alert and never adds a `mobile_app` device to the real server.
    static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        #if DEBUG
        if environment["FENTON_PUSH"] == "1" { return true }
        let journey = ["FENTON_HASS_TOKEN", "FENTON_UITEST_RESET", "FENTON_GALLERY"].contains { !(environment[$0] ?? "").isEmpty }
        return !journey
        #else
        return true
        #endif
    }
}
